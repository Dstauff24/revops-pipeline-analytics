-- ============================================================
-- 11. Quota Attainment Distribution
--
-- QUESTION
--   Not what the team averaged. What the distribution looks like:
--   how many reps cleared their number, how many were nowhere
--   near it, and how much of the year's revenue came from the top
--   of the range.
--
-- DECISION IT INFORMS
--   Whether the problem is the plan or the people, and how much
--   concentration risk the number carries. A team averaging 95
--   percent where the median rep is at 70 and two reps are at 200
--   does not have a healthy team, it has two producers and a
--   staffing decision to make. That team also has a real risk
--   problem: if one of the two leaves, the plan misses, and the
--   ramp curve in query 02 says the replacement will not
--   contribute for three quarters.
--
-- CAVEAT
--   Quota is prorated by days employed in the year, so a rep who
--   started in May is measured against roughly two thirds of a
--   number. Without that, every new hire looks like a failure and
--   every departure looks like a catastrophe. Reps with under 90
--   days in the year are excluded entirely: their attainment is
--   arithmetic noise, not performance. Revenue is credited to the
--   rep who owned the deal at close, which means inherited deals
--   from departed reps flatter whoever caught them. Deals with no
--   amount contribute nothing, so attainment is understated by
--   roughly the share of records query 12 flags as missing an
--   amount.
-- ============================================================

WITH year_bounds AS (
    SELECT DATE '2025-01-01' AS year_start,
           DATE '2025-12-31' AS year_end
),

rep_exposure AS (
    SELECT r.rep_id,
           r.name,
           r.segment_focus,
           r.hire_date,
           r.termination_date,
           r.quota_annual,
           greatest(r.hire_date, y.year_start)                            AS active_from,
           least(coalesce(r.termination_date, y.year_end), y.year_end)    AS active_to,
           date_diff('day',
                     greatest(r.hire_date, y.year_start),
                     least(coalesce(r.termination_date, y.year_end), y.year_end)) + 1
                                                                          AS days_in_year
    FROM reps AS r
    CROSS JOIN year_bounds AS y
    WHERE r.hire_date <= y.year_end
      AND (r.termination_date IS NULL OR r.termination_date >= y.year_start)
),

attainment AS (
    SELECT e.rep_id,
           e.name,
           e.segment_focus,
           e.days_in_year,
           e.termination_date IS NOT NULL                    AS departed,
           round(e.quota_annual * e.days_in_year / 365.0)     AS prorated_quota,
           round(coalesce(sum(o.amount), 0))                  AS won_revenue,
           round(100.0 * coalesce(sum(o.amount), 0)
                 / nullif(e.quota_annual * e.days_in_year / 365.0, 0), 1) AS attainment_pct
    FROM rep_exposure AS e
    LEFT JOIN opportunities AS o
           ON o.rep_id = e.rep_id
          AND o.stage = 'Closed Won'
          AND o.actual_close_date BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'
          AND o.actual_close_date >= o.created_date
    WHERE e.days_in_year >= 90       -- under a quarter on the job is not a data point
    GROUP BY e.rep_id, e.name, e.segment_focus, e.days_in_year,
             e.termination_date, e.quota_annual
),

banded AS (
    SELECT *,
           CASE
               WHEN attainment_pct >= 120 THEN 'a. 120%+'
               WHEN attainment_pct >= 100 THEN 'b. 100 to 119%'
               WHEN attainment_pct >=  80 THEN 'c. 80 to 99%'
               WHEN attainment_pct >=  50 THEN 'd. 50 to 79%'
               WHEN attainment_pct >=  25 THEN 'e. 25 to 49%'
               ELSE                            'f. under 25%'
           END AS attainment_band
    FROM attainment
),

-- Every band is listed whether or not anyone landed in it. An
-- empty band is a finding: it means the team is barbelled rather
-- than clustered around the number.
all_bands(attainment_band) AS (
    VALUES ('a. 120%+'), ('b. 100 to 119%'), ('c. 80 to 99%'),
           ('d. 50 to 79%'), ('e. 25 to 49%'), ('f. under 25%')
),

-- Team level statistics, computed once over reps rather than
-- over bands. Averaging the band averages would weight a band
-- holding one rep the same as a band holding nine.
team AS (
    SELECT count(*)                                                     AS team_reps,
           sum(won_revenue)                                             AS team_revenue,
           round(avg(attainment_pct), 1)                                AS team_mean_attainment,
           round(percentile_cont(0.50) WITHIN GROUP (ORDER BY attainment_pct), 1)
                                                                        AS team_median_attainment,
           round(100.0 * count(*) FILTER (WHERE attainment_pct >= 100)
                 / nullif(count(*), 0), 1)                              AS pct_of_reps_at_quota
    FROM attainment
)

SELECT ab.attainment_band,
       count(b.rep_id)                                                  AS reps,
       round(100.0 * count(b.rep_id) / nullif(t.team_reps, 0), 1)       AS pct_of_reps,
       count(b.rep_id) FILTER (WHERE b.departed)                        AS of_which_departed,
       round(coalesce(sum(b.won_revenue), 0))                           AS band_revenue,
       -- What share of the year's revenue this band produced.
       -- Compare it to pct_of_reps: the gap is the concentration.
       round(100.0 * coalesce(sum(b.won_revenue), 0)
             / nullif(t.team_revenue, 0), 1)                            AS pct_of_revenue,
       round(min(b.attainment_pct), 1)                                  AS min_attainment,
       round(max(b.attainment_pct), 1)                                  AS max_attainment,
       -- Repeated on every row so the distribution can be read
       -- against the headline number somebody will quote from a
       -- board deck. The mean and the median are not close.
       t.team_mean_attainment,
       t.team_median_attainment,
       t.pct_of_reps_at_quota
FROM all_bands       AS ab
CROSS JOIN team      AS t
LEFT JOIN banded     AS b ON b.attainment_band = ab.attainment_band
GROUP BY ab.attainment_band, t.team_reps, t.team_revenue,
         t.team_mean_attainment, t.team_median_attainment, t.pct_of_reps_at_quota
ORDER BY ab.attainment_band;
