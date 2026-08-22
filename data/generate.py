"""
================================================================
SYNTHETIC DATA GENERATOR

EVERY ROW THIS SCRIPT PRODUCES IS FABRICATED. No real company,
customer, employee, or dollar figure appears anywhere in the
output. Company names are assembled from a word list in this
file. Person names come from Faker. Any resemblance to a real
organization is coincidence produced by a random seed.

What this builds is a 24 month B2B sales pipeline shaped like a
CRM export, including the problems a CRM export has. The
imperfections are deliberate and are documented in data/README.md
and found by queries/12_data_hygiene_audit.sql.

Reproducible: seed is SEED below. Same seed, same database.
================================================================
"""

import csv
import os
import random
from datetime import date, timedelta

import numpy as np
from faker import Faker

# ----------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------
SEED = 4207

# The dataset covers two full calendar years and is frozen at
# AS_OF. Queries that need "today" use AS_OF as a literal, so the
# results never change with the wall clock.
START_DATE = date(2024, 1, 1)
AS_OF = date(2025, 12, 31)

N_TERRITORIES = 8
N_REPS = 25
N_ACCOUNTS = 300
N_LEADS = 4000

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "csv")

rng = np.random.default_rng(SEED)
random.seed(SEED)
fake = Faker("en_US")
Faker.seed(SEED)

STAGES = ["Prospecting", "Discovery", "Proposal", "Negotiation"]
CLOSED_WON = "Closed Won"
CLOSED_LOST = "Closed Lost"

# Monthly multiplier applied to lead volume and to win rate.
# Q4 pushes deals over the line, summer does not.
SEASONALITY = {
    1: 0.92, 2: 0.96, 3: 1.09, 4: 0.98, 5: 1.00, 6: 1.06,
    7: 0.78, 8: 0.74, 9: 1.05, 10: 1.03, 11: 1.07, 12: 1.24,
}

# Source economics. These differences are the point of query 03:
# inbound converts well but is capacity limited, outbound is
# high volume and low yield, referral converts best and is the
# rarest, paid costs the most per lead. Note that referral is not
# free: cpl for referral is the partner commission, which is what
# stops it from dominating the return on spend table outright.
SOURCES = {
    "Referral":    dict(share=0.06, cpl=(800, 0.50),  lead_to_opp=0.84, quality=1.45,
                        sub=["Customer Intro", "Partner Intro", "Advisor"]),
    "Inbound":     dict(share=0.19, cpl=(400, 0.60),  lead_to_opp=0.78, quality=1.20,
                        sub=["Content Download", "Demo Request", "Pricing Page", "Webinar"]),
    "Event":       dict(share=0.11, cpl=(2100, 0.50), lead_to_opp=0.64, quality=0.95,
                        sub=["Trade Show", "Regional Dinner", "Sponsored Booth"]),
    "Paid":        dict(share=0.19, cpl=(2600, 0.55), lead_to_opp=0.62, quality=0.82,
                        sub=["Search", "Display", "Paid Social", "Review Site"]),
    "Outbound":    dict(share=0.45, cpl=(650, 0.70),  lead_to_opp=0.56, quality=0.70,
                        sub=["Cold Call", "Sequenced Email", "LinkedIn", "List Buy"]),
}

# Base probability of clearing each stage gate, before adjusting
# for rep skill, ramp, source quality and segment.
ADVANCE_P = {
    "Prospecting": 0.86,   # to Discovery
    "Discovery":   0.78,   # to Proposal
    "Proposal":    0.74,   # to Negotiation
}
BASE_WIN_P = 0.52          # at Negotiation, before adjustment

# Median days spent in each stage. Negotiation is the designed
# bottleneck: legal and procurement live there. Query 08 finds it.
STAGE_DWELL_MEDIAN = {
    "Prospecting": 10,
    "Discovery":   20,
    "Proposal":    27,
    "Negotiation": 36,
}
SEGMENT_CYCLE_MULT = {"SMB": 0.70, "Mid-Market": 1.10, "Enterprise": 1.70}
SEGMENT_AMOUNT = {  # (median amount, sigma of lognormal)
    "SMB": (14000, 0.55),
    "Mid-Market": (52000, 0.60),
    "Enterprise": (185000, 0.70),
}
SEGMENT_QUOTA = {"SMB": 620000, "Mid-Market": 1250000, "Enterprise": 2200000}

