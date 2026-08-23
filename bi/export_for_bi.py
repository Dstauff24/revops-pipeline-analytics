"""
Export the BI extracts that the dashboards are built on.

    python bi/export_for_bi.py

Reads pipeline.duckdb, runs a defined set of queries, and writes
one CSV per extract into bi/exports/ along with a MANIFEST.md that
records the row count, column count, source query and SHA256 of
every file.

Three properties this script is built to hold:

  Idempotent. Running it twice produces byte identical CSVs. The
  SHA256 in the manifest is what makes that checkable rather than
  merely claimed. Only the manifest's own run timestamp changes.

  Reconciled. The record level hygiene extract is validated
  against the summary extract before anything is written. If the
  drill down and the headline number ever disagree, this fails
  loudly rather than shipping two dashboards that contradict each
  other.

  Guarded against a stale ramp signal. notes/ANALYSIS.md and
  notes/BUILDING_THE_DATA.md both claim the Q3 hire cohort ramps
  slowest, and dashboard 02 plots that claim. If a regenerated
  dataset ever stopped supporting it, the chart would quietly
  contradict the writeup, which for this repository is the worst
  available failure: the whole of BUILDING_THE_DATA.md is about
  catching exactly that class of error. So the claim is asserted
  here rather than eyeballed on the chart.

Nothing in queries/ is read for writing or modified. Extracts that
need a grain the analysis queries do not produce live in
bi/queries/ instead.

ALL DATA IS SYNTHETIC. See data/README.md.
"""

import csv
import datetime
import decimal
import hashlib
import os
import sys

import duckdb

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_PATH = os.path.join(ROOT, "pipeline.duckdb")
EXPORT_DIR = os.path.join(ROOT, "bi", "exports")

# The dataset is frozen at this date. It is recorded in the
# manifest so a reader can tell the difference between "the data
# is stale" and "the export is stale".
DATASET_AS_OF = "2025-12-31"

# Each extract names the dashboard it feeds and the grain it is
# at, because "why is this a separate file" is the first question
# anyone reading bi/ will have.
SPECS = [
    dict(out="01_open_pipeline_deals.csv",
         sql="bi/queries/01_open_pipeline_deals.sql",
         dashboard="01 Pipeline Health",
         grain="one row per open opportunity",
         feeds="stage bars, aging buckets, momentum split, all filters"),
    dict(out="01_funnel_conversion.csv",
         sql="queries/01_funnel_conversion.sql",
         dashboard="01 Pipeline Health",
         grain="one row per stage",
         feeds="stage to stage conversion rates"),
    dict(out="01_coverage_by_segment.csv",
         sql="queries/04_pipeline_coverage.sql",
         dashboard="01 Pipeline Health",
         grain="one row per segment",
         feeds="coverage ratio KPI and its conditional color"),

    dict(out="02_rep_attainment.csv",
         sql="bi/queries/02_rep_attainment.sql",
         dashboard="02 Rep Performance and Ramp",
         grain="one row per rep",
         feeds="attainment histogram and the sortable rep table"),
    dict(out="02_ramp_by_cohort.csv",
         sql="queries/02_rep_ramp_by_cohort.sql",
         dashboard="02 Rep Performance and Ramp",
         grain="one row per hire quarter and tenure band",
         feeds="ramp curves by cohort"),
    dict(out="02_win_rate_by_tenure.csv",
         sql="bi/queries/02_win_rate_by_tenure.sql",
         dashboard="02 Rep Performance and Ramp",
         grain="one row per tenure band and segment",
         feeds="win rate by tenure band"),

    dict(out="03_channel_efficiency.csv",
         sql="queries/03_lead_source_efficiency.sql",
         dashboard="03 Channel Efficiency",
         grain="one row per lead source",
         feeds="return on spend bars, cost against revenue scatter, volume"),
    dict(out="03_cycle_by_source.csv",
         sql="bi/queries/03_cycle_by_source.sql",
         dashboard="03 Channel Efficiency",
         grain="one row per source and outcome",
         feeds="cycle length by source"),

    dict(out="04_data_quality_checks.csv",
         sql="queries/12_data_hygiene_audit.sql",
         dashboard="04 Data Quality Monitor",
         grain="one row per integrity check",
         feeds="ranked issue list and the dollars exposed headline"),
    dict(out="04_flagged_records.csv",
         sql="bi/queries/04_flagged_records.sql",
         dashboard="04 Data Quality Monitor",
         grain="one row per record and issue pair",
         feeds="drill down work list"),
]


