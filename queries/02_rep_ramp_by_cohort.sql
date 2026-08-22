-- ============================================================
-- 02. Rep Ramp by Hire Cohort
--
-- QUESTION
--   How long does a new seller take to reach full productivity,
--   and does the answer depend on which quarter they were hired
--   in?
--
-- DECISION IT INFORMS
--   When to hire, and what to carry a new hire at in the plan.
--   Booking a rep at full quota from month one is how a plan
--   misses by a quarter. If one hire quarter ramps materially
--   slower than the others, that is an onboarding capacity
--   problem, not a talent problem, and the fix is to move the
--   hiring calendar rather than to manage the rep out.
--
-- CAVEAT
--   Three things to hold onto. First, cohorts here are five reps
--   each, so read the direction and not the decimal. Second,
--   closed won revenue lags the behavior that produced it by
--   about one sales cycle, which is why pipeline created per rep
--   month is shown alongside it: the leading indicator moves
--   first. Third, revenue is credited to whoever owned the deal
--   at close, and ownership moves when a rep leaves, so a rep who
--   inherited a late stage deal gets credit here for someone
--   else's work. Reps only count toward a tenure band if they
--   were employed long enough to reach it, which stops early
--   attrition from making the later bands look strong.
-- ============================================================

WITH cohort_reps AS (
    SELECT rep_id,
           hire_date,
           quota_annual,
           'Q' || quarter(hire_date) AS hire_quarter,
           -- Tenure actually observed, closed off by a departure
           -- or by the dataset's as of date, whichever came first.
           date_diff('month',
                     hire_date,
                     least(coalesce(termination_date, DATE '2025-12-31'),
                           DATE '2025-12-31')) AS months_observed
    FROM reps
    WHERE hire_date >= DATE '2023-01-01'   -- hired inside the observable window
),

tenure_bands(band, lo_month, hi_month) AS (
    VALUES ('months 01-03',  0,   2),
           ('months 04-06',  3,   5),
           ('months 07-12',  6,  11),
           ('months 13+',   12, 999)
),

-- The denominator is rep months, not reps. Without it the
-- open ended 13+ band would collect two years of revenue and get
-- compared against a three month band, which makes every ramp
-- curve look flatter than it is.
exposure AS (
    SELECT c.hire_quarter,
           b.band,
           b.lo_month,
           count(*)                                                AS reps_observed,
           sum(least(c.months_observed, b.hi_month + 1) - b.lo_month) AS rep_months,
           sum((least(c.months_observed, b.hi_month + 1) - b.lo_month)
               * c.quota_annual / 12.0)                            AS prorated_quota
    FROM cohort_reps  AS c
    JOIN tenure_bands AS b ON c.months_observed > b.lo_month
    GROUP BY c.hire_quarter, b.band, b.lo_month
),

-- Leading indicator: opportunities a rep put on the board,
-- bucketed by tenure at creation.
pipeline_created AS (
    SELECT c.hire_quarter,
           b.band,
           count(*)      AS opps_created,
           sum(o.amount) AS pipeline_amount
    FROM opportunities AS o
    JOIN cohort_reps   AS c ON c.rep_id = o.rep_id
    JOIN tenure_bands  AS b
      ON date_diff('month', c.hire_date, o.created_date)
         BETWEEN b.lo_month AND b.hi_month
    GROUP BY c.hire_quarter, b.band
),

-- Lagging indicator: revenue, bucketed by tenure at close.
revenue_closed AS (
    SELECT c.hire_quarter,
           b.band,
           count(*)      AS deals_won,
           sum(o.amount) AS won_amount
    FROM opportunities AS o
    JOIN cohort_reps   AS c ON c.rep_id = o.rep_id
    JOIN tenure_bands  AS b
      ON date_diff('month', c.hire_date, o.actual_close_date)
         BETWEEN b.lo_month AND b.hi_month
    WHERE o.stage = 'Closed Won'   -- stage is authoritative; see query 12
      AND o.actual_close_date IS NOT NULL
      AND o.actual_close_date >= c.hire_date  -- drops the reversed dates query 12 finds
    GROUP BY c.hire_quarter, b.band
)

SELECT e.hire_quarter,
       e.band                                   AS tenure_band,
       e.reps_observed,
       e.rep_months,
       coalesce(pc.opps_created, 0)             AS opps_created,
       round(coalesce(pc.opps_created, 0) / e.rep_months, 2)
                                                AS opps_created_per_rep_month,
       coalesce(rc.deals_won, 0)                AS deals_won,
       round(coalesce(rc.won_amount, 0))        AS won_amount,
       -- Revenue against the quota the rep was actually carrying
       -- for those months. This is the only way to compare an
       -- enterprise cohort to an SMB cohort without the segment
       -- mix doing all the talking.
       round(100.0 * coalesce(rc.won_amount, 0)
             / nullif(e.prorated_quota, 0), 1)  AS attainment_pct
FROM exposure              AS e
LEFT JOIN pipeline_created AS pc ON pc.hire_quarter = e.hire_quarter AND pc.band = e.band
LEFT JOIN revenue_closed   AS rc ON rc.hire_quarter = e.hire_quarter AND rc.band = e.band
ORDER BY e.hire_quarter, e.lo_month;