INDUSTRIES = [
    "Industrial Manufacturing", "Building Products", "Logistics",
    "Healthcare Services", "Financial Services", "Software",
    "Facilities Management", "Food and Beverage", "Utilities",
    "Professional Services",
]

LOSS_REASONS = [
    "Price", "Lost to Competitor", "No Decision", "No Budget",
    "Timing", "Missing Feature", "Champion Left", "Went Internal",
]

ACTIVITY_TYPES = ["Email", "Call", "Meeting", "Demo", "Note"]
ACTIVITY_WEIGHTS = [0.46, 0.30, 0.11, 0.06, 0.07]

# Fictional company name parts. Nothing here is a real trademark.
NAME_HEADS = [
    "Northvale", "Cedarpoint", "Ironbridge", "Blue Harbor", "Stonefield",
    "Redmill", "Silverline", "Granite Bay", "Willowmere", "Foxglove",
    "Kestrel", "Larkspur", "Copperton", "Marbrook", "Ninebark",
    "Oakspring", "Pinehollow", "Quarrystone", "Ridgeway", "Saltmarsh",
    "Tidewater", "Umberfield", "Vantage Hill", "Westerly", "Yarrowdale",
    "Amberline", "Brightwater", "Clearcreek", "Dunmore", "Eastgate",
    "Fairmount", "Glenhaven", "Havenport", "Inkwell", "Junipero",
    "Kingsferry", "Loamwood", "Meridian Falls", "Norwood Gate", "Overlook",
]
NAME_TAILS = [
    "Industrial", "Logistics", "Systems", "Fabrication", "Mechanical",
    "Analytics", "Utilities", "Holdings", "Supply", "Controls",
    "Foodworks", "Diagnostics", "Capital", "Facilities", "Materials",
    "Networks", "Instruments", "Packaging", "Metalworks", "Robotics",
]
NAME_SUFFIXES = ["Inc", "LLC", "Group", "Partners", "Co", "Corp"]

TERRITORY_NAMES = [
    ("Great Lakes", "Midwest", "Tier 1"),
    ("Ohio Valley", "Midwest", "Tier 2"),
    ("Mid Atlantic", "Northeast", "Tier 1"),
    ("New England", "Northeast", "Tier 2"),
    ("Southeast Coastal", "Southeast", "Tier 1"),
    ("Gulf Coast", "Southeast", "Tier 2"),
    ("Mountain West", "West", "Tier 3"),
    ("Pacific Northwest", "West", "Tier 2"),
]


# ----------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------
def d(x):
    """Format a date for CSV, or empty string for NULL."""
    return "" if x is None else x.isoformat()


def b(x):
    return "" if x is None else ("true" if x else "false")


def money(x):
    return "" if x is None else f"{round(float(x), 2):.2f}"


def rand_date(start, end):
    span = (end - start).days
    return start + timedelta(days=int(rng.integers(0, max(span, 1) + 1)))


def months_between(later, earlier):
    return (later - earlier).days / 30.44


def lognormal(median, sigma):
    return float(median * np.exp(rng.normal(0.0, sigma)))


def ramp_factor(hire_date, on_date):
    """
    Fraction of full productivity a rep is running at.

    Roughly 20 percent in month one, about 60 percent by month
    three, full by month six.

    Reps hired in Q3 ramp 40 percent slower. They onboard through
    the summer slowdown and then hit Q4, when their manager is
    closing deals instead of coaching, so they walk the same curve
    at 0.6 speed and reach full productivity around month ten
    instead of month six. This is planted so that
    queries/02_rep_ramp_by_cohort.sql has something real to find.
    """
    m = months_between(on_date, hire_date)
    if m < 0:
        return 0.0
    if hire_date.month in (7, 8, 9):
        m = m * 0.55          # Q3 hires move along the curve far slower
    if m < 1:
        base = 0.20
    elif m < 2:
        base = 0.35
    elif m < 3:
        base = 0.50
    elif m < 4:
        base = 0.62
    elif m < 5:
        base = 0.76
    elif m < 6:
        base = 0.88
    else:
        base = 1.00
    return base


def add_months(dt, n):
    y = dt.year + (dt.month - 1 + n) // 12
    m = (dt.month - 1 + n) % 12 + 1
    day = min(dt.day, [31, 29 if y % 4 == 0 else 28, 31, 30, 31, 30,
                       31, 31, 30, 31, 30, 31][m - 1])
    return date(y, m, day)


