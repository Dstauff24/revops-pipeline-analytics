-- ============================================================
-- BI EXTRACT: sales cycle by source and segment
-- Feeds dashboard 03 (Channel Efficiency)
--
-- WHY THIS IS A NEW FILE
--   Query 07 cuts cycle length by segment because that is the cut
--   that drives pipeline build targets. Dashboard 03 needs it by
--   source, so the efficiency picture can be time weighted: a
--   channel returning eight dollars in three months is a different
--   budget decision from one returning twelve in nine.
--
--   Wins and losses stay separate for the same reason query 07
--   separates them. A deal that dies in Discovery dies fast, and
--   blending the two makes every channel look quicker than any
--   deal a rep will actually work.
--
-- ALL DATA IS SYNTHETIC. See data/README.md.
-- ============================================================

WITH closed_clean AS (
    SELECT o.source,
           a.segment,
           o.stage,
           o.amount,
           date_diff('day', o.created_date, o.actual_close_date) AS cycle_days
    FROM opportunities AS o
    JOIN accounts      AS a ON a.account_id = o.account_id
    WHERE o.stage IN ('Closed Won', 'Closed Lost')
      AND o.actual_close_date IS NOT NULL
      AND o.actual_close_date >= o.created_date   -- excludes the reversed dates
)

SELECT source,
       CASE stage WHEN 'Closed Won' THEN 'Won' ELSE 'Lost' END  AS outcome,
       count(*)                                                 AS deals,
       round(avg(cycle_days))                                   AS avg_days,
       percentile_cont(0.50) WITHIN GROUP (ORDER BY cycle_days)  AS median_days,
       percentile_cont(0.75) WITHIN GROUP (ORDER BY cycle_days)  AS p75_days,
       percentile_cont(0.90) WITHIN GROUP (ORDER BY cycle_days)  AS p90_days,
       round(coalesce(sum(amount), 0))                          AS total_amount,
       round(avg(amount))                                       AS avg_amount
FROM closed_clean
GROUP BY source, stage
ORDER BY source, outcome;
