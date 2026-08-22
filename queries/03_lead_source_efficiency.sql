-- ============================================================
-- 03. Lead Source Efficiency
--
-- QUESTION
--   Which lead sources produce closed revenue per dollar of
--   marketing spend, and how does that change when you account
--   for sales cycle length?
--
-- DECISION IT INFORMS
--   Where next quarter's marketing budget goes. Sources that look
--   efficient on cost per lead often lose that advantage once you
--   weight for conversion rate and time to close. A source that
--   returns twelve dollars per dollar spent but takes nine months
--   to do it is a different budget decision than one that returns
--   eight dollars in three months, especially if the quarter has
--   a number to hit.
--
-- CAVEAT
--   Cost is allocated at the lead level, so multi-touch
--   attribution is out of scope. A deal that started as a cold
--   call and closed after a trade show credits the cold call and
--   nothing else. Treat this as directional for budget shifts,
--   not as an attribution model. Cycle length is measured only on
--   won deals, which biases it short for slow sources: their
--   losses take even longer and are not in that number. Sources
--   with fewer than 100 leads are filtered out because the
--   revenue per dollar figure is unstable below that.
-- ============================================================

WITH lead_outcomes AS (
    SELECT l.lead_id,
           l.source,
           l.marketing_cost_allocated,
           o.opportunity_id,
           o.amount,
           o.stage,
           o.created_date,
           o.actual_close_date,
           -- Reversed dates are real rows in this dataset. They
           -- are excluded from cycle math rather than clamped,
           -- because a negative cycle is not a fast deal.
           CASE
               WHEN o.actual_close_date IS NOT NULL
                AND o.actual_close_date >= o.created_date
               THEN date_diff('day', o.created_date, o.actual_close_date)
           END AS cycle_days
    FROM leads AS l
    LEFT JOIN opportunities AS o
           ON o.opportunity_id = l.converted_opportunity_id
),

by_source AS (
    SELECT source,
           count(*)                                              AS leads,
           round(sum(marketing_cost_allocated))                  AS marketing_spend,
           round(avg(marketing_cost_allocated), 2)               AS cost_per_lead,
           count(opportunity_id)                                 AS opportunities,
           count(*) FILTER (WHERE stage = 'Closed Won')                        AS deals_won,
           round(sum(amount) FILTER (WHERE stage = 'Closed Won'))              AS won_revenue,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY cycle_days)
               FILTER (WHERE stage = 'Closed Won')                             AS median_days_to_close
    FROM lead_outcomes
    GROUP BY source
    HAVING count(*) >= 100        -- below this the ratios are noise
)

SELECT source,
       leads,
       marketing_spend,
       cost_per_lead,
       opportunities,
       round(100.0 * opportunities / nullif(leads, 0), 1)        AS lead_to_opp_pct,
       deals_won,
       round(100.0 * deals_won / nullif(opportunities, 0), 1)    AS opp_win_rate_pct,
       won_revenue,
       round(marketing_spend / nullif(deals_won, 0))             AS acquisition_cost_per_win,
       round(won_revenue / nullif(marketing_spend, 0), 2)        AS revenue_per_dollar,
       median_days_to_close,
       -- The same return, expressed per quarter of capital tied
       -- up. This is the column that reorders the table, and it
       -- is the one worth arguing about in a budget meeting.
       round((won_revenue / nullif(marketing_spend, 0))
             / nullif(median_days_to_close / 90.0, 0), 2)        AS revenue_per_dollar_per_quarter
FROM by_source
ORDER BY revenue_per_dollar DESC;