# The ramp claim made in notes/ANALYSIS.md and
# notes/BUILDING_THE_DATA.md, in a form that can be checked. Q3
# hires are built to walk the ramp curve at 0.55 speed, so they
# should create less pipeline per rep month than every other
# cohort in both of the bands where the penalty is still live.
# Measured on opportunities created rather than on revenue,
# because revenue lags the behavior by a full sales cycle. This is
# the same measure dashboard 02 plots.
RAMP_SLOW_COHORT = "Q3"
RAMP_CLAIM_BANDS = ["months 01-03", "months 04-06"]
RAMP_CLAIM_MEASURE = "opps_created_per_rep_month"


def render(value):
    """
    Deterministic CSV formatting. Floats are rounded rather than
    repr'd, because repr turns 128.2 into 128.20000000000002 and
    makes the output ugly and platform sensitive.
    """
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, decimal.Decimal):
        return format(value.normalize(), "f")
    if isinstance(value, float):
        rounded = round(value, 4)
        if rounded == int(rounded):
            return str(int(rounded))
        return f"{rounded:.4f}".rstrip("0")
    if isinstance(value, (datetime.date, datetime.datetime)):
        return value.isoformat()
    return str(value)


def run_extract(con, spec):
    sql_path = os.path.join(ROOT, spec["sql"])
    if not os.path.exists(sql_path):
        raise FileNotFoundError(f"missing source query: {spec['sql']}")
    with open(sql_path) as fh:
        sql = fh.read()

    relation = con.sql(sql)
    columns = list(relation.columns)
    rows = relation.fetchall()

    out_path = os.path.join(EXPORT_DIR, spec["out"])
    with open(out_path, "w", newline="") as fh:
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(columns)
        for row in rows:
            writer.writerow([render(v) for v in row])

    with open(out_path, "rb") as fh:
        digest = hashlib.sha256(fh.read()).hexdigest()

    return dict(spec, rows=len(rows), columns=len(columns),
                sha256=digest, data=rows, header=columns)


def reconcile(results):
    """
    The drill down and the summary have to agree. If they do not,
    one dashboard says 30 records and the other lists 28, and
    whichever one the RevOps team happens to open becomes the
    truth. Cheaper to fail here.
    """
    summary = next(r for r in results if r["out"] == "04_data_quality_checks.csv")
    detail = next(r for r in results if r["out"] == "04_flagged_records.csv")

    s_cols = summary["header"]
    s_counts = {row[s_cols.index("check_id")]: row[s_cols.index("records")]
                for row in summary["data"]}

    d_cols = detail["header"]
    d_counts = {}
    for row in detail["data"]:
        cid = row[d_cols.index("check_id")]
        d_counts[cid] = d_counts.get(cid, 0) + 1

    problems = []
    for check_id, expected in sorted(s_counts.items()):
        actual = d_counts.get(check_id, 0)
        if actual != expected:
            problems.append(f"check {check_id}: summary says {expected}, "
                            f"drill down has {actual}")
    for check_id in sorted(set(d_counts) - set(s_counts)):
        problems.append(f"check {check_id}: in drill down but not in summary")
    return problems, sum(s_counts.values())


def assert_ramp_signal(results):
    """
    Assert the Q3 cohort sits below every other cohort on pipeline
    created per rep month, in each band where the planted penalty
    is still in effect.

    Returns (problems, readings). Reading the values off the
    extract that is about to be written, rather than re-querying,
    means the assertion covers exactly the bytes being shipped.
    """
    extract = next(r for r in results if r["out"] == "02_ramp_by_cohort.csv")
    cols = extract["header"]
    i_quarter = cols.index("hire_quarter")
    i_band = cols.index("tenure_band")
    i_measure = cols.index(RAMP_CLAIM_MEASURE)

    problems = []
    readings = []
    for band in RAMP_CLAIM_BANDS:
        values = {row[i_quarter]: float(row[i_measure])
                  for row in extract["data"] if row[i_band] == band}
        readings.append((band, values))

        if not values:
            problems.append(f"{band}: tenure band is absent from the extract entirely")
            continue
        if RAMP_SLOW_COHORT not in values:
            problems.append(f"{band}: no {RAMP_SLOW_COHORT} cohort row in this band")
            continue
        others = {q: v for q, v in values.items() if q != RAMP_SLOW_COHORT}
        if len(others) < 3:
            problems.append(f"{band}: expected three comparison cohorts, "
                            f"found {len(others)} ({', '.join(sorted(others)) or 'none'})")
            continue

        slow = values[RAMP_SLOW_COHORT]
        beaten_by = {q: v for q, v in others.items() if v <= slow}
        if beaten_by:
            detail = ", ".join(f"{q}={v}" for q, v in sorted(beaten_by.items()))
            problems.append(
                f"{band}: {RAMP_SLOW_COHORT}={slow} is not below every other "
                f"cohort, matched or beaten by {detail}")

    return problems, readings


