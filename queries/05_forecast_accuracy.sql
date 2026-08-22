-- ============================================================
-- 05. Forecast Accuracy
--
-- QUESTION
--   When a deal is called Commit, how often does it actually
--   close won, and does the answer depend on how long the rep has
--   been here?
--
-- DECISION IT INFORMS
--   What multiplier to apply to the rep submitted forecast before
--   it goes to the board, and who needs deal inspection rather
--   than a pipeline target. If Commit converts at 60 percent
--   instead of the 90 percent the category implies, the forecast
--   is not a forecast, it is a wish list, and the fix is to
--   redefine the category exit criteria rather than to lean on
--   reps harder. Also sets the ramp adjusted discount: a rep in
--   month four should not be forecast the same way as a rep in
--   year three.
--
-- CAVEAT
--   forecast_category on a closed deal is the last value the
--   record carried, not a snapshot taken at the start of the
--   quarter, because this dataset does not version that field.
--   That biases the numbers optimistic: some deals were moved
--   into Commit right before they closed won, which no real
--   forecast process would have gotten credit for. Read the
--   relative gap between tenure bands, which that bias affects
--   roughly evenly, rather than the absolute conversion rate.
--   Deals with no close date are excluded outright.
-- ============================================================

WITH closed_deals AS (
    SELECT o.opportunity_id,
           o.forecast_category,
           o.amount,
           o.stage = 'Closed Won' AS is_won,   -- stage is authoritative; see query 12
           o.expected_close_date,
           o.actual_close_date,
           date_diff('month', r.hire_date, o.actual_close_date) AS rep_tenure_months,
           CASE
               WHEN date_diff('month', r.hire_date, o.actual_close_date) < 12 THEN 'Under 1 year'
               WHEN date_diff('month', r.hire_date, o.actual_close_date) < 24 THEN '1 to 2 years'
               ELSE 'Over 2 years'
           END AS tenure_band
    FROM opportunities AS o
    JOIN reps          AS r ON r.rep_id = o.rep_id
    WHERE o.stage IN ('Closed Won', 'Closed Lost')
      AND o.actual_close_date IS NOT NULL
      AND o.actual_close_date >= o.created_date   -- drops the reversed dates
      AND o.amount IS NOT NULL
),

-- What each category is understood to promise. These are the
-- numbers the words are supposed to mean.
implied(forecast_category, implied_win_rate, category_rank) AS (
    VALUES ('Commit',    0.90, 1),
           ('Best Case', 0.50, 2),
           ('Pipeline',  0.20, 3),
           ('Omitted',   0.05, 4)
)

SELECT i.forecast_category,
       c.tenure_band,
       count(*)                                                     AS closed_deals,
       count(*) FILTER (WHERE c.is_won)                             AS deals_won,
       round(100.0 * count(*) FILTER (WHERE c.is_won)
             / nullif(count(*), 0), 1)                              AS actual_win_rate_pct,
       round(100.0 * i.implied_win_rate, 1)                         AS implied_win_rate_pct,
       -- Positive means the category promised more than it
       -- delivered. This is the forecast drift.
       round(100.0 * i.implied_win_rate
             - 100.0 * count(*) FILTER (WHERE c.is_won)
               / nullif(count(*), 0), 1)                            AS drift_points,
       round(sum(c.amount))                                         AS forecast_amount,
       round(coalesce(sum(c.amount) FILTER (WHERE c.is_won), 0))    AS realized_amount,
       -- Dollar variance against what the category implied would
       -- land. This is the number that shows up as a miss.
       round(coalesce(sum(c.amount) FILTER (WHERE c.is_won), 0)
             - sum(c.amount) * i.implied_win_rate)                  AS dollar_variance,
       -- Slip on won deals only. Lost deals drag this negative
       -- because a deal that dies in Discovery dies early, which
       -- is not the same thing as a forecast being accurate.
       round(avg(date_diff('day', c.expected_close_date, c.actual_close_date))
             FILTER (WHERE c.is_won))                               AS avg_days_slipped_on_wins
FROM closed_deals AS c
JOIN implied      AS i ON i.forecast_category = c.forecast_category
GROUP BY i.forecast_category, i.implied_win_rate, i.category_rank, c.tenure_band
HAVING count(*) >= 15
ORDER BY i.category_rank, c.tenure_band;
