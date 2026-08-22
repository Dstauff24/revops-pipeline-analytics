-- ============================================================
-- 13. Pipeline Aging
--
-- QUESTION
--   How old is the open pipeline, how much of it has stopped
--   moving, and how much of the number the team is carrying is
--   sitting behind deals that are not going to close?
--
-- DECISION IT INFORMS
--   What to close out. Aged pipeline is not neutral: it inflates
--   coverage, it makes the forecast look safer than it is, and it
--   consumes the review time that should be going to live deals.
--   The output is a work list. Anything in the oldest buckets
--   gets a decision this week: a real next step with a date, or
--   Closed Lost. Both are better than a deal that has been in
--   Proposal since spring.
--
-- CAVEAT
--   Age is measured two ways here, and they answer different
--   questions. Days since creation says how long the customer has
--   been in play. Days since the last stage change says whether
--   anyone is still working it, and it is the more useful of the
--   two: a 200 day Enterprise deal that moved last week is
--   healthy, and a 60 day SMB deal that has not moved in 45 days
--   is not. Thresholds are set against each segment's own median
--   cycle from query 07, because one global number would call
--   every Enterprise deal stale and let every SMB deal pass.
--   Deals with no amount are counted but carry no dollars, so the
--   bucket dollar totals understate.
-- ============================================================

WITH segment_cycle AS (
    -- Each segment's own median won cycle, used as the yardstick
    -- instead of a single company wide number.
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
           o.stage,
           o.amount,
           a.segment,
           r.name                                                        AS rep_name,
           r.termination_date,
           date_diff('day', o.created_date, DATE '2025-12-31')           AS days_since_created,
           date_diff('day',
                     coalesce((SELECT max(sh.changed_at)
                                 FROM stage_history AS sh
                                WHERE sh.opportunity_id = o.opportunity_id),
                              o.created_date),
                     DATE '2025-12-31')                                  AS days_since_last_move
    FROM opportunities AS o
    JOIN accounts      AS a ON a.account_id = o.account_id
    JOIN reps          AS r ON r.rep_id = o.rep_id
    WHERE o.stage NOT IN ('Closed Won', 'Closed Lost')
),

bucketed AS (
    SELECT d.*,
           c.median_won_cycle_days,
           CASE
               WHEN d.days_since_created <= 30                              THEN 'a. 0-30 days'
               WHEN d.days_since_created <= 60                              THEN 'b. 31-60 days'
               WHEN d.days_since_created <= 90                              THEN 'c. 61-90 days'
               WHEN d.days_since_created <= 180                             THEN 'd. 91-180 days'
               WHEN d.days_since_created <= 365                             THEN 'e. 181-365 days'
               ELSE                                                             'f. over 365 days'
           END AS age_bucket,
           -- The judgment call, made against the segment's own
           -- cycle rather than a flat threshold.
           CASE
               WHEN d.days_since_last_move >= c.median_won_cycle_days * 1.5 THEN 'Stalled'
               WHEN d.days_since_last_move >= c.median_won_cycle_days * 0.75 THEN 'Slowing'
               ELSE                                                              'Moving'
           END AS momentum
    FROM open_deals     AS d
    JOIN segment_cycle  AS c ON c.segment = d.segment
)

SELECT age_bucket,
       momentum,
       count(*)                                                    AS open_deals,
       round(coalesce(sum(amount), 0))                             AS pipeline_dollars,
       round(100.0 * coalesce(sum(amount), 0)
             / nullif(sum(sum(amount)) OVER (), 0), 1)             AS pct_of_open_pipeline,
       round(avg(days_since_created))                              AS avg_days_since_created,
       round(avg(days_since_last_move))                            AS avg_days_since_last_move,
       count(*) FILTER (WHERE stage = 'Negotiation')               AS in_negotiation,
       count(*) FILTER (WHERE termination_date IS NOT NULL)        AS owned_by_departed_rep,
       count(*) FILTER (WHERE amount IS NULL)                      AS missing_amount
FROM bucketed
GROUP BY age_bucket, momentum
ORDER BY age_bucket, momentum;
