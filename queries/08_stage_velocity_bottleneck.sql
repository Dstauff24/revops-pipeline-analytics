-- ============================================================
-- 08. Stage Velocity and the Bottleneck
--
-- QUESTION
--   How many days does a deal sit in each stage before it moves,
--   and which stage is holding the pipeline up right now?
--
-- DECISION IT INFORMS
--   Which stage to attack. Time in stage is the only pipeline
--   metric a manager can act on inside a single week: a deal
--   sitting 60 days in Negotiation needs a different intervention
--   (get legal on the phone, offer a term concession, walk away)
--   than a deal sitting 60 days in Discovery (it was never
--   qualified). This query separates the two so the intervention
--   matches the problem.
--
-- CAVEAT
--   Time in stage is measured from the previous stage change, or
--   from the opportunity's create date for the first stage, using
--   LAG over stage_history. Two limits follow. Rows where a rep
--   skipped a stage make the stage they skipped invisible and
--   inflate the time attributed to the stage before it: query 12
--   counts those. And ownership change rows (where from_stage
--   equals to_stage) are excluded from the LAG window, because a
--   reassignment is not stage movement, though it very often
--   causes the stall you see next to it.
-- ============================================================

WITH transitions AS (
    SELECT sh.opportunity_id,
           sh.from_stage,
           sh.to_stage,
           sh.changed_at,
           -- The previous stage change on this deal. For the very
           -- first transition there is none, so the opportunity's
           -- create date stands in.
           lag(sh.changed_at) OVER (
               PARTITION BY sh.opportunity_id
               ORDER BY sh.changed_at, sh.id
           ) AS previous_changed_at
    FROM stage_history AS sh
    WHERE sh.from_stage <> sh.to_stage    -- exclude ownership change rows
),

dwell AS (
    SELECT t.opportunity_id,
           t.from_stage AS stage,
           t.to_stage,
           date_diff('day',
                     coalesce(t.previous_changed_at, o.created_date),
                     t.changed_at) AS days_in_stage
    FROM transitions   AS t
    JOIN opportunities AS o ON o.opportunity_id = t.opportunity_id
    WHERE date_diff('day',
                    coalesce(t.previous_changed_at, o.created_date),
                    t.changed_at) >= 0     -- guards the reversed dates
),

-- What is sitting in each stage right now, and for how long. A
-- historical median cannot see the deals that have not moved yet,
-- and those are the ones a manager can still save.
currently_open AS (
    SELECT o.stage,
           count(*) AS open_deals_now,
           round(percentile_cont(0.50) WITHIN GROUP (
               ORDER BY date_diff('day',
                                  coalesce((SELECT max(sh2.changed_at)
                                            FROM stage_history sh2
                                            WHERE sh2.opportunity_id = o.opportunity_id),
                                           o.created_date),
                                  DATE '2025-12-31')
           )) AS median_days_sitting_now
    FROM opportunities AS o
    WHERE o.stage NOT IN ('Closed Won', 'Closed Lost')
    GROUP BY o.stage
)

SELECT d.stage,
       count(*)                                                       AS transitions_observed,
       round(avg(d.days_in_stage))                                    AS avg_days_in_stage,
       percentile_cont(0.50) WITHIN GROUP (ORDER BY d.days_in_stage)  AS median_days_in_stage,
       percentile_cont(0.90) WITHIN GROUP (ORDER BY d.days_in_stage)  AS p90_days_in_stage,
       -- Share of the total median cycle this stage accounts for.
       -- The bottleneck is whichever stage owns the largest slice.
       round(100.0 * percentile_cont(0.50) WITHIN GROUP (ORDER BY d.days_in_stage)
             / nullif(sum(percentile_cont(0.50) WITHIN GROUP (ORDER BY d.days_in_stage))
                      OVER (), 0), 1)                                 AS pct_of_median_cycle,
       -- Of the deals that left this stage, how many went forward
       -- rather than to Closed Lost.
       round(100.0 * count(*) FILTER (WHERE d.to_stage <> 'Closed Lost')
             / nullif(count(*), 0), 1)                                AS advanced_pct,
       coalesce(c.open_deals_now, 0)                                  AS open_deals_now,
       c.median_days_sitting_now
FROM dwell               AS d
LEFT JOIN currently_open AS c ON c.stage = d.stage
GROUP BY d.stage, c.open_deals_now, c.median_days_sitting_now
ORDER BY median_days_in_stage DESC;
