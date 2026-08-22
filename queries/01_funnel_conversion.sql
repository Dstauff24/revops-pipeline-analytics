-- ============================================================
-- 01. Funnel Conversion
--
-- QUESTION
--   Of the opportunities that enter the pipeline, what share
--   reach each subsequent stage, and where does the biggest
--   single drop happen?
--
-- DECISION IT INFORMS
--   Where to spend coaching time and enablement budget. A funnel
--   that leaks at Discovery is a qualification problem and gets
--   fixed with better discovery questions. A funnel that leaks at
--   Negotiation is a pricing or procurement problem and no amount
--   of prospecting training touches it. The two failures look
--   identical in a win rate number, which is why win rate alone
--   is not enough to act on.
--
-- CAVEAT
--   Stage reach is read from stage_history, not from the current
--   stage on the opportunity, because the current stage cannot
--   tell you where a closed lost deal died. Two known distortions
--   follow from that. First, reps skip stages: an opportunity can
--   appear in Proposal with no Discovery row, which understates
--   Discovery. Query 12 counts how often that happens. Second,
--   deals still open at the as of date are counted at the
--   furthest stage they have reached so far, so the later stages
--   are slightly understated for recent cohorts.
-- ============================================================

WITH stage_order(stage, ord) AS (
    VALUES ('Prospecting', 1),
           ('Discovery',   2),
           ('Proposal',    3),
           ('Negotiation', 4),
           ('Closed Won',  5)
),

-- Every opportunity is treated as having entered Prospecting,
-- whether or not a history row says so. The union deduplicates,
-- so a deal that bounced back into a stage is only counted once.
reached AS (
    SELECT opportunity_id, 'Prospecting' AS stage
    FROM opportunities

    UNION

    SELECT opportunity_id, to_stage
    FROM stage_history
    WHERE from_stage <> to_stage      -- ownership changes are not stage progress
),

stage_counts AS (
    SELECT so.ord,
           so.stage,
           count(DISTINCT r.opportunity_id) AS opportunities_reached
    FROM stage_order so
    LEFT JOIN reached r ON r.stage = so.stage
    GROUP BY so.ord, so.stage
),

entered AS (
    SELECT opportunities_reached AS top_of_funnel
    FROM stage_counts
    WHERE ord = 1
)

-- Self join on the stage counts, offset by one, so each row can
-- see the stage immediately above it.
SELECT this.stage,
       this.opportunities_reached,
       prior.stage                        AS prior_stage,
       prior.opportunities_reached        AS prior_stage_count,
       round(100.0 * this.opportunities_reached
             / nullif(prior.opportunities_reached, 0), 1) AS step_conversion_pct,
       round(100.0 * this.opportunities_reached
             / nullif(e.top_of_funnel, 0), 1)             AS pct_of_all_opportunities,
       prior.opportunities_reached - this.opportunities_reached AS deals_lost_at_this_step
FROM stage_counts       AS this
LEFT JOIN stage_counts  AS prior ON prior.ord = this.ord - 1
CROSS JOIN entered      AS e
ORDER BY this.ord;
