-- ============================================================
-- 04. Pipeline Coverage
--
-- QUESTION
--   Going into next quarter, does each segment have enough open
--   pipeline to hit its number, and how much of that pipeline is
--   real enough to count on?
--
-- DECISION IT INFORMS
--   Whether to keep selling or start building. A segment at 2x
--   coverage does not have a closing problem next quarter, it has
--   a prospecting problem this quarter, and the response is
--   pipeline generation now rather than deal inspection in week
--   eleven. The stage weighted number is the one to plan against.
--   The raw number is the one reps quote.
--
-- CAVEAT
--   Two soft spots. The target is built from annual quota divided
--   by four, which ignores that most teams weight Q4 heavier than
--   Q1, so this understates the Q1 gap at a real company. And
--   coverage is grouped by the account's segment while quota is
--   carried by the rep's segment focus, and those two do not
--   always agree: reps sell outside their stated segment. The
--   mismatch is small here but it is the reason the two columns
--   should never be read as a clean apples to apples ratio.
--   Stage weights below are the standard blunt instrument, not
--   fitted probabilities. Query 05 shows why fitted would be
--   better. Finally, coverage ratios are not comparable across
--   segments with different cycle lengths. Enterprise pipeline
--   sits open roughly twice as long as SMB pipeline (query 07),
--   so it accumulates to a higher multiple at the same health.
--   Compare each segment to its own history, not to its
--   neighbors.
-- ============================================================

WITH quarter_target AS (
    SELECT segment_focus            AS segment,
           count(*)                 AS active_reps,
           sum(quota_annual) / 4.0  AS quarterly_target
    FROM reps
    WHERE termination_date IS NULL
    GROUP BY segment_focus
),

open_pipeline AS (
    SELECT a.segment,
           count(*)                                      AS open_deals,
           sum(o.amount)                                 AS open_amount,
           sum(o.amount) FILTER (WHERE o.forecast_category = 'Commit')
                                                         AS commit_amount,
           sum(o.amount) FILTER (WHERE o.expected_close_date <= DATE '2026-03-31')
                                                         AS closing_this_quarter,
           -- The usual stage weighting. Blunt, but it is what
           -- gets used, so it is what gets reported.
           sum(o.amount * CASE o.stage
                              WHEN 'Prospecting' THEN 0.10
                              WHEN 'Discovery'   THEN 0.25
                              WHEN 'Proposal'    THEN 0.45
                              WHEN 'Negotiation' THEN 0.70
                              ELSE 0
                          END)                           AS weighted_amount
    FROM opportunities AS o
    JOIN accounts      AS a ON a.account_id = o.account_id
    WHERE o.stage NOT IN ('Closed Won', 'Closed Lost')
      AND o.amount IS NOT NULL      -- deals with no amount cannot be counted, only chased
    GROUP BY a.segment
)

SELECT t.segment,
       t.active_reps,
       round(t.quarterly_target)                                        AS quarterly_target,
       p.open_deals,
       round(p.open_amount)                                             AS open_pipeline,
       round(p.weighted_amount)                                         AS stage_weighted_pipeline,
       round(p.commit_amount)                                           AS commit_pipeline,
       round(p.open_amount / nullif(t.quarterly_target, 0), 2)          AS raw_coverage_x,
       round(p.weighted_amount / nullif(t.quarterly_target, 0), 2)      AS weighted_coverage_x,
       CASE
           WHEN p.weighted_amount / nullif(t.quarterly_target, 0) >= 1.20
               THEN 'Covered'
           WHEN p.weighted_amount / nullif(t.quarterly_target, 0) >= 0.85
               THEN 'Tight, inspect weekly'
           WHEN p.weighted_amount / nullif(t.quarterly_target, 0) >= 0.55
               THEN 'Short, build pipeline now'
           ELSE 'Will miss, reset the number'
       END                                                              AS coverage_call,
       round(p.open_amount / nullif(t.active_reps, 0))                  AS pipeline_per_rep
FROM quarter_target AS t
LEFT JOIN open_pipeline AS p ON p.segment = t.segment
ORDER BY weighted_coverage_x;
