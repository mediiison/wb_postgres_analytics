import argparse
import os
from pathlib import Path

import pandas as pd
import psycopg

ROOT = Path(__file__).parent
SQL_DIR = ROOT / "sql"
DEFAULT_DSN = "postgresql://wb:wb@localhost:5432/wb_analytics"
REQUIRED_COLUMNS = ["date", "article", "qty", "revenue"]


def read_csv(path):
    df = pd.read_csv(path)
    missing = [c for c in REQUIRED_COLUMNS if c not in df.columns]
    if missing:
        raise ValueError(f"Missing columns: {', '.join(missing)}")
    df["date"] = pd.to_datetime(df["date"]).dt.date
    df["article"] = df["article"].astype(str)
    if "category" not in df.columns:
        df["category"] = "Без категории"
    return df[["date", "article", "category", "qty", "revenue"]]


def run_sql_file(conn, name):
    conn.execute((SQL_DIR / name).read_text(encoding="utf-8"))


def load_rows(conn, df, source):
    conn.execute("TRUNCATE sales, articles")
    with conn.cursor() as cur:
        cur.execute(
            "CREATE TEMP TABLE stg ("
            "sale_date date, article text, category text, qty numeric, revenue numeric"
            ") ON COMMIT DROP"
        )
        with cur.copy("COPY stg (sale_date, article, category, qty, revenue) FROM STDIN") as copy:
            for row in df.itertuples(index=False, name=None):
                copy.write_row(row)
        cur.execute(
            "INSERT INTO articles (article, category) "
            "SELECT article, MIN(category) FROM stg GROUP BY article"
        )
        cur.execute(
            "INSERT INTO sales (sale_date, article, qty, revenue) "
            "SELECT sale_date, article, SUM(qty), SUM(revenue) FROM stg GROUP BY sale_date, article"
        )
        cur.execute(
            "INSERT INTO etl_runs (source_file, rows_loaded) VALUES (%s, %s)",
            (source, len(df)),
        )


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--csv", default="data/sales.csv")
    p.add_argument("--dsn", default=os.environ.get("DATABASE_URL", DEFAULT_DSN))
    args = p.parse_args()

    df = read_csv(args.csv)

    with psycopg.connect(args.dsn) as conn:
        run_sql_file(conn, "01_schema.sql")
        load_rows(conn, df, Path(args.csv).name)
        run_sql_file(conn, "02_views.sql")
        conn.execute("ANALYZE sales")
        conn.execute("ANALYZE articles")

        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*), COUNT(DISTINCT article), MIN(sale_date), MAX(sale_date) FROM sales")
            rows, articles, d_min, d_max = cur.fetchone()

    print(f"Loaded {rows} sales rows, {articles} articles, {d_min} - {d_max}")


if __name__ == "__main__":
    main()
