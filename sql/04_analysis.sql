/* =====================================================================
   04_analysis.sql
   Business questions answered with SQL (CTEs, window functions, views).

   Key metric definitions (as used by NHS England):
   - Waiting list        = incomplete pathways (Part_2), all patients
   - % within 18 weeks   = patients waiting 0-18 weeks / patients with a
                           known clock start. Constitutional standard = 92%.
   - 52+ week waiters    = patients waiting more than 52 weeks
   - Interim ambition    = 65% within 18 weeks by March 2026 (NHS 2025/26 planning guidance)
   ===================================================================== */

USE nhs_rtt;

-- ---------------------------------------------------------------------
-- VIEWS (also used by Excel and Power BI)
-- ---------------------------------------------------------------------

-- England-level monthly trend
CREATE OR REPLACE VIEW vw_monthly_england AS
SELECT
    m.month_start,
    SUM(f.total_waiting)                                        AS total_waiting,
    SUM(f.wait_00_18_wks)                                       AS within_18_wks,
    SUM(f.total_known_start)                                    AS known_start,
    SUM(f.wait_52_65_wks + f.wait_65_78_wks + f.wait_78_plus_wks) AS over_52_wks,
    SUM(f.wait_78_plus_wks)                                     AS over_78_wks,
    ROUND(100 * SUM(f.wait_00_18_wks) / NULLIF(SUM(f.total_known_start), 0), 1)
                                                                AS pct_within_18_wks
FROM fact_waiting_list f
JOIN dim_month m ON m.period = f.period
GROUP BY m.month_start;

-- Month x specialty
CREATE OR REPLACE VIEW vw_specialty_month AS
SELECT
    m.month_start,
    d.treatment_function_code,
    d.treatment_function_name,
    SUM(f.total_waiting)                                        AS total_waiting,
    SUM(f.wait_00_18_wks)                                       AS within_18_wks,
    SUM(f.total_known_start)                                    AS known_start,
    SUM(f.wait_52_65_wks + f.wait_65_78_wks + f.wait_78_plus_wks) AS over_52_wks,
    ROUND(100 * SUM(f.wait_00_18_wks) / NULLIF(SUM(f.total_known_start), 0), 1)
                                                                AS pct_within_18_wks
FROM fact_waiting_list f
JOIN dim_month m     ON m.period = f.period
JOIN dim_specialty d ON d.treatment_function_code = f.treatment_function_code
GROUP BY m.month_start, d.treatment_function_code, d.treatment_function_name;

-- Month x provider (hospital trust)
CREATE OR REPLACE VIEW vw_provider_month AS
SELECT
    m.month_start,
    p.provider_code,
    p.provider_name,
    p.provider_parent_name,
    p.provider_type,
    SUM(f.total_waiting)                                        AS total_waiting,
    SUM(f.wait_00_18_wks)                                       AS within_18_wks,
    SUM(f.total_known_start)                                    AS known_start,
    SUM(f.wait_52_65_wks + f.wait_65_78_wks + f.wait_78_plus_wks) AS over_52_wks,
    ROUND(100 * SUM(f.wait_00_18_wks) / NULLIF(SUM(f.total_known_start), 0), 1)
                                                                AS pct_within_18_wks
FROM fact_waiting_list f
JOIN dim_month m    ON m.period = f.period
JOIN dim_provider p ON p.provider_code = f.provider_code
GROUP BY m.month_start, p.provider_code, p.provider_name, p.provider_parent_name, p.provider_type;


-- ---------------------------------------------------------------------
-- Q1. How has the waiting list changed over the year?
--     Month-on-month change using LAG().
-- ---------------------------------------------------------------------
SELECT
    month_start,
    total_waiting,
    total_waiting - LAG(total_waiting) OVER (ORDER BY month_start) AS change_vs_prev_month,
    pct_within_18_wks,
    over_52_wks
FROM vw_monthly_england
ORDER BY month_start;

-- ---------------------------------------------------------------------
-- Q2. How far is England from the 92% standard, and what would it take?
--     "Gap" = extra patients who would need to be within 18 weeks.
-- ---------------------------------------------------------------------
SELECT
    month_start,
    pct_within_18_wks,
    pct_within_18_wks - 65.0                       AS vs_interim_65_pct,
    92.0 - pct_within_18_wks                       AS gap_to_standard_pts,
    CEIL(0.92 * known_start) - within_18_wks       AS patients_short_of_standard
FROM vw_monthly_england
ORDER BY month_start;

-- ---------------------------------------------------------------------
-- Q3. Which specialties have the biggest and longest waits (latest month)?
-- ---------------------------------------------------------------------
WITH latest AS (SELECT MAX(month_start) AS m FROM vw_specialty_month)
SELECT
    s.treatment_function_name,
    s.total_waiting,
    s.pct_within_18_wks,
    s.over_52_wks,
    ROUND(100 * s.over_52_wks / NULLIF(s.total_waiting, 0), 1) AS pct_over_52_wks,
    RANK() OVER (ORDER BY s.total_waiting DESC)                 AS rank_by_size
FROM vw_specialty_month s
JOIN latest l ON s.month_start = l.m
ORDER BY s.total_waiting DESC;

