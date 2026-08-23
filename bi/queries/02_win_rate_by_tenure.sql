-- ============================================================
-- BI EXTRACT: win rate by rep tenure at close
-- Feeds dashboard 02 (Rep Performance and Ramp)
--
-- WHY THIS IS A NEW FILE
--   No analysis query produces this grain. Query 06 is segment by
--   source, query 05 is forecast category by tenure. Dashboard 02
--   needs win rate by tenure band, cut by segment, which is a
--   third thing. Rather than bend query 06 to fit the dashboard,
--   the extract lives here and queries/ stays as it was.
--
--   Tenure is measured at close, not today, so a rep who has since
--   become senior does not retroactively improve the deals they
--   closed in month three.
--
-- ALL DATA IS SYNTHETIC. See data/README.md.
-- ============================================================

WITH closed AS (
    SELECT o.opportunity_id,
           a.segment,
           o.source,
           o.stage,
           o.amount,
           date_diff('month', r.hire_date, o.actual_close_date) AS tenure_months_at_close,
           'Q' || quarter(r.hire_date)                          AS hire_quarter
    FROM opportunities AS o
    JOIN reps          AS r ON r.rep_id     = o.rep_id
    JOIN accounts      AS a ON a.account_id = o.account_id
    WHERE o.stage IN ('Closed Won', 'Closed Lost')
      AND o.actual_close_date IS NOT NULL
      AND o.actual_close_date >= o.created_date
      AND o.actual_close_date >= r.hire_date
)

SELECT CASE
           WHEN tenure_months_at_close <  3 THEN 'a. months 01-03'
           WHEN tenure_months_at_close <  6 THEN 'b. months 04-06'
           WHEN tenure_months_at_close < 12 THEN 'c. months 07-12'
           WHEN tenure_months_at_close < 24 THEN 'd. months 13-24'
           ELSE                                 'e. over 24 months'
       END                                                   AS tenure_band,
       segment,
       count(*)                                              AS closed_deals,
       count(*) FILTER (WHERE stage = 'Closed Won')           AS deals_won,
       round(100.0 * count(*) FILTER (WHERE stage = 'Closed Won')
             / nullif(count(*), 0), 1)                       AS win_rate_pct,
       round(coalesce(sum(amount) FILTER (WHERE stage = 'Closed Won'), 0))
                                                             AS won_revenue,
       round(avg(amount) FILTER (WHERE stage = 'Closed Won')) AS avg_won_deal
FROM closed
GROUP BY tenure_band, segment
HAVING count(*) >= 20      -- same stability floor query 06 uses
ORDER BY tenure_band, segment;
