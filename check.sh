#!/usr/bin/env bash
#
# Release gate. Everything that has to be true before this repo is
# renamed, pinned, or shown to anyone.
#
#     ./check.sh
#
# Runs every gate and reports all of them. It deliberately does not
# stop at the first failure: when you are about to publish you want
# the whole list of what is blocking, not the first item on it.
#
# Exits nonzero if any gate fails.
#
# ----------------------------------------------------------------
# Failure tested 2026-08-24. Every gate below was made to fail on
# purpose, confirmed to exit 1, and reverted. A gate that has only
# ever been watched passing is not evidence of anything: it proves
# it does not false-positive, not that it detects. Two checks in
# this repository had already passed for reasons unrelated to what
# they claimed to verify, which is what prompted this pass. See
# "The fifth tell" in notes/BUILDING_THE_DATA.md.
#
#   Build (setup.py)        pointed SCHEMA_PATH at a missing file
#                           with pipeline.duckdb absent
#   Queries (run_all.py)    renamed the activities table in the db
#   Hygiene reconciliation  dropped 5 rows from the drill down
#                           query so it disagreed with the summary
#   Q3 ramp assertion       deleted the Q4 cohort's early tenure
#                           opportunities, so Q3 was no longer the
#                           lowest cohort in either band
#   Em dashes (files)       wrote one into a scratch file
#   Em dashes (commits)     made a commit carrying one, unpushed
#   Publishing placeholders already failing, legitimately, and it
#                           stays that way until the workbooks are
#                           published. That is the gate working.
#
# The data mutations were reverted by rebuilding from setup.py and
# confirming the export SHA256s matched the manifest byte for byte.
# ----------------------------------------------------------------

set -uo pipefail
cd "$(dirname "$0")"

PY=$(command -v python3 || command -v python)
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

FAILED=0
pass() { printf '  [ok]   %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n' "$1"; FAILED=$((FAILED + 1)); }
note() { printf '         %s\n' "$1"; }

echo
echo "==========================================================="
echo "revops-pipeline-analytics release gate"
echo "==========================================================="
echo

# ----------------------------------------------------------------
echo "Build"
# ----------------------------------------------------------------
if [ ! -f pipeline.duckdb ]; then
    note "pipeline.duckdb missing, building it"
    if "$PY" setup.py > "$LOG" 2>&1; then
        pass "setup.py built and verified the database"
    else
        fail "setup.py failed"
        tail -15 "$LOG" | sed 's/^/         /'
    fi
else
    pass "pipeline.duckdb present"
fi

# ----------------------------------------------------------------
echo
echo "Queries"
# ----------------------------------------------------------------
if "$PY" run_all.py > "$LOG" 2>&1; then
    pass "$(grep -o 'All [0-9]* queries ran without error' "$LOG" || echo 'run_all.py passed')"
else
    fail "run_all.py: at least one query errored"
    grep -E 'FAILED' "$LOG" | head -8 | sed 's/^/         /'
fi

# ----------------------------------------------------------------
echo
echo "BI extracts"
# ----------------------------------------------------------------
if "$PY" bi/export_for_bi.py > "$LOG" 2>&1; then
    pass "export_for_bi.py wrote all extracts"
    # Surface the two assertions rather than burying them in a log.
    grep -E 'checks agree' "$LOG" | sed 's/^ *\[ok\] */         hygiene: /'
    grep -E '^    months' "$LOG" | sed 's/^ */         ramp: /'
    pass "hygiene drill down reconciles with the summary"
    pass "Q3 ramp claim still holds in the extract"
else
    fail "export_for_bi.py failed"
    grep -E '\[FAIL\]|months |Either the generator|until the chart' "$LOG" \
        | head -12 | sed 's/^ */         /'
fi

# ----------------------------------------------------------------
echo
echo "Text gates"
# ----------------------------------------------------------------
# The hex escape is used so this script does not contain the
# character it is searching for. Note that $'\\u2014' looks like it
# would work and does not: this bash leaves it as the literal text
# \\u2014, which turns the check into a search for the string
# "u2014" and quietly matches nothing that matters. Verified with
# od before trusting it.
EM_DASH=$'\xe2\x80\x94'
EM_HITS=$(grep -rn -I "$EM_DASH" . --exclude-dir=.git 2>/dev/null || true)
if [ -z "$EM_HITS" ]; then
    pass "no em dashes"
else
    fail "em dashes found ($(printf '%s\n' "$EM_HITS" | wc -l | tr -d ' ') occurrences)"
    printf '%s\n' "$EM_HITS" | head -10 | sed 's/^/         /'
fi

# Two markers, because removing the comment and leaving the value
# behind is the likelier slip. check.sh excludes itself: the
# pattern below is the pattern.
# Commit messages count too. This gate exists because the first
# version of the commit that added it contained two em dashes.
BASE=$(git merge-base HEAD origin/main 2>/dev/null || echo "")
if [ -n "$BASE" ]; then
    MSG_HITS=$(git log --format='%h %s%n%b' "$BASE..HEAD" 2>/dev/null \
               | grep -n "$EM_DASH" || true)
    if [ -z "$MSG_HITS" ]; then
        pass "no em dashes in this branch's commit messages"
    else
        fail "em dashes in commit messages"
        printf '%s\n' "$MSG_HITS" | head -6 | sed 's/^/         /'
    fi
else
    note "skipped commit message check (no merge base with origin/main)"
fi

PUB_HITS=$(grep -rnE -I 'PUBLISH:|_PENDING' . --exclude-dir=.git --exclude=check.sh 2>/dev/null || true)
if [ -z "$PUB_HITS" ]; then
    pass "no unresolved publishing placeholders"
else
    fail "publishing placeholders still present ($(printf '%s\n' "$PUB_HITS" | wc -l | tr -d ' ') of them)"
    printf '%s\n' "$PUB_HITS" | sed 's/^/         /'
    note ""
    note "These block renaming and pinning, by design. Publish the"
    note "Tableau workbooks first, fill in the real URLs, capture"
    note "screenshots from the published versions, then rename."
fi

# ----------------------------------------------------------------
echo
echo "==========================================================="
if [ "$FAILED" -eq 0 ]; then
    echo "All gates passed. Safe to rename and pin."
    echo "==========================================================="
    echo
    exit 0
fi
echo "$FAILED gate(s) failed. Not ready to publish."
echo "==========================================================="
echo
exit 1