# ----------------------------------------------------------------
# territories
# ----------------------------------------------------------------
territories = []
for i, (nm, region, tier) in enumerate(TERRITORY_NAMES, start=1):
    tam_base = {"Tier 1": 420_000_000, "Tier 2": 240_000_000, "Tier 3": 110_000_000}[tier]
    territories.append(dict(
        territory_id=i,
        name=nm,
        region=region,
        market_tier=tier,
        tam_estimate=int(tam_base * rng.uniform(0.82, 1.24)),
    ))

# ----------------------------------------------------------------
# reps
#
# Hire dates are placed on purpose rather than sampled, so that
# every quarter from 2023 Q1 through 2025 Q3 has a cohort with
# enough reps in it to compare. Eight tenured reps predate the
# data window and give the comparison a fully ramped baseline.
# ----------------------------------------------------------------
TENURED_HIRES = [
    date(2019, 4, 15), date(2020, 2, 3), date(2020, 9, 14),
    date(2021, 6, 7), date(2022, 3, 21),
]
# Five reps per hire quarter, so the ramp cohorts in query 02 are
# the same size and the comparison between them is not just noise.
COHORT_HIRES = [
    date(2023, 1, 9),  date(2023, 2, 13), date(2024, 1, 8),  date(2024, 2, 12),
    date(2023, 4, 10), date(2023, 5, 8),  date(2024, 4, 8),  date(2024, 5, 13),
    date(2023, 7, 10), date(2023, 8, 14), date(2024, 7, 8),  date(2024, 8, 12),
    date(2023, 10, 9), date(2023, 11, 13), date(2024, 10, 14), date(2024, 11, 11),
    # The most recent hires, one per quarter, are the reps who are
    # still ramping at the as of date.
    date(2025, 2, 10), date(2025, 5, 12), date(2025, 8, 11), date(2025, 10, 13),
]
HIRE_DATES = TENURED_HIRES + COHORT_HIRES
assert len(HIRE_DATES) == N_REPS

reps = []
rep_meta = {}
for i, hd in enumerate(HIRE_DATES, start=1):
    territory_id = ((i - 1) % N_TERRITORIES) + 1
    # Bigger territories carry the enterprise sellers.
    if i <= len(TENURED_HIRES):
        segment = ["Enterprise", "Mid-Market", "Enterprise", "Mid-Market", "SMB"][i - 1]
    else:
        segment = ["SMB", "Mid-Market", "Enterprise", "Mid-Market"][(i - len(TENURED_HIRES) - 1) % 4]
    skill = float(np.clip(rng.normal(1.0, 0.14), 0.62, 1.42))
    reps.append(dict(
        rep_id=i,
        name=fake.name(),
        hire_date=hd,
        territory_id=territory_id,
        segment_focus=segment,
        ramp_status=None,          # filled in after attrition
        quota_annual=SEGMENT_QUOTA[segment] * round(float(rng.uniform(0.92, 1.10)), 3),
        manager_id=None,
        termination_date=None,
    ))
    rep_meta[i] = dict(skill=skill)

# Three of the tenured reps are the managers. They carry a quota
# too, which is common in a team this size.
MANAGER_IDS = [1, 2, 3]
for r in reps:
    if r["rep_id"] in MANAGER_IDS:
        r["manager_id"] = None
    else:
        r["manager_id"] = MANAGER_IDS[(r["rep_id"]) % len(MANAGER_IDS)]

# Attrition. Roughly a third of the team leaves, weighted toward
# the lower performers, which is both realistic and the reason
# rep level analysis needs a survivorship caveat.
term_candidates = [r["rep_id"] for r in reps if r["rep_id"] not in MANAGER_IDS]
term_weights = np.array([1.0 / (rep_meta[i]["skill"] ** 3) for i in term_candidates])
term_weights = term_weights / term_weights.sum()
terminated = set(rng.choice(term_candidates, size=8, replace=False, p=term_weights).tolist())

for r in reps:
    if r["rep_id"] in terminated:
        earliest = add_months(r["hire_date"], 7)
        latest = min(AS_OF - timedelta(days=20), add_months(r["hire_date"], 30))
        if latest <= earliest:
            latest = min(AS_OF - timedelta(days=20), earliest + timedelta(days=60))
        r["termination_date"] = rand_date(max(earliest, START_DATE + timedelta(days=60)), latest)
        r["ramp_status"] = "Terminated"
        rep_meta[r["rep_id"]]["skill"] *= 0.82
    elif months_between(AS_OF, r["hire_date"]) < 6:
        r["ramp_status"] = "Ramping"
    else:
        r["ramp_status"] = "Full Productivity"

