# WB Postgres Analytics

Хранилище продаж в PostgreSQL с аналитикой на чистом SQL: ABC/XYZ-классификация ассортимента, динамика выручки, скользящие средние, поиск неходовых артикулов. 

Продолжение проектов `wb_stock_signal` и `abc_xyz_dashboard`: тот же формат данных, та же методика ABC/XYZ, но расчёт выполняется внутри базы.

## Структура

| Файл | Назначение |
|---|---|
| `docker-compose.yml` | PostgreSQL 16 для локального запуска |
| `sql/01_schema.sql` | таблицы `articles`, `sales`, `etl_runs`, индексы |
| `sql/02_views.sql` | представления и материализованное представление для ABC/XYZ |
| `sql/reports/*.sql` | параметризованные аналитические запросы |
| `load_data.py` | загрузка CSV в базу |
| `report.py` | запуск отчётов из командной строки |
| `data/sales.csv` | демо-датасет: 150 артикулов, 12 месяцев |

## Схема данных

```
articles (article PK, category)
sales    (sale_date, article FK -> articles, qty, revenue, PK (sale_date, article))
etl_runs (id, loaded_at, source_file, rows_loaded)
```

Индекс `idx_sales_article_date` по `(article, sale_date)` ускоряет выборки по артикулу, первичный ключ покрывает запросы по диапазону дат.

## Представления

| Объект | Содержание |
|---|---|
| `v_article_revenue` | выручка и количество по артикулу |
| `v_abc` | доля и накопленная доля выручки, класс A/B/C (оконные функции `SUM() OVER`) |
| `mv_monthly_qty` | материализованное представление: продажи по месяцам, включая нулевые, только полные месяцы |
| `v_xyz` | коэффициент вариации спроса и класс X/Y/Z (`STDDEV_POP / AVG`) |
| `v_abc_xyz` | сводка по артикулам с сегментом (AX ... CZ) |
| `v_segment_matrix` | матрица сегментов: число артикулов и доля выручки (`COUNT(*) FILTER`) |

Границы классов: A до 80% выручки, B до 95%, C остальное; X при CV до 0.25, Y до 0.5, Z выше. Меняются в `sql/02_views.sql`.

Результат `v_segment_matrix` на демо-данных совпадает с расчётом в pandas из `abc_xyz_dashboard` по всем ячейкам матрицы.

## Установка

```bash
pip install -r requirements.txt
docker compose up -d
```

Строка подключения берётся из переменной `DATABASE_URL` (пример в `.env.example`), по умолчанию `postgresql://wb:wb@localhost:5432/wb_analytics`. Учётные данные в `docker-compose.yml` предназначены только для локальной разработки.

## Загрузка данных

```bash
python load_data.py --csv data/sales.csv
```

Загрузчик создаёт таблицы, полностью перезаливает данные через `COPY` и пересоздаёт представления. Повторный запуск безопасен. Дубли по паре дата/артикул суммируются. Каждый запуск пишется в `etl_runs`.

Формат CSV: `date`, `article`, `qty`, `revenue`, `category` (необязательно).

## Отчёты

```bash
python report.py matrix
python report.py top --n 5
python report.py monthly
python report.py moving --article HLP-001 --window 7
python report.py idle --days 14
python report.py segment --segment CZ
```

| Отчёт | Приёмы SQL |
|---|---|
| `matrix` | агрегаты с `FILTER`, представления поверх представлений |
| `top` | `ROW_NUMBER() OVER (PARTITION BY category ...)` |
| `monthly` | `LAG()` для прироста месяц к месяцу |
| `moving` | `generate_series`, `LEFT JOIN` для нулевых дней, скользящее среднее `AVG() OVER (ROWS BETWEEN ...)` |
| `idle` | `HAVING` и арифметика дат |
| `segment` | список артикулов выбранного сегмента |

Любой отчёт можно сохранить в файл: `--csv result.csv`.

Те же запросы можно запускать напрямую в `psql`, например:

```sql
SELECT * FROM v_abc_xyz WHERE segment = 'AZ' ORDER BY revenue DESC;
```

## Обновление после загрузки новых данных

`load_data.py` пересоздаёт материализованное представление сам. При ручной догрузке строк в `sales` его нужно обновить:

```sql
REFRESH MATERIALIZED VIEW mv_monthly_qty;
```

## Ограничения

- Загрузка полная (с очисткой таблиц), инкрементальной догрузки нет.
- XYZ считается по полным календарным месяцам, неполные крайние месяцы отбрасываются.
- Новые артикулы с короткой историей получают завышенный CV и попадают в Z.
