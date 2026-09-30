/* =====================================================================
   03_clean_transform.sql
   Profiles the raw data, then builds a small star schema for analysis:
     dim_month, dim_provider, dim_specialty  +  fact_waiting_list
   ===================================================================== */

USE nhs_rtt;

-- ---------------------------------------------------------------------
-- STEP 1. PROFILE THE RAW DATA  (run these and look at the results)
-- ---------------------------------------------------------------------

-- 1a. Which RTT parts are in the file? We only want Part_2
--     (incomplete pathways = patients still waiting = "the waiting list").
SELECT rtt_part_type, rtt_part_description, COUNT(*) AS row_count
FROM stg_rtt
GROUP BY rtt_part_type, rtt_part_description
ORDER BY rtt_part_type;

-- 1b. Treatment functions (specialties). Note any "Total" code
--     (usually C_999): it is a subtotal and must NOT be summed with the others.
SELECT treatment_function_code, treatment_function_name, COUNT(*) AS row_count
FROM stg_rtt
GROUP BY treatment_function_code, treatment_function_name
ORDER BY treatment_function_code;

-- 1c. Data quality: do the five buckets add up to the published total?
--     NOTE (found while profiling): for Part_2 rows the NHS leaves the
--     "Total" and "unknown clock start" columns blank and only fills
--     "Total All". So we compare the buckets with total_all, for Part_2 only.
--     Expect 0 mismatches.
SELECT COUNT(*) AS bucket_mismatches
FROM stg_rtt
WHERE rtt_part_type = 'Part_2'
  AND wait_00_18_wks + wait_18_52_wks + wait_52_65_wks
    + wait_65_78_wks + wait_78_plus_wks <> total_all;

-- 1d. Missing keys
SELECT
    SUM(provider_code IS NULL OR provider_code = '')                     AS missing_provider,
    SUM(treatment_function_code IS NULL OR treatment_function_code = '') AS missing_specialty,
    SUM(period IS NULL OR period = '')                                   AS missing_period
FROM stg_rtt;


-- ---------------------------------------------------------------------
-- STEP 2. DIMENSIONS
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS fact_waiting_list;
DROP TABLE IF EXISTS dim_month;
DROP TABLE IF EXISTS dim_provider;
DROP TABLE IF EXISTS dim_specialty;

-- 'RTT-April-2025' -> 2025-04-01
CREATE TABLE dim_month AS
SELECT DISTINCT
    period,
    STR_TO_DATE(CONCAT('01-', SUBSTRING(period, 5)), '%d-%M-%Y') AS month_start
FROM stg_rtt;
ALTER TABLE dim_month ADD PRIMARY KEY (period);

CREATE TABLE dim_provider AS
SELECT
    provider_code,
    MAX(provider_name)        AS provider_name,
    MAX(provider_parent_code) AS provider_parent_code,
    MAX(provider_parent_name) AS provider_parent_name,  -- Integrated Care Board (ICB)
    -- NHS trusts vs independent-sector (private) providers treating NHS patients
    CASE WHEN MAX(provider_name) LIKE '% NHS %' THEN 'NHS trust'
         ELSE 'Independent sector / other' END AS provider_type
FROM stg_rtt
WHERE rtt_part_type = 'Part_2'
GROUP BY provider_code;
ALTER TABLE dim_provider ADD PRIMARY KEY (provider_code);

CREATE TABLE dim_specialty AS
SELECT
    treatment_function_code,
    MAX(treatment_function_name) AS treatment_function_name
FROM stg_rtt
WHERE rtt_part_type = 'Part_2'
  AND treatment_function_code <> 'C_999'   -- 'Total' is not a specialty
GROUP BY treatment_function_code;
ALTER TABLE dim_specialty ADD PRIMARY KEY (treatment_function_code);


-- ---------------------------------------------------------------------
-- STEP 3. FACT TABLE
-- Waiting list (Part_2) per month x provider x specialty.
-- Commissioner rows are summed away: we analyse where patients are treated.
-- The "Total" specialty (C_999) is excluded to avoid double counting.
-- ---------------------------------------------------------------------

CREATE TABLE fact_waiting_list AS
SELECT
    s.period,
    s.provider_code,
    s.treatment_function_code,
    SUM(s.wait_00_18_wks)      AS wait_00_18_wks,
    SUM(s.wait_18_52_wks)      AS wait_18_52_wks,
    SUM(s.wait_52_65_wks)      AS wait_52_65_wks,
    SUM(s.wait_65_78_wks)      AS wait_65_78_wks,
    SUM(s.wait_78_plus_wks)    AS wait_78_plus_wks,
    -- Known clock start = sum of the wait buckets (the "Total" column is blank for Part_2)
    SUM(s.wait_00_18_wks + s.wait_18_52_wks + s.wait_52_65_wks
        + s.wait_65_78_wks + s.wait_78_plus_wks) AS total_known_start,
    SUM(s.unknown_clock_start) AS unknown_clock_start,
    SUM(s.total_all)           AS total_waiting
FROM stg_rtt s
WHERE s.rtt_part_type = 'Part_2'
  AND s.treatment_function_code <> 'C_999'
GROUP BY s.period, s.provider_code, s.treatment_function_code;

ALTER TABLE fact_waiting_list
    ADD PRIMARY KEY (period, provider_code, treatment_function_code);


-- ---------------------------------------------------------------------
-- STEP 4. RECONCILIATION
-- The sum of specialties should equal the published C_999 total.
-- Expect 0 rows. Any rows returned = a data issue worth a note in the README.
-- ---------------------------------------------------------------------

SELECT t.period, t.provider_code, t.published_total, f.sum_of_specialties
FROM (
    SELECT period, provider_code, SUM(total_all) AS published_total
    FROM stg_rtt
    WHERE rtt_part_type = 'Part_2' AND treatment_function_code = 'C_999'
    GROUP BY period, provider_code
) t
JOIN (
    SELECT period, provider_code, SUM(total_waiting) AS sum_of_specialties
    FROM fact_waiting_list
    GROUP BY period, provider_code
) f ON f.period = t.period AND f.provider_code = t.provider_code
WHERE t.published_total <> f.sum_of_specialties;

-- Row counts after the build
SELECT 'fact_waiting_list' AS tbl, COUNT(*) AS n FROM fact_waiting_list
UNION ALL SELECT 'dim_month',     COUNT(*) FROM dim_month
UNION ALL SELECT 'dim_provider',  COUNT(*) FROM dim_provider
UNION ALL SELECT 'dim_specialty', COUNT(*) FROM dim_specialty;