rep_by_id = {r["rep_id"]: r for r in reps}


def rep_active_on(rep, on_date):
    if on_date < rep["hire_date"]:
        return False
    if rep["termination_date"] and on_date > rep["termination_date"]:
        return False
    return True


# ----------------------------------------------------------------
# accounts
# ----------------------------------------------------------------
used_bases = set()


def make_company_name():
    """
    Head plus tail is kept unique, so the only way two accounts
    normalize to the same base name is if this script planted a
    duplicate on purpose. That keeps the duplicate check in
    query 12 honest instead of drowning it in coincidences.
    """
    while True:
        base = f"{random.choice(NAME_HEADS)} {random.choice(NAME_TAILS)}"
        if base not in used_bases:
            used_bases.add(base)
            return f"{base} {random.choice(NAME_SUFFIXES)}"


accounts = []
for i in range(1, N_ACCOUNTS + 1):
    emp = int(np.clip(lognormal(220, 1.5), 8, 42000))
    if emp < 100:
        segment = "SMB"
    elif emp < 1000:
        segment = "Mid-Market"
    else:
        segment = "Enterprise"
    accounts.append(dict(
        account_id=i,
        company_name=make_company_name(),
        industry=random.choice(INDUSTRIES),
        employee_count=emp,
        territory_id=int(rng.integers(1, N_TERRITORIES + 1)),
        created_date=rand_date(date(2022, 1, 1), AS_OF - timedelta(days=30)),
        segment=segment,
    ))

# Deliberate dirt: near duplicate accounts. These are the records
# a merge job missed. Each one gets its own opportunities later,
# which is exactly why duplicates distort account level reporting.
DUP_STYLES = [
    lambda n: n.replace(" Inc", ", Inc."),
    lambda n: n.replace(" LLC", " L.L.C."),
    lambda n: n.upper(),
    lambda n: n + ".",
    lambda n: n.replace(" Group", " Grp"),
    lambda n: n.replace(" Co", " Company"),
]
dup_sources = rng.choice(N_ACCOUNTS, size=6, replace=False)
next_account_id = N_ACCOUNTS + 1
for k, src_idx in enumerate(dup_sources.tolist()):
    src = accounts[src_idx]
    # Use whichever mangling actually changes this particular
    # name, starting from a different style for each duplicate.
    variant = src["company_name"]
    for offset in range(len(DUP_STYLES)):
        candidate = DUP_STYLES[(k + offset) % len(DUP_STYLES)](src["company_name"])
        if candidate != src["company_name"]:
            variant = candidate
            break
    accounts.append(dict(
        account_id=next_account_id,
        company_name=variant,
        industry=src["industry"],
        employee_count=src["employee_count"] + int(rng.integers(-5, 6)),
        territory_id=src["territory_id"],
        created_date=src["created_date"] + timedelta(days=int(rng.integers(20, 400))),
        segment=src["segment"],
    ))
    next_account_id += 1

account_by_id = {a["account_id"]: a for a in accounts}
all_account_ids = [a["account_id"] for a in accounts]

# ----------------------------------------------------------------
# leads
# ----------------------------------------------------------------
source_names = list(SOURCES.keys())
source_shares = np.array([SOURCES[s]["share"] for s in source_names])
source_shares = source_shares / source_shares.sum()

# Lead creation dates follow the seasonal curve.
# Volume also trends up across the window. The business is
# growing, which is why the open pipeline at the as of date is
# larger than a flat run rate would produce.
day_pool = []
day_weights = []
total_days = (AS_OF - timedelta(days=10) - START_DATE).days
cur = START_DATE
while cur <= AS_OF - timedelta(days=10):
    progress = (cur - START_DATE).days / total_days
    day_pool.append(cur)
    day_weights.append(SEASONALITY[cur.month] * (1.0 + 0.50 * progress))
    cur += timedelta(days=1)
day_weights = np.array(day_weights) / np.sum(day_weights)

leads = []
for lead_id in range(1, N_LEADS + 1):
    source = source_names[int(rng.choice(len(source_names), p=source_shares))]
    cfg = SOURCES[source]
    created = day_pool[int(rng.choice(len(day_pool), p=day_weights))]
    cpl_median, cpl_sigma = cfg["cpl"]
    leads.append(dict(
        lead_id=lead_id,
        account_id=int(rng.choice(all_account_ids)),
        source=source,
        sub_source=random.choice(cfg["sub"]),
        created_date=created,
        marketing_cost_allocated=round(lognormal(cpl_median, cpl_sigma), 2),
        converted_date=None,
        converted_opportunity_id=None,
    ))

