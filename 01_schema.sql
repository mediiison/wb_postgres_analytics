CREATE TABLE IF NOT EXISTS articles (
    article  text PRIMARY KEY,
    category text NOT NULL DEFAULT 'Без категории'
);

CREATE TABLE IF NOT EXISTS sales (
    sale_date date           NOT NULL,
    article   text           NOT NULL REFERENCES articles (article),
    qty       numeric(12, 2) NOT NULL CHECK (qty >= 0),
    revenue   numeric(14, 2) NOT NULL,
    PRIMARY KEY (sale_date, article)
);

CREATE INDEX IF NOT EXISTS idx_sales_article_date ON sales (article, sale_date);

CREATE TABLE IF NOT EXISTS etl_runs (
    id          bigserial PRIMARY KEY,
    loaded_at   timestamptz NOT NULL DEFAULT now(),
    source_file text        NOT NULL,
    rows_loaded integer     NOT NULL
);
