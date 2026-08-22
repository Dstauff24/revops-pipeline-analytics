-- ============================================================
-- 12. Data Hygiene Audit
--
-- QUESTION
--   Before anybody trusts a number out of this CRM: what is
--   broken in it, how much of it is broken, and how much revenue
--   is sitting behind the broken records?
--
-- DECISION IT INFORMS
--   What to fix first, and which reports to stop publishing until
--   it is fixed. Every other query in this repo makes a silent
--   choice about these records, and this is the query that makes
--   those choices visible. It is also the operational one: each
--   row here becomes either a validation rule, a required field,
--   a workflow, or a list somebody works through on a Friday.
--   The ordering is severity first and dollars second, not record
--   count, because record count is the least useful of the three.
--   Twelve opportunities carrying a negative amount is a smaller
--   list than 167 missing a loss reason and a much worse problem:
--   one of them silently subtracts from revenue and the other
--   costs you a slide in the quarterly review.
--
-- CAVEAT
--   These are checks, not verdicts. Some are unambiguous defects:
--   a close date before a create date is always wrong. Others are
--   judgment: a deal open 180 days is stalled in most businesses
--   and normal in some, and the duplicate account check uses name
--   normalization, which will always both miss real duplicates
--   that were spelled differently and flag two genuinely separate
--   subsidiaries that share a name. Everything here needs a human
--   pass before anything gets merged or deleted. Nothing in this
--   query modifies data, and that is on purpose.
-- ============================================================

WITH totals AS (
    SELECT (SELECT count(*) FROM opportunities) AS total_opportunities,
           (SELECT count(*) FROM leads)         AS total_leads,
           (SELECT count(*) FROM accounts)      AS total_accounts,
           (SELECT count(*) FROM stage_history) AS total_stage_rows
),

stage_rank(stage, ord) AS (
    VALUES ('Prospecting', 1), ('Discovery', 2), ('Proposal', 3),
           ('Negotiation', 4), ('Closed Won', 5), ('Closed Lost', 5)
),

-- Last recorded movement on each deal, used by the stalled check.
last_movement AS (
    SELECT o.opportunity_id,
           o.stage,
           o.amount,
           coalesce(max(sh.changed_at), o.created_date) AS last_changed_at
    FROM opportunities   AS o
    LEFT JOIN stage_history AS sh ON sh.opportunity_id = o.opportunity_id
    GROUP BY o.opportunity_id, o.stage, o.amount, o.created_date
),

-- Account names reduced to a comparison key: case folded,
-- punctuation stripped, legal suffix removed. This is what turns
-- "Westerly Networks LLC" and "Westerly Networks L.L.C." into the
-- same customer.
normalized_accounts AS (
    SELECT account_id,
           company_name,
           trim(regexp_replace(
               regexp_replace(lower(company_name), '[^a-z0-9]+', ' ', 'g'),
               '\s+(inc|llc|l l c|corp|corporation|co|company|group|grp|partners|holdings)\s*$',
               '')) AS name_key
    FROM accounts
),