# ----------------------------------------------------------------
# opportunities, stage history, activities
# ----------------------------------------------------------------
opportunities = []
stage_history = []
activities = []
sh_id = 1
opp_id = 1

# Assignment weights: a rep who is still ramping picks up fewer
# new deals, which is how a real manager runs a territory.
def pick_rep(account, created):
    eligible = [r for r in reps if rep_active_on(r, created)]
    if not eligible:
        eligible = list(reps)
    weights = []
    for r in eligible:
        w = 0.25 + 0.75 * ramp_factor(r["hire_date"], created)
        if r["territory_id"] == account["territory_id"]:
            w *= 3.2
        if r["segment_focus"] == account["segment"]:
            w *= 2.4
        weights.append(max(w, 0.01))
    weights = np.array(weights)
    weights = weights / weights.sum()
    return eligible[int(rng.choice(len(eligible), p=weights))]


for lead in leads:
    cfg = SOURCES[lead["source"]]
    if rng.random() > cfg["lead_to_opp"]:
        continue
    lag = int(np.clip(lognormal({"Referral": 4, "Inbound": 6, "Event": 14,
                                 "Paid": 8, "Outbound": 16}[lead["source"]], 0.6), 1, 90))
    converted = lead["created_date"] + timedelta(days=lag)
    if converted > AS_OF:
        continue

    account = account_by_id[lead["account_id"]]
    rep = pick_rep(account, converted)
    rf = ramp_factor(rep["hire_date"], converted)
    skill = rep_meta[rep["rep_id"]]["skill"]
    quality = float(np.clip(skill * (0.35 + 0.65 * rf) * cfg["quality"], 0.35, 1.55))

    segment = account["segment"]
    cycle_mult = SEGMENT_CYCLE_MULT[segment] * {"Referral": 0.80, "Inbound": 0.92,
                                                "Event": 1.05, "Paid": 1.05,
                                                "Outbound": 1.20}[lead["source"]]

    # Walk the stages.
    cur_stage = "Prospecting"
    cur_date = converted
    last_change = converted
    transitions = []
    outcome = None          # "won", "lost", or None for still open
    stalled = rng.random() < 0.017   # deliberate dirt: nobody closed it out

    while True:
        dwell = lognormal(STAGE_DWELL_MEDIAN[cur_stage] * cycle_mult, 0.62)
        if stalled and cur_stage in ("Discovery", "Proposal"):
            dwell = float(rng.uniform(410, 620))
        nxt_date = cur_date + timedelta(days=int(max(dwell, 1)))

        if cur_stage == "Negotiation":
            p_win = BASE_WIN_P * quality * SEASONALITY[nxt_date.month] * \
                {"SMB": 1.06, "Mid-Market": 1.00, "Enterprise": 0.88}[segment]
            advance = rng.random() < float(np.clip(p_win, 0.03, 0.90))
            nxt_stage = CLOSED_WON if advance else CLOSED_LOST
        else:
            p_adv = ADVANCE_P[cur_stage] * (0.55 + 0.45 * quality)
            advance = rng.random() < float(np.clip(p_adv, 0.05, 0.95))
            nxt_stage = STAGES[STAGES.index(cur_stage) + 1] if advance else CLOSED_LOST

        if nxt_date > AS_OF:
            outcome = None                      # still open at the as of date
            break

        transitions.append((cur_stage, nxt_stage, nxt_date))
        last_change = nxt_date
        cur_date = nxt_date
        cur_stage = nxt_stage
        if cur_stage in (CLOSED_WON, CLOSED_LOST):
            outcome = "won" if cur_stage == CLOSED_WON else "lost"
            break

    amt_median, amt_sigma = SEGMENT_AMOUNT[segment]
    amount = round(lognormal(amt_median, amt_sigma) *
                   {"Referral": 1.12, "Inbound": 1.02, "Event": 1.0,
                    "Paid": 0.94, "Outbound": 0.97}[lead["source"]], 2)

    # The expected close date is what the rep typed in, and reps
    # type in dates that are too soon. Query 05 measures the slip.
    optimistic_cycle = sum(STAGE_DWELL_MEDIAN.values()) * cycle_mult * float(rng.uniform(0.52, 0.88))
    expected_close = converted + timedelta(days=int(max(optimistic_cycle, 7)))

    actual_close = last_change if outcome else None
    is_won = (outcome == "won") if outcome else None

    # Forecast category. Optimism scales with how new the rep is,
    # which is the drift query 05 exists to quantify.
    optimism = 1.0 + 0.95 * (1.0 - rf) + (0.25 if rep["termination_date"] else 0.0)
    if outcome == "won":
        fc = random.choices(["Commit", "Best Case", "Pipeline"], weights=[0.63, 0.28, 0.09])[0]
    elif outcome == "lost":
        p_commit = float(np.clip(0.11 * optimism, 0.0, 0.46))
        p_best = float(np.clip(0.23 * optimism, 0.0, 0.40))
        fc = random.choices(
            ["Commit", "Best Case", "Pipeline", "Omitted"],
            weights=[p_commit, p_best, max(1.0 - p_commit - p_best - 0.07, 0.05), 0.07])[0]
    else:
        if cur_stage == "Negotiation":
            fc = random.choices(["Commit", "Best Case", "Pipeline"], weights=[0.52, 0.35, 0.13])[0]
        elif cur_stage == "Proposal":
            fc = random.choices(["Commit", "Best Case", "Pipeline"], weights=[0.16, 0.48, 0.36])[0]
        else:
            fc = random.choices(["Best Case", "Pipeline", "Omitted"], weights=[0.14, 0.80, 0.06])[0]

    loss_reason = random.choice(LOSS_REASONS) if outcome == "lost" else None
    if loss_reason and rng.random() < 0.10:
        loss_reason = None      # deliberate dirt: closed lost with no reason

    opportunities.append(dict(
        opportunity_id=opp_id,
        account_id=account["account_id"],
        rep_id=rep["rep_id"],
        source=lead["source"],
        created_date=converted,
        stage=cur_stage,
        amount=amount,
        forecast_category=fc,
        expected_close_date=expected_close,
        actual_close_date=actual_close,
        is_won=is_won,
        loss_reason=loss_reason,
        _segment=segment,
        _last_change=last_change,
        _stages_touched=len(transitions) + 1,
        _skill=skill,
    ))

    for frm, to, when in transitions:
        stage_history.append(dict(
            id=sh_id,
            opportunity_id=opp_id,
            from_stage=frm,
            to_stage=to,
            changed_at=when,
            changed_by_rep_id=rep["rep_id"],
        ))
        sh_id += 1

    lead["converted_date"] = converted
    lead["converted_opportunity_id"] = opp_id
    opp_id += 1

