-- ============================================================
-- 06. Win Rate by Segment and Source
--
-- QUESTION
--   Where does this team actually win: which combinations of
--   customer segment and lead source convert, and which ones
--   consume capacity without producing revenue?
--
-- DECISION IT INFORMS
--   What the team should stop working. A single blended win rate
--   hides the fact that the same rep hours produce very different
--   returns depending on what they are pointed at. If one
--   segment and source pair converts at a third of another, that
--   is a routing rule, an ideal customer profile revision, or a
--   decision to stop paying for that channel in that segment.
--
-- CAVEAT
--   Win rate on its own is the wrong thing to optimize. A cell
--   with a low rate and a large average deal can be worth more
--   per hour than a cell with a high rate and small deals, which
--   is why won revenue per opportunity worked is in this output
--   next to the rate. Deals with no amount are counted in the
--   rate and excluded from the revenue columns, so the two do not
--   reconcile exactly. A win is defined as stage = 'Closed Won'
--   rather than by the is_won flag, because the two disagree on
--   a handful of records here and query 12 counts them. Only closed deals count toward the rate:
--   open deals have not decided yet, and including them would
--   pull every recent cohort's rate toward zero.
-- ============================================================

SELECT a.segment,
       o.source,
       count(*)                                          AS opportunities,
       count(*) FILTER (WHERE o.stage IN ('Closed Won', 'Closed Lost'))
                                                         AS closed,
       count(*) FILTER (WHERE o.stage = 'Closed Won')                  AS won,
       -- nullif guards the divide: a segment and source pair with
       -- nothing closed yet returns NULL rather than blowing up
       -- or, worse, reporting a confident zero.
       round(100.0 * count(*) FILTER (WHERE o.stage = 'Closed Won')
             / nullif(count(*) FILTER (WHERE o.stage IN ('Closed Won', 'Closed Lost')), 0), 1)
                                                         AS win_rate_pct,
       round(coalesce(sum(o.amount) FILTER (WHERE o.stage = 'Closed Won'), 0))
                                                         AS won_revenue,
       round(avg(o.amount) FILTER (WHERE o.stage = 'Closed Won'))      AS avg_won_deal,
       -- The number that actually ranks the cells: revenue
       -- produced per opportunity the team had to work, win or
       -- lose. Effort is spent on all of them.
       round(coalesce(sum(o.amount) FILTER (WHERE o.stage = 'Closed Won'), 0)
             / nullif(count(*) FILTER (WHERE o.stage IN ('Closed Won', 'Closed Lost')), 0))
                                                         AS revenue_per_opp_worked
FROM opportunities AS o
JOIN accounts      AS a ON a.account_id = o.account_id
GROUP BY a.segment, o.source
HAVING count(*) FILTER (WHERE o.stage IN ('Closed Won', 'Closed Lost')) >= 20
ORDER BY a.segment, revenue_per_opp_worked DESC;