findings AS (

    -- 1. No amount. Every revenue number in the repo is short by
    --    whatever these were worth.
    SELECT 1                                        AS check_id,
           'Opportunity has no amount'              AS issue_type,
           'Distorts revenue reporting'             AS severity,
           'opportunities'                          AS table_affected,
           count(*)                                 AS records,
           NULL                                     AS dollars_affected,
           'Forecast and attainment understate by the value of these deals'
                                                    AS what_it_breaks
    FROM opportunities
    WHERE amount IS NULL

    UNION ALL

    -- 2. Amounts that cannot be real.
    SELECT 2, 'Opportunity amount is zero or negative', 'Distorts revenue reporting',
           'opportunities', count(*), round(sum(amount)),
           'Negative values net against real revenue in every sum'
    FROM opportunities
    WHERE amount IS NOT NULL AND amount <= 0

    UNION ALL

    -- 3. Time running backwards. Always a defect, usually an
    --    import or a backdated renewal.
    SELECT 3, 'Close date precedes create date', 'Blocks cycle time reporting',
           'opportunities', count(*), round(sum(amount)),
           'Produces negative sales cycles that poison any average'
    FROM opportunities
    WHERE actual_close_date IS NOT NULL
      AND actual_close_date < created_date

    UNION ALL

    -- 4. Closed on the board, no date on the record.
    SELECT 4, 'Closed deal has no close date', 'Blocks period reporting',
           'opportunities', count(*), round(sum(amount)),
           'Deal is invisible to any report filtered by close month or quarter'
    FROM opportunities
    WHERE stage IN ('Closed Won', 'Closed Lost')
      AND actual_close_date IS NULL

    UNION ALL

    -- 5. The mirror image: open deal carrying a close date.
    SELECT 5, 'Open deal has a close date', 'Distorts pipeline reporting',
           'opportunities', count(*), round(sum(amount)),
           'Deal counts as open pipeline and as closed revenue depending on the filter'
    FROM opportunities
    WHERE stage NOT IN ('Closed Won', 'Closed Lost')
      AND actual_close_date IS NOT NULL

    UNION ALL

    -- 6. Lost with no reason. Not a reporting break, a learning
    --    break: this is the field that tells product why.
    SELECT 6, 'Closed Lost with no loss reason', 'Cleanup and process',
           'opportunities', count(*), round(sum(amount)),
           'Win loss analysis silently drops these, biasing whatever reasons remain'
    FROM opportunities
    WHERE stage = 'Closed Lost'
      AND (loss_reason IS NULL OR trim(loss_reason) = '')

    UNION ALL

    -- 7. The flag and the stage disagree. Two reports, two
    --    answers, and an argument in a pipeline meeting.
    SELECT 7, 'is_won flag disagrees with stage', 'Blocks revenue reporting',
           'opportunities', count(*), round(sum(amount)),
           'Win rate differs depending on which column the report was written against'
    FROM opportunities
    WHERE (stage = 'Closed Won'  AND coalesce(is_won, FALSE) = FALSE)
       OR (stage = 'Closed Lost' AND coalesce(is_won, FALSE) = TRUE)
       OR (stage NOT IN ('Closed Won', 'Closed Lost') AND is_won IS NOT NULL)

    UNION ALL

    -- 8. Nobody has touched it in six months and nobody has
    --    closed it out. This is the pile that makes coverage
    --    ratios lie.
    SELECT 8, 'Open deal with no stage movement in 180 days', 'Distorts pipeline reporting',
           'opportunities', count(*), round(sum(amount)),
           'Inflates open pipeline and every coverage ratio built on it'
    FROM last_movement
    WHERE stage NOT IN ('Closed Won', 'Closed Lost')
      AND date_diff('day', last_changed_at, DATE '2025-12-31') >= 180

    UNION ALL

    -- 9. Duplicate customers. One company, two account records,
    --    two halves of a relationship nobody can see whole.
    SELECT 9, 'Duplicate account records (normalized name match)', 'Distorts account reporting',
           'accounts',
           (SELECT count(*) FROM normalized_accounts
             WHERE name_key IN (SELECT name_key FROM normalized_accounts
                                 GROUP BY name_key HAVING count(*) > 1)),
           NULL,
           'Splits one customer across two records, understating account value and expansion'

    UNION ALL

    -- 10. Lead says it converted. Nothing is linked to it.
    SELECT 10, 'Lead marked converted with no opportunity linked', 'Blocks source attribution',
           'leads', count(*), NULL,
           'Marketing source attribution loses these deals entirely'
    FROM leads
    WHERE converted_date IS NOT NULL
      AND converted_opportunity_id IS NULL

    UNION ALL

    -- 11. Stage history that jumps a stage. Closed Lost is
    --     excluded because a deal can legitimately die from
    --     anywhere.
    SELECT 11, 'Stage history skips a stage', 'Distorts funnel reporting',
           'stage_history', count(*), NULL,
           'Funnel conversion undercounts the skipped stage and overstates time in the prior one'
    FROM stage_history AS sh
    JOIN stage_rank    AS f ON f.stage = sh.from_stage
    JOIN stage_rank    AS t ON t.stage = sh.to_stage
    WHERE sh.to_stage <> 'Closed Lost'
      AND t.ord - f.ord > 1

    UNION ALL

    -- 12. A deal with no logged work against it. Either it was
    --     never worked or the rep does not log, and both are
    --     worth knowing before anyone reads query 09.
    SELECT 12, 'Opportunity with zero logged activities', 'Cleanup and process',
           'opportunities', count(*), round(sum(o.amount)),
           'Activity based analysis silently excludes these deals'
    FROM opportunities AS o
    WHERE NOT EXISTS (SELECT 1 FROM activities AS a
                       WHERE a.opportunity_id = o.opportunity_id)

    UNION ALL

    -- 13. Open deals still sitting under a rep who does not work
    --     here. Nobody is calling these customers back.
    SELECT 13, 'Open deal owned by a departed rep', 'Blocks pipeline execution',
           'opportunities', count(*), round(sum(o.amount)),
           'Live pipeline with no owner: nobody is working these and they still count in coverage'
    FROM opportunities AS o
    JOIN reps          AS r ON r.rep_id = o.rep_id
    WHERE o.stage NOT IN ('Closed Won', 'Closed Lost')
      AND r.termination_date IS NOT NULL
)

SELECT f.check_id,
       f.issue_type,
       f.severity,
       CASE
           WHEN f.severity LIKE 'Blocks%'   THEN 1
           WHEN f.severity LIKE 'Distorts%' THEN 2
           ELSE 3
       END AS fix_priority,
       f.table_affected,
       f.records,
       round(100.0 * f.records
             / nullif(CASE f.table_affected
                          WHEN 'opportunities' THEN t.total_opportunities
                          WHEN 'leads'         THEN t.total_leads
                          WHEN 'accounts'      THEN t.total_accounts
                          WHEN 'stage_history' THEN t.total_stage_rows
                      END, 0), 2)                        AS pct_of_table,
       f.dollars_affected,
       f.what_it_breaks
FROM findings AS f
CROSS JOIN totals AS t
WHERE f.records > 0        -- a clean check does not need a row
ORDER BY fix_priority,
         abs(coalesce(f.dollars_affected, 0)) DESC,
         f.records DESC;