print(f"  opportunities generated: {len(opportunities)}")

# ----------------------------------------------------------------
# Reassignment on attrition
#
# When a rep leaves, their open deals move to somebody. The move
# is written to stage_history as a row where from_stage equals
# to_stage, and every later stage change is credited to the new
# owner. This is what makes rep level attribution genuinely hard:
# the rep who closed the deal is often not the rep who worked it.
# ----------------------------------------------------------------
reassigned = 0
orphaned = 0
for opp in opportunities:
    owner = rep_by_id[opp["rep_id"]]
    term = owner["termination_date"]
    if not term:
        continue
    still_open_at_term = (opp["actual_close_date"] is None) or (opp["actual_close_date"] > term)
    if not still_open_at_term or opp["created_date"] > term:
        continue
    # A handful are left with the departed rep on purpose. That is
    # the pile query 12 flags and somebody has to clean up.
    if rng.random() < 0.12:
        orphaned += 1
        continue
    candidates = [r for r in reps
                  if r["rep_id"] != owner["rep_id"] and rep_active_on(r, term)
                  and r["territory_id"] == owner["territory_id"]]
    if not candidates:
        candidates = [r for r in reps if r["rep_id"] != owner["rep_id"] and rep_active_on(r, term)]
    if not candidates:
        continue
    new_owner = candidates[int(rng.integers(0, len(candidates)))]
    stage_at_term = "Prospecting"
    for sh in stage_history:
        if sh["opportunity_id"] == opp["opportunity_id"] and sh["changed_at"] <= term:
            stage_at_term = sh["to_stage"]
    stage_history.append(dict(
        id=sh_id,
        opportunity_id=opp["opportunity_id"],
        from_stage=stage_at_term,
        to_stage=stage_at_term,
        changed_at=term,
        changed_by_rep_id=new_owner["rep_id"],
    ))
    sh_id += 1
    for sh in stage_history:
        if sh["opportunity_id"] == opp["opportunity_id"] and sh["changed_at"] > term:
            sh["changed_by_rep_id"] = new_owner["rep_id"]
    opp["rep_id"] = new_owner["rep_id"]
    reassigned += 1

