"""
Run every query in queries/ against pipeline.duckdb, print the
results, and exit nonzero if any of them fails.

    python run_all.py            # all queries, first 15 rows each
    python run_all.py 03 08      # just those, full output
    python run_all.py --rows 50  # more rows

A portfolio repo with a query that does not run is worse than no
repo, so this is wired to fail loudly rather than skip.

ALL DATA IS SYNTHETIC. See data/generate.py and data/README.md.
"""

import decimal
import glob
import os
import re
import sys

import duckdb

ROOT = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(ROOT, "pipeline.duckdb")
QUERY_DIR = os.path.join(ROOT, "queries")

DEFAULT_ROWS = 15
WIDTH = 100


def parse_args(argv):
    rows = DEFAULT_ROWS
    picks = []
    i = 0
    while i < len(argv):
        if argv[i] == "--rows":
            rows = int(argv[i + 1])
            i += 2
        else:
            picks.append(argv[i])
            i += 1
    return rows, picks


def question_of(sql):
    """Pull the QUESTION block out of the file header."""
    match = re.search(r"--\s*QUESTION\s*\n((?:--.*\n)+?)--\s*\n", sql)
    if not match:
        return ""
    lines = [re.sub(r"^--\s?", "", ln).strip() for ln in match.group(1).splitlines()]
    return " ".join(ln for ln in lines if ln)


def render(relation, max_rows):
    columns = relation.columns
    rows = relation.fetchall()
    shown = rows[:max_rows]

    def cell(v):
        if v is None:
            return ""
        if isinstance(v, decimal.Decimal):
            v = float(v)
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, float):
            if v == int(v):
                return f"{int(v):,}"
            return f"{v:,.3f}".rstrip("0").rstrip(".")
        if isinstance(v, int):
            return f"{v:,}"
        return str(v)

    table = [[cell(v) for v in row] for row in shown]
    widths = [len(c) for c in columns]
    for row in table:
        for i, v in enumerate(row):
            widths[i] = max(widths[i], len(v))
    widths = [min(w, 34) for w in widths]

    def line(values):
        return "  ".join(v[:w].ljust(w) for v, w in zip(values, widths))

    out = [line(columns), "  ".join("-" * w for w in widths)]
    out += [line(r) for r in table]
    if len(rows) > len(shown):
        out.append(f"... {len(rows) - len(shown):,} more rows")
    out.append(f"({len(rows):,} rows)")
    return "\n".join(out)


def main():
    max_rows, picks = parse_args(sys.argv[1:])
    if picks:
        max_rows = 500

    if not os.path.exists(DB_PATH):
        sys.exit("pipeline.duckdb not found. Run: python setup.py")

    files = sorted(glob.glob(os.path.join(QUERY_DIR, "*.sql")))
    if picks:
        files = [f for f in files
                 if any(os.path.basename(f).startswith(p.zfill(2)) for p in picks)]
        if not files:
            sys.exit(f"No queries matched {picks}")

    con = duckdb.connect(DB_PATH, read_only=True)
    failures = []

    for path in files:
        name = os.path.basename(path)
        with open(path) as fh:
            sql = fh.read()

        print()
        print("=" * WIDTH)
        print(name)
        question = question_of(sql)
        if question:
            print(f"  {question}")
        print("=" * WIDTH)

        try:
            print(render(con.sql(sql), max_rows))
        except Exception as exc:                      # noqa: BLE001
            failures.append((name, exc))
            print(f"  FAILED: {exc}")

    print()
    print("=" * WIDTH)
    if failures:
        print(f"{len(failures)} of {len(files)} queries FAILED:")
        for name, exc in failures:
            print(f"  {name}: {exc}")
        print("=" * WIDTH)
        sys.exit(1)

    print(f"All {len(files)} queries ran without error.")
    print("=" * WIDTH)


if __name__ == "__main__":
    main()
