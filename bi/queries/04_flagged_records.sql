-- ============================================================
-- BI EXTRACT: record level drill down for the hygiene audit
-- Feeds dashboard 04 (Data Quality Monitor)
--
-- WHY THIS IS NOT queries/12
--   Query 12 answers "what is broken and what does it cost" and
--   returns thirteen summary rows. That is the right answer for a
--   person reading SQL and the wrong one for a dashboard, because
--   the whole value of putting hygiene in front of the RevOps team
--   is that somebody can click the number and get the work list.
--
--   This extract emits one row per (record, issue) pair using the
--   same thirteen checks, the same severities, and the same
--   priority ranking as query 12. A record failing two checks
--   appears twice, on purpose: it is two pieces of work.
--
--   Every row carries the owning rep and account, because the
--   first question anyone asks about a bad record is whose it is.
--
-- ALL DATA IS SYNTHETIC. See data/README.md.
-- ============================================================

WITH opp_context AS (
    SELECT o.opportunity_id,
           o.stage,
           o.amount,
           o.created_date,
           o.actual_close_date,
           o.forecast_category,
           o.loss_reason,
           o.is_won,
           a.company_name          AS account_name,
           a.segment,
           r.name                  AS rep_name,
           r.termination_date      AS rep_termination_date,
           t.name                  AS territory
    FROM opportunities AS o
    JOIN accounts      AS a ON a.account_id   = o.account_id
    JOIN reps          AS r ON r.rep_id       = o.rep_id
    JOIN territories   AS t ON t.territory_id = a.territory_id
),

last_movement AS (
    SELECT o.opportunity_id,
           coalesce(max(sh.changed_at), o.created_date) AS last_changed_at
    FROM opportunities      AS o
    LEFT JOIN stage_history AS sh ON sh.opportunity_id = o.opportunity_id
    GROUP BY o.opportunity_id, o.created_date
),

stage_rank(stage, ord) AS (
    VALUES ('Prospecting', 1), ('Discovery', 2), ('Proposal', 3),
           ('Negotiation', 4), ('Closed Won', 5), ('Closed Lost', 5)
),

normalized_accounts AS (
    SELECT account_id,
           company_name,
           trim(regexp_replace(
               regexp_replace(lower(company_name), '[^a-z0-9]+', ' ', 'g'),
               '\s+(inc|llc|l l c|corp|corporation|co|company|group|grp|partners|holdings)\s*$',
               '')) AS name_key
    FROM accounts
),