print(f"  opportunities reassigned after attrition: {reassigned}")
print(f"  opportunities left with a departed rep: {orphaned}")

# ----------------------------------------------------------------
# activities
#
# Touch count is generated after the outcome is known and is
# correlated with it. That correlation is real in this dataset and
# it is also not causal, which is the whole point of the caveat on
# query 09.
# ----------------------------------------------------------------
activity_id = 1
zero_activity_opps = set(rng.choice(len(opportunities), size=int(len(opportunities) * 0.03),
                                    replace=False).tolist())
for idx, opp in enumerate(opportunities):
    if idx in zero_activity_opps:
        continue
    seg_mult = {"SMB": 0.80, "Mid-Market": 1.10, "Enterprise": 1.55}[opp["_segment"]]
    lam = (2.8 + 2.95 * opp["_stages_touched"]) * seg_mult * opp["_skill"]
    if opp["is_won"]:
        lam *= 1.38
    n = int(rng.poisson(max(lam, 1.0)))
    end = opp["actual_close_date"] or AS_OF
    if end <= opp["created_date"]:
        end = opp["created_date"] + timedelta(days=1)
    span = (end - opp["created_date"]).days
    for _ in range(n):
        adate = opp["created_date"] + timedelta(days=int(rng.integers(0, span + 1)))
        if adate.weekday() >= 5 and rng.random() < 0.8:
            adate -= timedelta(days=2)
        activities.append(dict(
            activity_id=activity_id,
            opportunity_id=opp["opportunity_id"],
            rep_id=opp["rep_id"],
            activity_type=random.choices(ACTIVITY_TYPES, weights=ACTIVITY_WEIGHTS)[0],
            activity_date=adate,
        ))
        activity_id += 1

print(f"  activities generated: {len(activities)}")

# ----------------------------------------------------------------
# Deliberate dirt
#
# Everything below this line is damage applied on purpose. Each
# block maps to a check in queries/12_data_hygiene_audit.sql.
# ----------------------------------------------------------------
n_opps = len(opportunities)


def sample_opps(n, predicate=None):
    pool = [o for o in opportunities if (predicate is None or predicate(o))]
    n = min(n, len(pool))
    idx = rng.choice(len(pool), size=n, replace=False).tolist()
    return [pool[i] for i in idx]


# 1. Missing amount on roughly 5 percent of deals.
for o in sample_opps(int(n_opps * 0.05)):
    o["amount"] = None

# 2. Nonsense amounts.
for o in sample_opps(12, lambda o: o["amount"] is not None):
    o["amount"] = round(float(rng.choice([0.0, -1500.0, -25000.0])), 2)

# 3. Close date earlier than create date. Usually a bad import or
#    a rep backdating a renewal.
for o in sample_opps(30, lambda o: o["actual_close_date"] is not None):
    o["actual_close_date"] = o["created_date"] - timedelta(days=int(rng.integers(1, 25)))

# 4. Closed stage with no close date.
for o in sample_opps(25, lambda o: o["stage"] in (CLOSED_WON, CLOSED_LOST)
                     and o["actual_close_date"] is not None):
    o["actual_close_date"] = None

# 5. Open stage carrying a close date.
for o in sample_opps(15, lambda o: o["stage"] in STAGES and o["actual_close_date"] is None):
    o["actual_close_date"] = o["created_date"] + timedelta(days=int(rng.integers(20, 200)))

# 6. is_won disagreeing with stage.
for o in sample_opps(10, lambda o: o["stage"] == CLOSED_WON):
    o["is_won"] = None
for o in sample_opps(8, lambda o: o["stage"] == CLOSED_LOST):
    o["is_won"] = True
for o in sample_opps(9, lambda o: o["stage"] in STAGES):
    o["is_won"] = True

# 7. Leads flagged converted with nothing linked.
for lead in leads:
    if lead["converted_opportunity_id"] is not None and rng.random() < 0.015:
        lead["converted_opportunity_id"] = None

# 8. stage_history rows that skip a stage. The Discovery step is
#    collapsed away, leaving a Prospecting to Proposal jump.
by_opp = {}
for sh in stage_history:
    by_opp.setdefault(sh["opportunity_id"], []).append(sh)
