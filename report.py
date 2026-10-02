import argparse
import os
from pathlib import Path

import pandas as pd
import psycopg

SQL_DIR = Path(__file__).parent / "sql" / "reports"
DEFAULT_DSN = "postgresql://wb:wb@localhost:5432/wb_analytics"


def run_report(dsn, name, params):
    query = (SQL_DIR / f"{name}.sql").read_text(encoding="utf-8")
    with psycopg.connect(dsn) as conn:
        with conn.cursor() as cur:
            cur.execute(query, params)
            columns = [c.name for c in cur.description]
            rows = cur.fetchall()
    return pd.DataFrame(rows, columns=columns)


def build_parser():
    p = argparse.ArgumentParser()
    p.add_argument("--dsn", default=os.environ.get("DATABASE_URL", DEFAULT_DSN))
    p.add_argument("--csv", default="")
    sub = p.add_subparsers(dest="report", required=True)

    sub.add_parser("matrix")

    top = sub.add_parser("top")
    top.add_argument("--n", type=int, default=5)

    sub.add_parser("monthly")

    moving = sub.add_parser("moving")
    moving.add_argument("--article", required=True)
    moving.add_argument("--window", type=int, default=7)
    moving.add_argument("--tail", type=int, default=30)

    idle = sub.add_parser("idle")
    idle.add_argument("--days", type=int, default=14)

    segment = sub.add_parser("segment")
    segment.add_argument("--segment", required=True)

    return p


def main():
    args = build_parser().parse_args()

    if args.report == "matrix":
        df = run_report(args.dsn, "matrix", {})
    elif args.report == "top":
        df = run_report(args.dsn, "top_by_category", {"n": args.n})
    elif args.report == "monthly":
        df = run_report(args.dsn, "monthly_growth", {})
    elif args.report == "moving":
        df = run_report(
            args.dsn,
            "moving_average",
            {"article": args.article, "preceding": args.window - 1},
        ).tail(args.tail)
    elif args.report == "idle":
        df = run_report(args.dsn, "idle_articles", {"days": args.days})
    else:
        df = run_report(args.dsn, "segment", {"segment": args.segment.upper()})

    if df.empty:
        print("No rows")
    else:
        print(df.to_string(index=False))

    if args.csv:
        df.to_csv(args.csv, index=False, encoding="utf-8-sig")
        print(f"Saved: {args.csv}")


if __name__ == "__main__":
    main()