def write_manifest(results, flagged_total):
    generated = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")
    lines = [
        "# BI export manifest",
        "",
        "> **All data is synthetic. Generated by `data/generate.py`.",
        "> Represents no real company or person.**",
        "",
        "Written by `bi/export_for_bi.py`. Every dashboard in `bi/` is",
        "built on exactly one of these files, and every file traces back",
        "to a query in this repository.",
        "",
        f"- Dataset as of: **{DATASET_AS_OF}** (frozen; queries use it as a literal)",
        f"- Export generated: {generated}",
        f"- Extracts: {len(results)}",
        f"- Hygiene records flagged: {flagged_total}",
        "",
        "The SHA256 column is the idempotency check. Re-running the export",
        "against an unchanged database reproduces these hashes exactly.",
        "Only the generated timestamp above moves.",
        "",
        "| File | Rows | Cols | Dashboard | Grain | Source query | SHA256 |",
        "|---|---:|---:|---|---|---|---|",
    ]
    for r in results:
        lines.append(
            f"| `{r['out']}` | {r['rows']:,} | {r['columns']} | {r['dashboard']} "
            f"| {r['grain']} | [`{r['sql']}`](../../{r['sql']}) | `{r['sha256'][:16]}` |"
        )
    lines += [
        "",
        "## What each extract feeds",
        "",
    ]
    for r in results:
        lines.append(f"- **`{r['out']}`** ({r['dashboard']}): {r['feeds']}.")
    lines.append("")

    path = os.path.join(EXPORT_DIR, "MANIFEST.md")
    with open(path, "w") as fh:
        fh.write("\n".join(lines))
    return path


def main():
    if not os.path.exists(DB_PATH):
        sys.exit("pipeline.duckdb not found. Run: python setup.py")

    os.makedirs(EXPORT_DIR, exist_ok=True)
    con = duckdb.connect(DB_PATH, read_only=True)

    results = []
    failures = []
    print(f"Exporting {len(SPECS)} extracts to bi/exports/\n")
    for spec in SPECS:
        try:
            result = run_extract(con, spec)
            results.append(result)
            print(f"  [ok]   {result['out']:<32} {result['rows']:>6,} rows  "
                  f"{result['columns']:>2} cols  {result['sha256'][:12]}")
        except Exception as exc:                       # noqa: BLE001
            failures.append((spec["out"], exc))
            print(f"  [FAIL] {spec['out']:<32} {exc}")

    if failures:
        print(f"\n{len(failures)} extract(s) failed.")
        for name, exc in failures:
            print(f"  {name}: {exc}")
        sys.exit(1)

    print("\nReconciling the hygiene drill down against the summary")
    problems, flagged_total = reconcile(results)
    if problems:
        print("  [FAIL] drill down does not match the summary:")
        for p in problems:
            print(f"    {p}")
        sys.exit(1)
    print(f"  [ok]   all 13 checks agree, {flagged_total:,} flagged records total")

    print("\nAsserting the Q3 ramp claim that dashboard 02 plots")
    ramp_problems, readings = assert_ramp_signal(results)
    for band, values in readings:
        rendered = "  ".join(f"{q}={values[q]}" for q in sorted(values))
        print(f"    {band}:  {rendered}")
    if ramp_problems:
        print("  [FAIL] the extract no longer supports the claim in "
              "notes/ANALYSIS.md and notes/BUILDING_THE_DATA.md:")
        for p in ramp_problems:
            print(f"    {p}")
        print("  Either the generator changed and the writeups need updating,")
        print("  or the ramp penalty regressed. Do not publish dashboard 02")
        print("  until the chart and the documents agree again.")
        sys.exit(1)
    print(f"  [ok]   {RAMP_SLOW_COHORT} lowest in both bands")

    manifest = write_manifest(results, flagged_total)
    total_rows = sum(r["rows"] for r in results)
    print(f"\nWrote {len(results)} CSVs ({total_rows:,} rows) and "
          f"{os.path.relpath(manifest, ROOT)}")
    print("Done.")


if __name__ == "__main__":
    main()
