-- ============================================================
-- 07. Sales Cycle Length
--
-- QUESTION
--   How long does a deal actually take to close, by segment, and
--   how far is the typical deal from the average deal?
--
-- DECISION IT INFORMS
--   How far ahead pipeline has to be built, and what date to put
--   on a deal in the forecast. If the median Enterprise deal
--   takes five months, then anything not already in Discovery by
--   the start of Q1 is not a Q1 deal no matter what the rep
--   entered as an expected close date, and pipeline generation
--   targets have to be set two quarters out.
--
-- CAVEAT
--   The average is reported here only so it can be compared to
--   the median, and the gap between them is the finding: a long
--   right tail of stalled deals drags the mean somewhere no real
--   deal lives. Plan against the median and the 75th percentile.
--   Losses are measured separately from wins because a deal that
--   dies in Discovery dies fast, and blending the two makes the
--   cycle look shorter than any deal a rep will actually work.
--   Rows where the close date precedes the create date are
--   excluded rather than clamped: query 12 counts them. Outcome
--   is read from stage rather than from the is_won flag, because
--   the two disagree on a handful of records in this dataset and
--   stage is what the pipeline report renders. Grouping on the
--   nullable flag instead would silently split Lost into two
--   rows, one of them holding the records where nobody set it.
-- ============================================================

WITH closed_clean AS (
    SELECT o.opportunity_id,
           a.segment,
           o.source,
           o.stage,
           o.amount,
           date_diff('day', o.created_date, o.actual_close_date) AS cycle_days
    FROM opportunities AS o
    JOIN accounts      AS a ON a.account_id = o.account_id
    WHERE o.stage IN ('Closed Won', 'Closed Lost')
      AND o.actual_close_date IS NOT NULL
      AND o.actual_close_date >= o.created_date
)

SELECT segment,
       CASE stage WHEN 'Closed Won' THEN 'Won' ELSE 'Lost' END  AS outcome,
       count(*)                                           AS deals,
       round(avg(cycle_days))                             AS avg_days,
       percentile_cont(0.50) WITHIN GROUP (ORDER BY cycle_days) AS median_days,
       percentile_cont(0.75) WITHIN GROUP (ORDER BY cycle_days) AS p75_days,
       percentile_cont(0.90) WITHIN GROUP (ORDER BY cycle_days) AS p90_days,
       max(cycle_days)                                    AS max_days,
       -- How far the mean sits above the median, as a share of
       -- the median. Anything much over 15 percent means the
       -- average is being written by the tail.
       round(100.0 * (avg(cycle_days)
             - percentile_cont(0.50) WITHIN GROUP (ORDER BY cycle_days))
             / nullif(percentile_cont(0.50) WITHIN GROUP (ORDER BY cycle_days), 0), 1)
                                                          AS mean_above_median_pct,
       round(avg(amount))                                 AS avg_amount
FROM closed_clean
GROUP BY segment, stage
ORDER BY segment, outcome;
