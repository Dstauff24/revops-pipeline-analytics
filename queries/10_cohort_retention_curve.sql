-- ============================================================
-- 10. Account Cohort Retention and Expansion Curve
--
-- QUESTION
--   After an account buys for the first time, how much more do
--   they buy, how fast, and what share of them ever come back?
--
-- DECISION IT INFORMS
--   Whether growth should come from new logos or from the
--   installed base, and what a first deal is actually worth. If a
--   cohort's cumulative revenue reaches two and a half times the
--   first purchase within a year, then a first deal is worth two
--   and a half times its face value, and paying more to acquire
--   one is rational. If the curve is flat, the company has a
--   transactional business that has been telling itself it has a
--   land and expand business, and the account management headcount
--   is not earning its cost.
--
-- CAVEAT
--   Later cohorts have had less time to expand, so the curve
--   truncates on the right: a cohort formed one quarter before
--   the as of date cannot show a four quarter number. The
--   quarters_observable column marks how much of each row is real
--   history rather than absence of data. Never average across
--   cohorts without accounting for it, which is the single most
--   common way a retention chart gets read wrong. Duplicate
--   account records also split one real customer across two
--   cohorts and understate expansion: query 12 counts them, and
--   they are not merged here.
-- ============================================================

WITH first_purchase AS (
    SELECT account_id,
           min(actual_close_date) AS first_win_date
    FROM opportunities
    WHERE stage = 'Closed Won'
      AND actual_close_date IS NOT NULL
      AND actual_close_date >= created_date
    GROUP BY account_id
),

cohorts AS (
    SELECT account_id,
           CAST(date_trunc('quarter', first_win_date) AS DATE) AS cohort_quarter
    FROM first_purchase
),

cohort_size AS (
    SELECT cohort_quarter,
           count(*) AS cohort_accounts,
           -- How many quarters of history this cohort could
           -- possibly show, given the as of date.
           date_diff('quarter', cohort_quarter,
                     CAST(date_trunc('quarter', DATE '2025-12-31') AS DATE))
                                    AS quarters_observable
    FROM cohorts
    GROUP BY cohort_quarter
),

wins_by_quarter AS (
    SELECT c.cohort_quarter,
           date_diff('quarter', c.cohort_quarter,
                     CAST(date_trunc('quarter', o.actual_close_date) AS DATE))
                                        AS quarter_index,
           count(DISTINCT o.account_id) AS accounts_buying,
           count(*)                     AS deals_won,
           sum(o.amount)                AS won_amount
    FROM opportunities AS o
    JOIN cohorts       AS c ON c.account_id = o.account_id
    WHERE o.stage = 'Closed Won'
      AND o.actual_close_date IS NOT NULL
      AND o.actual_close_date >= o.created_date
      AND o.amount IS NOT NULL
    GROUP BY c.cohort_quarter, quarter_index
)

SELECT w.cohort_quarter,
       s.cohort_accounts,
       s.quarters_observable,
       w.quarter_index,
       w.accounts_buying,
       w.deals_won,
       round(w.won_amount)                                          AS won_amount_this_quarter,
       -- Running total across the cohort's life. This is the
       -- column that answers what a first deal is worth.
       round(sum(w.won_amount) OVER (
             PARTITION BY w.cohort_quarter
             ORDER BY w.quarter_index
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))     AS cumulative_won,
       -- Cumulative revenue as a multiple of what the cohort spent
       -- in the quarter it landed.
       round(sum(w.won_amount) OVER (
             PARTITION BY w.cohort_quarter
             ORDER BY w.quarter_index
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
             / nullif(first_value(w.won_amount) OVER (
                   PARTITION BY w.cohort_quarter
                   ORDER BY w.quarter_index), 0), 2)                AS expansion_index,
       -- Share of the cohort transacting in this quarter. This is
       -- the retention half of the curve.
       round(100.0 * w.accounts_buying
             / nullif(s.cohort_accounts, 0), 1)                     AS pct_of_cohort_buying
FROM wins_by_quarter AS w
JOIN cohort_size     AS s ON s.cohort_quarter = w.cohort_quarter
WHERE s.cohort_accounts >= 8      -- thin cohorts make a noisy curve
ORDER BY w.cohort_quarter, w.quarter_index;
