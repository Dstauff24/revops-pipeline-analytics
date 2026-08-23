-- ============================================================
-- BI EXTRACT: open pipeline at deal grain
-- Feeds dashboard 01 (Pipeline Health)
--
-- WHY THIS IS NOT queries/04 OR queries/13
--   Those two answer a fixed question and pre-aggregate to do it:
--   query 04 rolls up to segment, query 13 to age bucket. A
--   dashboard cannot filter below the grain it was handed, and
--   dashboard 01 needs territory, segment and rep filters that
--   the analysis queries have already collapsed away.
--
--   So this extract keeps one row per open opportunity and lets
--   the BI tool aggregate at view time. The derived columns
--   (momentum, age bucket) use exactly the same thresholds as
--   query 13, so the dashboard and the analysis agree.
--
-- ALL DATA IS SYNTHETIC. See data/README.md.
-- ============================================================

WITH segment_cycle AS (
    -- Same segment relative yardstick query 13 uses, so the
    -- momentum labels match between the dashboard and the SQL.
    SELECT a.segment,
           percentile_cont(0.50) WITHIN GROUP (
               ORDER BY date_diff('day', o.created_date, o.actual_close_date))
               AS median_won_cycle_days
    FROM opportunities AS o
    JOIN accounts      AS a ON a.account_id = o.account_id
    WHERE o.stage = 'Closed Won'
      AND o.actual_close_date IS NOT NULL
      AND o.actual_close_date >= o.created_date
    GROUP BY a.segment
),

open_deals AS (
    SELECT o.opportunity_id,
           a.company_name                                     AS account_name,
           a.industry,
           a.segment,
           t.name                                             AS territory,
           t.region,
           t.market_tier,
           r.name                                             AS rep_name,
           r.segment_focus                                    AS rep_segment_focus,
           r.termination_date IS NOT NULL                     AS owned_by_departed_rep,
           o.source,
           o.stage,
           o.forecast_category,
           o.amount,
           o.created_date,
           o.expected_close_date,
           date_diff('day', o.created_date, DATE '2025-12-31') AS days_since_created,
           date_diff('day',
                     coalesce((SELECT max(sh.changed_at)
                                 FROM stage_history AS sh
                                WHERE sh.opportunity_id = o.opportunity_id),
                              o.created_date),
                     DATE '2025-12-31')                        AS days_since_last_move,
           -- Standard stage weighting, carried here so the
           -- dashboard does not have to re-derive it and get it
           -- subtly different from query 04.
           CASE o.stage
               WHEN 'Prospecting' THEN 0.10
               WHEN 'Discovery'   THEN 0.25
               WHEN 'Proposal'    THEN 0.45
               WHEN 'Negotiation' THEN 0.70
           END                                                AS stage_weight
    FROM opportunities AS o
    JOIN accounts      AS a ON a.account_id  = o.account_id
    JOIN reps          AS r ON r.rep_id      = o.rep_id
    JOIN territories   AS t ON t.territory_id = a.territory_id
    WHERE o.stage NOT IN ('Closed Won', 'Closed Lost')
)

SELECT d.opportunity_id,
       d.account_name,
       d.industry,
       d.segment,
       d.territory,
       d.region,
       d.market_tier,
       d.rep_name,
       d.rep_segment_focus,
       d.owned_by_departed_rep,
       d.source,
       d.stage,
       d.forecast_category,
       d.amount,
       round(d.amount * d.stage_weight, 2)          AS weighted_amount,
       d.created_date,
       d.expected_close_date,
       d.days_since_created,
       d.days_since_last_move,
       CASE
           WHEN d.days_since_created <=  30 THEN 'a. 0-30 days'
           WHEN d.days_since_created <=  60 THEN 'b. 31-60 days'
           WHEN d.days_since_created <=  90 THEN 'c. 61-90 days'
           WHEN d.days_since_created <= 180 THEN 'd. 91-180 days'
           WHEN d.days_since_created <= 365 THEN 'e. 181-365 days'
           ELSE                                  'f. over 365 days'
       END                                          AS age_bucket,
       CASE
           WHEN d.days_since_last_move >= c.median_won_cycle_days * 1.5  THEN 'Stalled'
           WHEN d.days_since_last_move >= c.median_won_cycle_days * 0.75 THEN 'Slowing'
           ELSE                                                              'Moving'
       END                                          AS momentum,
       d.amount IS NULL                             AS missing_amount
FROM open_deals    AS d
JOIN segment_cycle AS c ON c.segment = d.segment
ORDER BY d.opportunity_id;