flagged AS (

    SELECT 1 AS check_id, 'Opportunity has no amount' AS issue_type,
           'Distorts revenue reporting' AS severity,
           'opportunity' AS record_type, opportunity_id AS record_id,
           account_name, rep_name, territory, segment, stage,
           CAST(NULL AS DECIMAL(12,2)) AS amount, created_date, actual_close_date,
           'Amount is null; deal contributes nothing to any revenue total' AS detail
    FROM opp_context WHERE amount IS NULL

    UNION ALL
    SELECT 2, 'Opportunity amount is zero or negative', 'Distorts revenue reporting',
           'opportunity', opportunity_id, account_name, rep_name, territory, segment, stage,
           amount, created_date, actual_close_date,
           'Amount is ' || CAST(amount AS VARCHAR) || '; nets against real revenue'
    FROM opp_context WHERE amount IS NOT NULL AND amount <= 0

    UNION ALL
    SELECT 3, 'Close date precedes create date', 'Blocks cycle time reporting',
           'opportunity', opportunity_id, account_name, rep_name, territory, segment, stage,
           amount, created_date, actual_close_date,
           'Closed ' || CAST(date_diff('day', actual_close_date, created_date) AS VARCHAR)
             || ' days before it was created'
    FROM opp_context
    WHERE actual_close_date IS NOT NULL AND actual_close_date < created_date

    UNION ALL
    SELECT 4, 'Closed deal has no close date', 'Blocks period reporting',
           'opportunity', opportunity_id, account_name, rep_name, territory, segment, stage,
           amount, created_date, actual_close_date,
           'Stage is ' || stage || ' with no close date; invisible to period filters'
    FROM opp_context
    WHERE stage IN ('Closed Won', 'Closed Lost') AND actual_close_date IS NULL

    UNION ALL
    SELECT 5, 'Open deal has a close date', 'Distorts pipeline reporting',
           'opportunity', opportunity_id, account_name, rep_name, territory, segment, stage,
           amount, created_date, actual_close_date,
           'Stage is ' || stage || ' but a close date is set'
    FROM opp_context
    WHERE stage NOT IN ('Closed Won', 'Closed Lost') AND actual_close_date IS NOT NULL

    UNION ALL
    SELECT 6, 'Closed Lost with no loss reason', 'Cleanup and process',
           'opportunity', opportunity_id, account_name, rep_name, territory, segment, stage,
           amount, created_date, actual_close_date,
           'No loss reason recorded; dropped from win loss analysis'
    FROM opp_context
    WHERE stage = 'Closed Lost' AND (loss_reason IS NULL OR trim(loss_reason) = '')

    UNION ALL
    SELECT 7, 'is_won flag disagrees with stage', 'Blocks revenue reporting',
           'opportunity', opportunity_id, account_name, rep_name, territory, segment, stage,
           amount, created_date, actual_close_date,
           'Stage is ' || stage || ' but is_won is '
             || coalesce(CAST(is_won AS VARCHAR), 'null')
    FROM opp_context
    WHERE (stage = 'Closed Won'  AND coalesce(is_won, FALSE) = FALSE)
       OR (stage = 'Closed Lost' AND coalesce(is_won, FALSE) = TRUE)
       OR (stage NOT IN ('Closed Won', 'Closed Lost') AND is_won IS NOT NULL)

    UNION ALL
    SELECT 8, 'Open deal with no stage movement in 180 days', 'Distorts pipeline reporting',
           'opportunity', c.opportunity_id, c.account_name, c.rep_name, c.territory,
           c.segment, c.stage, c.amount, c.created_date, c.actual_close_date,
           'No stage change in '
             || CAST(date_diff('day', m.last_changed_at, DATE '2025-12-31') AS VARCHAR)
             || ' days'
    FROM opp_context   AS c
    JOIN last_movement AS m ON m.opportunity_id = c.opportunity_id
    WHERE c.stage NOT IN ('Closed Won', 'Closed Lost')
      AND date_diff('day', m.last_changed_at, DATE '2025-12-31') >= 180

    UNION ALL
    SELECT 9, 'Duplicate account records (normalized name match)', 'Distorts account reporting',
           'account', n.account_id, n.company_name,
           CAST(NULL AS VARCHAR), t.name, a.segment, CAST(NULL AS VARCHAR),
           CAST(NULL AS DECIMAL(12,2)), a.created_date, CAST(NULL AS DATE),
           'Normalizes to "' || n.name_key || '", shared with another account record'
    FROM normalized_accounts AS n
    JOIN accounts            AS a ON a.account_id   = n.account_id
    JOIN territories         AS t ON t.territory_id = a.territory_id
    WHERE n.name_key IN (SELECT name_key FROM normalized_accounts
                          GROUP BY name_key HAVING count(*) > 1)

    UNION ALL
    SELECT 10, 'Lead marked converted with no opportunity linked', 'Blocks source attribution',
           'lead', l.lead_id, a.company_name, CAST(NULL AS VARCHAR), t.name, a.segment,
           CAST(NULL AS VARCHAR), CAST(NULL AS DECIMAL(12,2)), l.created_date,
           CAST(NULL AS DATE),
           'Source ' || l.source || ', converted ' || CAST(l.converted_date AS VARCHAR)
             || ', nothing linked'
    FROM leads       AS l
    JOIN accounts    AS a ON a.account_id   = l.account_id
    JOIN territories AS t ON t.territory_id = a.territory_id
    WHERE l.converted_date IS NOT NULL AND l.converted_opportunity_id IS NULL

    UNION ALL
    SELECT 11, 'Stage history skips a stage', 'Distorts funnel reporting',
           'stage_history', sh.id, c.account_name, c.rep_name, c.territory, c.segment,
           c.stage, c.amount, c.created_date, c.actual_close_date,
           'Jumped ' || sh.from_stage || ' straight to ' || sh.to_stage
    FROM stage_history AS sh
    JOIN stage_rank    AS f ON f.stage = sh.from_stage
    JOIN stage_rank    AS tr ON tr.stage = sh.to_stage
    JOIN opp_context   AS c ON c.opportunity_id = sh.opportunity_id
    WHERE sh.to_stage <> 'Closed Lost' AND tr.ord - f.ord > 1

    UNION ALL
    SELECT 12, 'Opportunity with zero logged activities', 'Cleanup and process',
           'opportunity', opportunity_id, account_name, rep_name, territory, segment, stage,
           amount, created_date, actual_close_date,
           'No calls, emails, meetings or demos logged against this deal'
    FROM opp_context AS c
    WHERE NOT EXISTS (SELECT 1 FROM activities AS act
                       WHERE act.opportunity_id = c.opportunity_id)

    UNION ALL
    SELECT 13, 'Open deal owned by a departed rep', 'Blocks pipeline execution',
           'opportunity', opportunity_id, account_name, rep_name, territory, segment, stage,
           amount, created_date, actual_close_date,
           'Owner left on ' || CAST(rep_termination_date AS VARCHAR) || '; deal still open'
    FROM opp_context
    WHERE stage NOT IN ('Closed Won', 'Closed Lost') AND rep_termination_date IS NOT NULL
)

SELECT check_id,
       issue_type,
       severity,
       CASE
           WHEN severity LIKE 'Blocks%'   THEN 1
           WHEN severity LIKE 'Distorts%' THEN 2
           ELSE 3
       END                          AS fix_priority,
       record_type,
       record_id,
       account_name,
       rep_name,
       territory,
       segment,
       stage,
       amount,
       created_date,
       actual_close_date,
       detail
FROM flagged
ORDER BY fix_priority, check_id, record_type, record_id;
