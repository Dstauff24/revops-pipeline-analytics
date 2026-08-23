-- ============================================================
-- BI EXTRACT: quota attainment at rep grain
-- Feeds dashboard 02 (Rep Performance and Ramp)
--
-- WHY THIS IS NOT queries/11
--   Query 11 answers "what does the distribution look like" and
--   returns six banded rows to do it. A histogram needs the rows
--   the bands were built from, and a sortable rep table needs one
--   row per rep. Handing a dashboard the banded output would let
--   it draw the bands and nothing else.
--
--   Same population rules as query 11: quota prorated by days
--   employed in the year, reps with under 90 days excluded, wins
--   read from stage rather than the is_won flag.
--
-- ALL DATA IS SYNTHETIC. See data/README.md.
-- ============================================================

WITH rep_exposure AS (
    SELECT r.rep_id,
           r.name                                                       AS rep_name,
           r.segment_focus,
           r.hire_date,
           r.termination_date,
           r.quota_annual,
           t.name                                                       AS territory,
           t.region,
           m.name                                                       AS manager_name,
           date_diff('day',
                     greatest(r.hire_date, DATE '2025-01-01'),
                     least(coalesce(r.termination_date, DATE '2025-12-31'),
                           DATE '2025-12-31')) + 1                      AS days_in_year,
           date_diff('month', r.hire_date, DATE '2025-12-31')           AS tenure_months_at_year_end,
           'Q' || quarter(r.hire_date)                                  AS hire_quarter,
           year(r.hire_date)                                            AS hire_year
    FROM reps             AS r
    JOIN territories      AS t ON t.territory_id = r.territory_id
    LEFT JOIN reps        AS m ON m.rep_id       = r.manager_id
    WHERE r.hire_date <= DATE '2025-12-31'
      AND (r.termination_date IS NULL OR r.termination_date >= DATE '2025-01-01')
)

SELECT e.rep_id,
       e.rep_name,
       e.manager_name,
       e.territory,
       e.region,
       e.segment_focus,
       e.hire_date,
       e.hire_year,
       e.hire_quarter,
       e.termination_date,
       e.termination_date IS NOT NULL                                   AS departed,
       e.tenure_months_at_year_end,
       CASE
           WHEN e.tenure_months_at_year_end <  6 THEN 'a. under 6 months'
           WHEN e.tenure_months_at_year_end < 12 THEN 'b. 6 to 11 months'
           WHEN e.tenure_months_at_year_end < 24 THEN 'c. 1 to 2 years'
           ELSE                                       'd. over 2 years'
       END                                                              AS tenure_band,
       e.days_in_year,
       round(e.quota_annual)                                            AS quota_annual,
       round(e.quota_annual * e.days_in_year / 365.0)                   AS prorated_quota,
       count(o.opportunity_id)                                          AS deals_won,
       round(coalesce(sum(o.amount), 0))                                AS won_revenue,
       round(100.0 * coalesce(sum(o.amount), 0)
             / nullif(e.quota_annual * e.days_in_year / 365.0, 0), 1)   AS attainment_pct,
       -- Banding is carried here as well as computed in query 11,
       -- so the histogram and the analysis cannot drift apart.
       CASE
           WHEN 100.0 * coalesce(sum(o.amount), 0)
                / nullif(e.quota_annual * e.days_in_year / 365.0, 0) >= 120 THEN 'a. 120%+'
           WHEN 100.0 * coalesce(sum(o.amount), 0)
                / nullif(e.quota_annual * e.days_in_year / 365.0, 0) >= 100 THEN 'b. 100 to 119%'
           WHEN 100.0 * coalesce(sum(o.amount), 0)
                / nullif(e.quota_annual * e.days_in_year / 365.0, 0) >=  80 THEN 'c. 80 to 99%'
           WHEN 100.0 * coalesce(sum(o.amount), 0)
                / nullif(e.quota_annual * e.days_in_year / 365.0, 0) >=  50 THEN 'd. 50 to 79%'
           WHEN 100.0 * coalesce(sum(o.amount), 0)
                / nullif(e.quota_annual * e.days_in_year / 365.0, 0) >=  25 THEN 'e. 25 to 49%'
           ELSE                                                              'f. under 25%'
       END                                                              AS attainment_band
FROM rep_exposure AS e
LEFT JOIN opportunities AS o
       ON o.rep_id = e.rep_id
      AND o.stage  = 'Closed Won'
      AND o.actual_close_date BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'
      AND o.actual_close_date >= o.created_date
WHERE e.days_in_year >= 90
GROUP BY e.rep_id, e.rep_name, e.manager_name, e.territory, e.region,
         e.segment_focus, e.hire_date, e.hire_year, e.hire_quarter,
         e.termination_date, e.tenure_months_at_year_end, e.days_in_year,
         e.quota_annual
ORDER BY e.rep_id;