-- ---------------------------------------------------------------------
-- Q4. Provider league table (latest month): best and worst performers.
--     Only trusts with 1,000+ waiting, so tiny providers don't skew it.
-- ---------------------------------------------------------------------
WITH latest AS (SELECT MAX(month_start) AS m FROM vw_provider_month),
ranked AS (
    SELECT
        p.provider_name,
        p.provider_parent_name,
        p.total_waiting,
        p.pct_within_18_wks,
        p.over_52_wks,
        RANK() OVER (ORDER BY p.pct_within_18_wks DESC) AS rank_best,
        RANK() OVER (ORDER BY p.pct_within_18_wks ASC)  AS rank_worst
    FROM vw_provider_month p
    JOIN latest l ON p.month_start = l.m
    WHERE p.total_waiting >= 1000
)
SELECT * FROM ranked
WHERE rank_best <= 10 OR rank_worst <= 10
ORDER BY pct_within_18_wks DESC;

-- ---------------------------------------------------------------------
-- Q5. Regional variation (parent organisation), latest month.
-- ---------------------------------------------------------------------
WITH latest AS (SELECT MAX(month_start) AS m FROM vw_provider_month)
SELECT
    p.provider_parent_name,
    SUM(p.total_waiting)                                                AS total_waiting,
    ROUND(100 * SUM(p.within_18_wks) / NULLIF(SUM(p.known_start), 0), 1) AS pct_within_18_wks,
    SUM(p.over_52_wks)                                                  AS over_52_wks
FROM vw_provider_month p
JOIN latest l ON p.month_start = l.m
GROUP BY p.provider_parent_name
ORDER BY pct_within_18_wks DESC;

-- ---------------------------------------------------------------------
-- Q6. Which trusts improved or declined most over the year?
--     Compares each trust's first and last month in the data.
-- ---------------------------------------------------------------------
WITH bounds AS (
    SELECT MIN(month_start) AS first_m, MAX(month_start) AS last_m
    FROM vw_provider_month
),
first_last AS (
    SELECT
        p.provider_name,
        MAX(CASE WHEN p.month_start = b.first_m THEN p.pct_within_18_wks END) AS pct_first,
        MAX(CASE WHEN p.month_start = b.last_m  THEN p.pct_within_18_wks END) AS pct_last,
        MAX(CASE WHEN p.month_start = b.last_m  THEN p.total_waiting END)     AS waiting_last
    FROM vw_provider_month p
    CROSS JOIN bounds b
    GROUP BY p.provider_name
)
SELECT
    provider_name,
    pct_first,
    pct_last,
    ROUND(pct_last - pct_first, 1) AS change_pts
FROM first_last
WHERE pct_first IS NOT NULL AND pct_last IS NOT NULL AND waiting_last >= 1000
ORDER BY change_pts DESC;   -- top = biggest improvers, bottom = biggest decliners

-- ---------------------------------------------------------------------
-- Q7. Long waits: which specialties hold the most 52+ week waiters,
--     and what share of all 52+ week waiters is that? (latest month)
-- ---------------------------------------------------------------------
WITH latest AS (SELECT MAX(month_start) AS m FROM vw_specialty_month)
SELECT
    s.treatment_function_name,
    s.over_52_wks,
    ROUND(100 * s.over_52_wks / SUM(s.over_52_wks) OVER (), 1) AS share_of_all_52wk_waits
FROM vw_specialty_month s
JOIN latest l ON s.month_start = l.m
ORDER BY s.over_52_wks DESC;

-- ---------------------------------------------------------------------
-- Q8. NHS trusts vs independent-sector providers (latest month).
--     Independent providers top the raw league table (Q4), but they hold a
--     small, less complex share of the list. Compare like with like.
-- ---------------------------------------------------------------------
WITH latest AS (SELECT MAX(month_start) AS m FROM vw_provider_month)
SELECT
    p.provider_type,
    COUNT(*)                                                            AS providers,
    SUM(p.total_waiting)                                                AS total_waiting,
    ROUND(100 * SUM(p.total_waiting) / SUM(SUM(p.total_waiting)) OVER (), 1) AS share_of_list,
    ROUND(100 * SUM(p.within_18_wks) / NULLIF(SUM(p.known_start), 0), 1) AS pct_within_18_wks,
    SUM(p.over_52_wks)                                                  AS over_52_wks
FROM vw_provider_month p
JOIN latest l ON p.month_start = l.m
GROUP BY p.provider_type;

-- NHS trusts only, 20,000+ waiting: fairer best / worst comparison
WITH latest AS (SELECT MAX(month_start) AS m FROM vw_provider_month),
nhs AS (
    SELECT p.provider_name, p.total_waiting, p.pct_within_18_wks, p.over_52_wks,
           RANK() OVER (ORDER BY p.pct_within_18_wks DESC) AS rank_best,
           RANK() OVER (ORDER BY p.pct_within_18_wks ASC)  AS rank_worst
    FROM vw_provider_month p
    JOIN latest l ON p.month_start = l.m
    WHERE p.provider_type = 'NHS trust' AND p.total_waiting >= 20000
)
SELECT * FROM nhs
WHERE rank_best <= 5 OR rank_worst <= 5
ORDER BY pct_within_18_wks DESC;
