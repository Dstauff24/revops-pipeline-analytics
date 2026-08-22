"""
One command build: generate the synthetic data, create the
database, load it, verify it.

    python setup.py

This is a task script, not a packaging file. There is nothing to
install from this repository. Running it twice is safe: it drops
and rebuilds pipeline.duckdb from scratch.

ALL DATA IS SYNTHETIC. See data/generate.py and data/README.md.
"""

import os
import subprocess
import sys

import duckdb

ROOT = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(ROOT, "pipeline.duckdb")
SCHEMA_PATH = os.path.join(ROOT, "schema", "01_tables.sql")
CSV_DIR = os.path.join(ROOT, "data", "csv")
GENERATOR = os.path.join(ROOT, "data", "generate.py")

TABLES = ["territories", "reps", "accounts", "opportunities",
          "leads", "stage_history", "activities"]


def generate_data():
    print("[1/4] Generating synthetic data")
    result = subprocess.run([sys.executable, GENERATOR], cwd=ROOT)
    if result.returncode != 0:
        sys.exit("Data generation failed.")


def build_database():
    print("\n[2/4] Building pipeline.duckdb")
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    con = duckdb.connect(DB_PATH)
    with open(SCHEMA_PATH) as fh:
        con.execute(fh.read())

    print("\n[3/4] Loading tables")
    for table in TABLES:
        csv_path = os.path.join(CSV_DIR, f"{table}.csv")
        con.execute(
            f"COPY {table} FROM '{csv_path}' (FORMAT CSV, HEADER TRUE, NULLSTR '')"
        )
        n = con.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
        print(f"      {table:<16} {n:>8,} rows")
    return con


def verify(con):
    print("\n[4/4] Verifying")
    checks = [
        ("every table has rows",
         "SELECT count(*) FROM (" +
         " UNION ALL ".join(f"SELECT '{t}' AS t, count(*) AS n FROM {t}" for t in TABLES) +
         ") WHERE n = 0", 0),
        ("opportunities point at real accounts",
         "SELECT count(*) FROM opportunities o "
         "LEFT JOIN accounts a USING (account_id) WHERE a.account_id IS NULL", 0),
        ("stage history points at real opportunities",
         "SELECT count(*) FROM stage_history s "
         "LEFT JOIN opportunities o USING (opportunity_id) WHERE o.opportunity_id IS NULL", 0),
        ("activities point at real opportunities",
         "SELECT count(*) FROM activities a "
         "LEFT JOIN opportunities o USING (opportunity_id) WHERE o.opportunity_id IS NULL", 0),
    ]
    failed = False
    for label, sql, expected in checks:
        actual = con.execute(sql).fetchone()[0]
        ok = actual == expected
        failed = failed or not ok
        print(f"      [{'ok' if ok else 'FAIL'}] {label}")

    # These are the deliberate defects. If they are missing, the
    # generator changed and query 12 has nothing to find.
    dirt = con.execute("""
        SELECT
          count(*) FILTER (WHERE amount IS NULL)                              AS null_amount,
          count(*) FILTER (WHERE actual_close_date < created_date)            AS backwards_dates,
          count(*) FILTER (WHERE stage IN ('Closed Won','Closed Lost')
                             AND actual_close_date IS NULL)                   AS closed_no_date
        FROM opportunities
    """).fetchone()
    print(f"      [info] deliberate defects present: "
          f"{dirt[0]} null amounts, {dirt[1]} reversed dates, {dirt[2]} closed with no date")
    if min(dirt) == 0:
        print("      [FAIL] expected deliberate defects are missing")
        failed = True

    if failed:
        sys.exit("\nVerification failed.")
    print("\nDone. Database at pipeline.duckdb")
    print("Next: python run_all.py")


if __name__ == "__main__":
    generate_data()
    con = build_database()
    verify(con)
    con.close()
