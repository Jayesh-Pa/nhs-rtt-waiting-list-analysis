/* =====================================================================
   01_create_schema.sql
   Creates the nhs_rtt database and the staging table for the raw extracts.
   Target: MySQL 8.0+
   ===================================================================== */

CREATE DATABASE IF NOT EXISTS nhs_rtt
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE nhs_rtt;

DROP TABLE IF EXISTS stg_rtt;

-- One row per Provider x Commissioner x RTT part x Treatment function x Month,
-- exactly as published, with the 105 weekly bands pre-summed into 5 buckets.
CREATE TABLE stg_rtt (
    id                        INT AUTO_INCREMENT PRIMARY KEY,
    period                    VARCHAR(30),   -- e.g. 'RTT-April-2025'
    provider_parent_code      VARCHAR(10),
    provider_parent_name      VARCHAR(200),
    provider_code             VARCHAR(10),
    provider_name             VARCHAR(200),
    commissioner_parent_code  VARCHAR(10),
    commissioner_parent_name  VARCHAR(200),
    commissioner_code         VARCHAR(10),
    commissioner_name         VARCHAR(200),
    rtt_part_type             VARCHAR(10),   -- Part_1A, Part_1B, Part_2, Part_2A, Part_3
    rtt_part_description      VARCHAR(200),
    treatment_function_code   VARCHAR(10),   -- e.g. C_110 (Trauma & Orthopaedics)
    treatment_function_name   VARCHAR(100),
    wait_00_18_wks            INT,
    wait_18_52_wks            INT,
    wait_52_65_wks            INT,
    wait_65_78_wks            INT,
    wait_78_plus_wks          INT,
    total_known_start         INT,           -- patients with a known clock start
    unknown_clock_start       INT,
    total_all                 INT,
    source_file               VARCHAR(50),
    loaded_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