skip_candidates = [oid for oid, rows in by_opp.items()
                   if any(r["from_stage"] == "Prospecting" and r["to_stage"] == "Discovery" for r in rows)
                   and any(r["from_stage"] == "Discovery" and r["to_stage"] == "Proposal" for r in rows)]
skipped = 0
if skip_candidates:
    chosen = rng.choice(len(skip_candidates), size=min(25, len(skip_candidates)), replace=False).tolist()
    drop_ids = set()
    for ci in chosen:
        oid = skip_candidates[ci]
        rows = by_opp[oid]
        r1 = next(r for r in rows if r["from_stage"] == "Prospecting" and r["to_stage"] == "Discovery")
        r2 = next(r for r in rows if r["from_stage"] == "Discovery" and r["to_stage"] == "Proposal")
        r1["to_stage"] = "Proposal"
        r1["changed_at"] = r2["changed_at"]
        drop_ids.add(r2["id"])
        skipped += 1
    stage_history = [r for r in stage_history if r["id"] not in drop_ids]

print(f"  stage_history rows collapsed into stage skips: {skipped}")

# ----------------------------------------------------------------
# Write CSVs
# ----------------------------------------------------------------
os.makedirs(OUT_DIR, exist_ok=True)


def write_csv(name, header, rows):
    path = os.path.join(OUT_DIR, name)
    with open(path, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(header)
        w.writerows(rows)
    return len(rows)


counts = {}
counts["territories"] = write_csv(
    "territories.csv",
    ["territory_id", "name", "region", "market_tier", "tam_estimate"],
    [[t["territory_id"], t["name"], t["region"], t["market_tier"], t["tam_estimate"]]
     for t in territories])

counts["reps"] = write_csv(
    "reps.csv",
    ["rep_id", "name", "hire_date", "territory_id", "segment_focus", "ramp_status",
     "quota_annual", "manager_id", "termination_date"],
    [[r["rep_id"], r["name"], d(r["hire_date"]), r["territory_id"], r["segment_focus"],
      r["ramp_status"], money(r["quota_annual"]),
      "" if r["manager_id"] is None else r["manager_id"], d(r["termination_date"])]
     for r in reps])

counts["accounts"] = write_csv(
    "accounts.csv",
    ["account_id", "company_name", "industry", "employee_count", "territory_id",
     "created_date", "segment"],
    [[a["account_id"], a["company_name"], a["industry"], a["employee_count"],
      a["territory_id"], d(a["created_date"]), a["segment"]] for a in accounts])

counts["leads"] = write_csv(
    "leads.csv",
    ["lead_id", "account_id", "source", "sub_source", "created_date",
     "marketing_cost_allocated", "converted_date", "converted_opportunity_id"],
    [[l["lead_id"], l["account_id"], l["source"], l["sub_source"], d(l["created_date"]),
      money(l["marketing_cost_allocated"]), d(l["converted_date"]),
      "" if l["converted_opportunity_id"] is None else l["converted_opportunity_id"]]
     for l in leads])

counts["opportunities"] = write_csv(
    "opportunities.csv",
    ["opportunity_id", "account_id", "rep_id", "source", "created_date", "stage",
     "amount", "forecast_category", "expected_close_date", "actual_close_date",
     "is_won", "loss_reason"],
    [[o["opportunity_id"], o["account_id"], o["rep_id"], o["source"], d(o["created_date"]),
      o["stage"], money(o["amount"]), o["forecast_category"], d(o["expected_close_date"]),
      d(o["actual_close_date"]), b(o["is_won"]), o["loss_reason"] or ""]
     for o in opportunities])

counts["stage_history"] = write_csv(
    "stage_history.csv",
    ["id", "opportunity_id", "from_stage", "to_stage", "changed_at", "changed_by_rep_id"],
    [[s["id"], s["opportunity_id"], s["from_stage"], s["to_stage"], d(s["changed_at"]),
      s["changed_by_rep_id"]] for s in sorted(stage_history, key=lambda x: x["id"])])

counts["activities"] = write_csv(
    "activities.csv",
    ["activity_id", "opportunity_id", "rep_id", "activity_type", "activity_date"],
    [[a["activity_id"], a["opportunity_id"], a["rep_id"], a["activity_type"],
      d(a["activity_date"])] for a in activities])


def main():
    return counts


if __name__ == "__main__":
    print("\nRow counts:")
    for k, v in counts.items():
        print(f"  {k:<16} {v:>7,}")
    print(f"\nCSVs written to {OUT_DIR}")
