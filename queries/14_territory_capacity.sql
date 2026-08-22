-- ============================================================
-- 14. Territory Capacity
--
-- QUESTION
--   Is each territory carrying an amount of pipeline its rep
--   count can actually work, and does headcount line up with
--   where the market is?
--
-- DECISION IT INFORMS
--   Where the next hire goes, and where a territory needs to be
--   split. A territory running well above the team's pipeline per
--   rep is not a high performing territory, it is a territory
--   where deals are going unworked, and the deals it drops do not
--   show up anywhere as a loss. They just age out, which is what
--   query 13 is looking at from the other side. The reverse case
--   matters too: a rep with a third of the average book is a
--   coverage problem dressed up as a performance problem, and no
--   amount of coaching fixes it.
--
-- CAVEAT
--   Rep count is headcount, not capacity. A territory with three
--   reps, two of them hired in the last two quarters, has roughly
--   two reps worth of capacity by the ramp curve in query 02, and
--   the ramp adjusted column below tries to say so. It is a
--   rough adjustment, not a staffing model. tam_estimate is a
--   planning assumption somebody typed into a spreadsheet, so
--   penetration against it is directional at best. And reps sell
--   outside their assigned territory, which this query does not
--   attempt to unwind: pipeline is counted where the account
--   sits, headcount where the rep sits.
-- ============================================================

WITH rep_capacity AS (
    SELECT r.territory_id,
           count(*)                                                       AS active_reps,
           sum(r.quota_annual)                                            AS territory_quota,
           -- Ramp adjusted headcount. A rep under six months
           -- counts as a fraction of a rep, following the curve
           -- that query 02 measures.
           sum(CASE
                   WHEN date_diff('month', r.hire_date, DATE '2025-12-31') < 3  THEN 0.25
                   WHEN date_diff('month', r.hire_date, DATE '2025-12-31') < 6  THEN 0.55
                   WHEN date_diff('month', r.hire_date, DATE '2025-12-31') < 12 THEN 0.85
                   ELSE 1.00
               END)                                                       AS effective_reps,
           count(*) FILTER (
               WHERE date_diff('month', r.hire_date, DATE '2025-12-31') < 12)
                                                                          AS reps_under_1_year
    FROM reps AS r
    WHERE r.termination_date IS NULL
    GROUP BY r.territory_id
),

territory_pipeline AS (
    SELECT a.territory_id,
           count(DISTINCT a.account_id)                                   AS accounts,
           count(*) FILTER (WHERE o.stage NOT IN ('Closed Won', 'Closed Lost'))
                                                                          AS open_deals,
           sum(o.amount) FILTER (WHERE o.stage NOT IN ('Closed Won', 'Closed Lost'))
                                                                          AS open_pipeline,
           sum(o.amount) FILTER (
               WHERE o.stage = 'Closed Won'
                 AND o.actual_close_date >= DATE '2025-01-01')            AS won_revenue_2025
    FROM accounts           AS a
    LEFT JOIN opportunities AS o ON o.account_id = a.account_id
    GROUP BY a.territory_id
)

SELECT t.name                                                          AS territory,
       t.region,
       t.market_tier,
       c.active_reps,
       round(c.effective_reps, 2)                                       AS ramp_adjusted_reps,
       c.reps_under_1_year,
       p.accounts,
       p.open_deals,
       round(coalesce(p.open_pipeline, 0))                              AS open_pipeline,
       round(coalesce(p.won_revenue_2025, 0))                           AS won_revenue_2025,
       round(coalesce(p.open_pipeline, 0) / nullif(c.active_reps, 0))   AS pipeline_per_rep,
       -- The column that actually drives the staffing call.
       round(coalesce(p.open_pipeline, 0)
             / nullif(c.effective_reps, 0))                             AS pipeline_per_effective_rep,
       round(coalesce(p.open_deals, 0) / nullif(c.effective_reps, 0), 1)
                                                                        AS open_deals_per_effective_rep,
       round(100.0 * coalesce(p.won_revenue_2025, 0)
             / nullif(t.tam_estimate, 0), 3)                            AS pct_of_tam_won_2025,
       CASE
           WHEN coalesce(p.open_pipeline, 0) / nullif(c.effective_reps, 0)
                > 1.6 * (SELECT sum(coalesce(open_pipeline, 0)) FROM territory_pipeline)
                       / (SELECT sum(effective_reps) FROM rep_capacity)
               THEN 'Over capacity, split or hire'
           WHEN coalesce(p.open_pipeline, 0) / nullif(c.effective_reps, 0)
                < 0.6 * (SELECT sum(coalesce(open_pipeline, 0)) FROM territory_pipeline)
                       / (SELECT sum(effective_reps) FROM rep_capacity)
               THEN 'Under fed, check routing before coaching'
           ELSE 'In range'
       END                                                              AS capacity_call
FROM territories          AS t
JOIN rep_capacity         AS c ON c.territory_id = t.territory_id
LEFT JOIN territory_pipeline AS p ON p.territory_id = t.territory_id
ORDER BY pipeline_per_effective_rep DESC;
