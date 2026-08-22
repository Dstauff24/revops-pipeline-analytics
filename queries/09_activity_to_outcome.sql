-- ============================================================
-- 09. Activity to Outcome
--
-- QUESTION
--   Do deals that get worked harder early win more often, and
--   does the type of touch matter more than the count?
--
-- DECISION IT INFORMS
--   Whether an activity target is worth setting, and if so, on
--   what. Most teams set a call count because a call count is
--   easy to measure. If meetings and demos separate winners from
--   losers and raw volume does not, then the target should be
--   meetings booked, and a rep sending 80 emails a week without
--   booking one is not busy, they are stuck. It also sets the
--   early warning threshold: a deal past 30 days with almost no
--   logged touches is not a slow deal, it is a dead one that
--   nobody has closed out yet.
--
-- CAVEAT
--   This is the easiest query in the repo to draw a wrong
--   conclusion from, so two design decisions are worth stating.
--
--   First, activity is counted only in the deal's first 30 days,
--   and only deals that lived at least 30 days are included.
--   Counting activity over the whole life of a deal measures deal
--   length, not effort: a deal open for a year accumulates
--   touches by existing. Normalizing to touches per week does not
--   fix it either, it just inverts the bias, because a deal that
--   died in nine days shows a high weekly rate. A fixed window
--   gives every deal the same opportunity to be worked.
--
--   Second, and this does not go away: activity does not cause
--   wins here. A buyer who is engaged takes more meetings, so the
--   causation plausibly runs backwards. Watch the median deal age
--   column fall as intensity rises: engaged deals also move
--   faster, which is a third variable sitting behind both. Treat
--   this as a screening signal, not a management target. Logged
--   is also not the same as happened: email syncs itself, calls
--   get logged when a rep bothers.
-- ============================================================

WITH deal_activity AS (
    SELECT o.opportunity_id,
           o.stage,
           o.amount,
           a.segment,
           date_diff('day', o.created_date, o.actual_close_date)  AS deal_age_days,
           count(act.activity_id) FILTER (
               WHERE act.activity_date <= o.created_date + INTERVAL 30 DAY)
                                                                  AS activities_first_30d,
           count(act.activity_id) FILTER (
               WHERE act.activity_type IN ('Meeting', 'Demo')
                 AND act.activity_date <= o.created_date + INTERVAL 30 DAY)
                                                                  AS meetings_first_30d,
           count(act.activity_id)                                 AS activities_lifetime
    FROM opportunities   AS o
    JOIN accounts        AS a   ON a.account_id = o.account_id
    LEFT JOIN activities AS act ON act.opportunity_id = o.opportunity_id
    WHERE o.stage IN ('Closed Won', 'Closed Lost')
      AND o.actual_close_date IS NOT NULL
      -- Every deal in the population had a full 30 day window in
      -- which it could have been worked.
      AND o.actual_close_date >= o.created_date + INTERVAL 30 DAY
    GROUP BY o.opportunity_id, o.stage, o.amount, a.segment,
             o.created_date, o.actual_close_date
),

quintiles AS (
    SELECT *,
           ntile(5) OVER (PARTITION BY segment ORDER BY activities_first_30d)
               AS intensity_quintile
    FROM deal_activity
)

SELECT segment,
       intensity_quintile,
       count(*)                                                AS deals,
       min(activities_first_30d)                               AS touches_floor,
       max(activities_first_30d)                               AS touches_ceiling,
       round(avg(activities_first_30d), 1)                     AS avg_touches_first_30d,
       round(avg(meetings_first_30d), 1)                       AS avg_meetings_first_30d,
       count(*) FILTER (WHERE stage = 'Closed Won')            AS won,
       round(100.0 * count(*) FILTER (WHERE stage = 'Closed Won')
             / nullif(count(*), 0), 1)                         AS win_rate_pct,
       -- The confound, printed rather than hidden. Heavily worked
       -- deals also close faster, so some of the win rate lift
       -- above belongs to buyer engagement, not to rep effort.
       round(percentile_cont(0.50) WITHIN GROUP (ORDER BY deal_age_days))
                                                               AS median_deal_age_days,
       round(avg(activities_lifetime), 1)                      AS avg_touches_lifetime
FROM quintiles
GROUP BY segment, intensity_quintile
ORDER BY segment, intensity_quintile;
