-- ============================================================
-- PROJECT 3: EMERGENCY LOG DATA CLEANING (PostgreSQL / Supabase)
-- ============================================================
-- Source table : emergency_log_unclean  (raw, never modified)
-- Output table : emergency_log_clean    (one row per visit)
-- Dataset      : simulated emergency department log, 250 raw rows.
--                Not real patients or real hospital data.
-- Safe to rerun: the script drops and rebuilds emergency_log_clean
--                from the untouched raw table every time.
-- Workflow     : profile -> define -> decide -> clean -> validate
-- Pattern      : every block is QUESTION, query, FINDING.
-- ============================================================


-- ============================================================
-- PART 1: PROFILE THE RAW TABLE (read-only, changes nothing)
-- ============================================================

-- QUESTION: What does the raw data look like?
SELECT *
FROM emergency_log_unclean
ORDER BY log_id
LIMIT 20;
-- FINDING: One row = one admission (visit), identified by log_id.
-- IDs repeat 2-4 times. Names have stray spaces, underscores and mixed
-- casing. Dates come in 3 formats (2026-05-01, 05/01/2026, 05-04-2026).
-- Rooms vary (Room 102, ROOM 105, room 102, Rm 105). Insurance casing
-- varies (AXA Mansard / axa mansard). NULL appears in room and insurance.

-- QUESTION: How many rows vs how many distinct visit IDs?
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT log_id) AS distinct_id
FROM emergency_log_unclean;
-- FINDING: 250 rows but only 122 distinct log_ids (each visit is
-- entered about twice).

-- QUESTION: Are the repeated rows exact copies or conflicting versions?
SELECT COUNT(*) AS distinct_rows
FROM (
    SELECT DISTINCT *
    FROM emergency_log_unclean
) AS unique_rows;
-- FINDING: 122 distinct full rows = 122 distinct IDs. Every repeated ID
-- is an exact copy, with no conflicting versions, so DISTINCT is safe.

-- QUESTION: In assigned_room, are the missing values real NULLs,
-- the text 'NULL', or empty strings?
SELECT
    COUNT(*) FILTER (WHERE assigned_room IS NULL) AS real_nulls,
    COUNT(*) FILTER (WHERE assigned_room = 'NULL') AS text_null,
    COUNT(*) FILTER (WHERE assigned_room = '') AS empty_strings
FROM emergency_log_unclean;
-- FINDING: 0 real NULLs, 34 rows with the text 'NULL', 0 empty strings.
-- Missing rooms are stored as the word 'NULL', so IS NULL would miss
-- them. Counts are on raw rows (including copies).

-- QUESTION: In insurance_provider, are the missing values real NULLs,
-- the text 'NULL', or empty strings?
SELECT
    COUNT(*) FILTER (WHERE insurance_provider IS NULL) AS real_nulls,
    COUNT(*) FILTER (WHERE insurance_provider = 'NULL') AS text_null,
    COUNT(*) FILTER (WHERE insurance_provider = '') AS empty_strings
FROM emergency_log_unclean;
-- FINDING: 0 real NULLs, 30 rows with the text 'NULL', 0 empty strings.
-- Same pattern as assigned_room. Counts are on raw rows (including copies).

-- QUESTION: What distinct values does assigned_room contain?
SELECT
    assigned_room,
    COUNT(*) AS total_rows
FROM emergency_log_unclean
GROUP BY assigned_room
ORDER BY assigned_room;
-- FINDING: 19 distinct spellings for only 6 real rooms (102, 105, 108,
-- 110, 201, 204) plus 34 text 'NULL'. Prefix varies: Room / ROOM /
-- room / Rm. Any GROUP BY on this column would split one room into
-- up to 4 groups.


-- ============================================================
-- PART 2: BUILD AND CLEAN (rebuilds the clean table from scratch)
-- ============================================================

-- STEP 0: start fresh so the script is safe to rerun.
-- Safe because emergency_log_unclean is never modified.
DROP TABLE IF EXISTS emergency_log_clean;

-- STEP 1: build the clean table.
-- Removes exact copies (DISTINCT) and turns the text 'NULL' into
-- real NULLs in assigned_room and insurance_provider.
CREATE TABLE emergency_log_clean AS
SELECT DISTINCT
    log_id,
    patient_name,
    admission_date,
    acuity_score,
    NULLIF(assigned_room, 'NULL') AS assigned_room,
    NULLIF(insurance_provider, 'NULL') AS insurance_provider
FROM emergency_log_unclean;

-- VALIDATE: row count and real NULLs in the clean table
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE assigned_room IS NULL) AS null_rooms,
    COUNT(*) FILTER (WHERE insurance_provider IS NULL) AS null_insurance
FROM emergency_log_clean;
-- FINDING: 122 rows (= distinct visits). 17 rooms and 15 insurance
-- values are now real NULLs. Raw counts (34, 30) included copies.

-- ------------------------------------------------------------
-- STEP 2: ROOMS -> 'Room ###'
-- ------------------------------------------------------------

-- QUESTION: Does rebuilding the room label from its last 3 digits
-- give one clean format for every spelling?
SELECT DISTINCT
    assigned_room,
    'Room ' || RIGHT(assigned_room, 3) AS room_fixed
FROM emergency_log_clean
ORDER BY assigned_room;
-- FINDING: All 18 spellings (Room / ROOM / room / Rm) map to exactly
-- 6 clean labels: Room 102, 105, 108, 110, 201, 204. NULL stays NULL.
-- RIGHT(..., 3) is safe here because every room number has 3 digits
-- and no value has trailing spaces.

-- DECIDE: how many rows will the room fix actually change?
SELECT COUNT(*) AS rows_to_change
FROM emergency_log_clean
WHERE assigned_room IS NOT NULL
  AND assigned_room <> 'Room ' || RIGHT(assigned_room, 3);
-- FINDING: 54 rows need the fix.

-- CLEAN: standardize assigned_room to 'Room ###' format.
-- Affects only rows whose current text differs from the clean label.
-- NOTE: running this twice is harmless; the second run changes 0 rows.
UPDATE emergency_log_clean
SET assigned_room = 'Room ' || RIGHT(assigned_room, 3)
WHERE assigned_room IS NOT NULL
  AND assigned_room <> 'Room ' || RIGHT(assigned_room, 3);

-- VALIDATE: distinct rooms after the fix
SELECT
    assigned_room,
    COUNT(*) AS total_rows
FROM emergency_log_clean
GROUP BY assigned_room
ORDER BY assigned_room;
-- FINDING: 18 spellings reduced to 6 clean labels (Room 102, 105, 108,
-- 110, 201, 204), plus 17 NULLs. Counts add up to 122, so no rows were
-- lost. 54 rows were updated.

-- ------------------------------------------------------------
-- STEP 3: INSURANCE CASING
-- ------------------------------------------------------------

-- QUESTION: What distinct values does insurance_provider contain?
SELECT
    insurance_provider,
    COUNT(*) AS total_rows
FROM emergency_log_clean
GROUP BY insurance_provider
ORDER BY insurance_provider;
-- FINDING: 7 lines for 4 real insurers (AXA Mansard, Leadway Assurance,
-- NEM Insurance, Reliance Health) plus 15 NULLs. Only casing varies:
-- AXA Mansard appears in 2 forms, Reliance Health in 2 forms.
-- INITCAP() was not used: it would turn AXA into Axa.

-- DECIDE: how many rows need the insurance casing fix?
SELECT COUNT(*) AS rows_to_change
FROM emergency_log_clean
WHERE (LOWER(insurance_provider) = 'axa mansard'
       AND insurance_provider <> 'AXA Mansard')
   OR (LOWER(insurance_provider) = 'reliance health'
       AND insurance_provider <> 'Reliance Health');
-- FINDING: 3 rows need the fix.

-- CLEAN: standardize insurance_provider casing.
-- Only touches the 3 rows whose spelling differs from the clean name.
-- Keep the WHERE clause: without it, every other row would become NULL.
UPDATE emergency_log_clean
SET insurance_provider = CASE
    WHEN LOWER(insurance_provider) = 'axa mansard' THEN 'AXA Mansard'
    WHEN LOWER(insurance_provider) = 'reliance health' THEN 'Reliance Health'
END
WHERE (LOWER(insurance_provider) = 'axa mansard'
       AND insurance_provider <> 'AXA Mansard')
   OR (LOWER(insurance_provider) = 'reliance health'
       AND insurance_provider <> 'Reliance Health');

-- VALIDATE: distinct insurers after the fix
SELECT
    insurance_provider,
    COUNT(*) AS total_rows
FROM emergency_log_clean
GROUP BY insurance_provider
ORDER BY insurance_provider;
-- FINDING: 7 spellings reduced to 4 clean insurers (AXA Mansard,
-- Leadway Assurance, NEM Insurance, Reliance Health) plus 15 NULLs.
-- 3 rows updated (casing only). Counts add up to 122.

-- ------------------------------------------------------------
-- STEP 4: PATIENT NAMES
-- ------------------------------------------------------------

-- QUESTION: How many names have each formatting problem?
SELECT
    COUNT(*) FILTER (WHERE patient_name <> TRIM(patient_name)) AS edge_spaces,
    COUNT(*) FILTER (WHERE POSITION('_' IN patient_name) > 0) AS has_underscore,
    COUNT(*) FILTER (WHERE POSITION('  ' IN patient_name) > 0) AS double_space
FROM emergency_log_clean;
-- FINDING: 60 names with edge spaces, 117 with underscores, 59 with
-- double spaces (overlaps with edge spaces). Casing is also mixed.
-- POSITION() is used instead of LIKE because _ is a wildcard in LIKE.

-- QUESTION: What do the cleaned names look like in each casing?
-- Order of operations: underscore -> space, collapse repeated spaces,
-- trim the ends, then change case.
SELECT DISTINCT
    patient_name,
    TRIM(REGEXP_REPLACE(REPLACE(patient_name, '_', ' '), '\s+', ' ', 'g')) AS spaces_fixed,
    UPPER(TRIM(REGEXP_REPLACE(REPLACE(patient_name, '_', ' '), '\s+', ' ', 'g'))) AS as_upper,
    INITCAP(TRIM(REGEXP_REPLACE(REPLACE(patient_name, '_', ' '), '\s+', ' ', 'g'))) AS as_title
FROM emergency_log_clean
ORDER BY patient_name
LIMIT 15;
-- FINDING: INITCAP mangles names like 2Baba and BNXN (2baba, Bnxn).
-- UPPER keeps every name intact, so UPPER is the project standard.
-- This is a presentation choice, not a claim that uppercase is more
-- correct.

-- CLEAN: standardize patient_name (underscores to spaces, collapse
-- repeated spaces, trim ends, UPPER case).
UPDATE emergency_log_clean
SET patient_name =
    UPPER(TRIM(REGEXP_REPLACE(REPLACE(patient_name, '_', ' '), '\s+', ' ', 'g')))
WHERE patient_name <>
    UPPER(TRIM(REGEXP_REPLACE(REPLACE(patient_name, '_', ' '), '\s+', ' ', 'g')));

-- VALIDATE: any names still messy?
SELECT
    COUNT(*) FILTER (WHERE patient_name <> TRIM(patient_name)) AS edge_spaces,
    COUNT(*) FILTER (WHERE POSITION('_' IN patient_name) > 0) AS has_underscore,
    COUNT(*) FILTER (WHERE POSITION('  ' IN patient_name) > 0) AS double_space,
    COUNT(*) FILTER (WHERE patient_name <> UPPER(patient_name)) AS not_upper
FROM emergency_log_clean;
-- FINDING: 4 problems checked (edge spaces, underscores, double spaces,
-- non-uppercase); all 0 after the update. Names standardized to UPPER.

-- ------------------------------------------------------------
-- STEP 5: ADMISSION DATES (text -> DATE)
-- ------------------------------------------------------------

-- QUESTION: How many rows use each date format?
SELECT
    COUNT(*) FILTER (WHERE admission_date ~ '^\d{4}-\d{2}-\d{2}$') AS fmt_yyyy_mm_dd,
    COUNT(*) FILTER (WHERE admission_date ~ '^\d{2}/\d{2}/\d{4}$') AS fmt_slash,
    COUNT(*) FILTER (WHERE admission_date ~ '^\d{2}-\d{2}-\d{4}$') AS fmt_dash,
    COUNT(*) FILTER (WHERE admission_date !~ '^\d{4}-\d{2}-\d{2}$'
                       AND admission_date !~ '^\d{2}/\d{2}/\d{4}$'
                       AND admission_date !~ '^\d{2}-\d{2}-\d{4}$') AS other_or_null
FROM emergency_log_clean;
-- FINDING: 3 formats, all rows matched. 93 are YYYY-MM-DD, 15 are
-- MM/DD/YYYY, 14 are MM-DD-YYYY. 0 unrecognised values.

-- DECIDE: is the slash/dash format month-first or day-first?
SELECT
    COUNT(*) FILTER (WHERE SUBSTRING(admission_date FROM 1 FOR 2)::int > 12) AS first_part_over_12,
    COUNT(*) FILTER (WHERE SUBSTRING(admission_date FROM 4 FOR 2)::int > 12) AS second_part_over_12
FROM emergency_log_clean
WHERE admission_date !~ '^\d{4}-\d{2}-\d{2}$';
-- FINDING: first part never exceeds 12, second part does in 18 rows.
-- Slash/dash dates are MM/DD/YYYY (month first).

-- CLEAN (a): add a real DATE column next to the original text one.
ALTER TABLE emergency_log_clean
ADD COLUMN admission_date_clean DATE;

-- CLEAN (b): convert each format with its own pattern.
-- No ELSE, so an unrecognised value would show up as NULL.
UPDATE emergency_log_clean
SET admission_date_clean = CASE
    WHEN admission_date ~ '^\d{4}-\d{2}-\d{2}$' THEN TO_DATE(admission_date, 'YYYY-MM-DD')
    WHEN admission_date ~ '^\d{2}/\d{2}/\d{4}$' THEN TO_DATE(admission_date, 'MM/DD/YYYY')
    WHEN admission_date ~ '^\d{2}-\d{2}-\d{4}$' THEN TO_DATE(admission_date, 'MM-DD-YYYY')
END
WHERE admission_date_clean IS NULL;

-- VALIDATE: did every date convert, and is the range plausible?
SELECT
    COUNT(*) FILTER (WHERE admission_date_clean IS NULL) AS null_dates,
    MIN(admission_date_clean) AS earliest,
    MAX(admission_date_clean) AS latest
FROM emergency_log_clean;
-- FINDING: 0 NULL dates after conversion. Range 2026-05-01 to
-- 2026-06-30, plausible for the dataset.

-- VALIDATE: original text vs converted date, a few rows per format
(SELECT 'YYYY-MM-DD' AS format, admission_date, admission_date_clean
 FROM emergency_log_clean
 WHERE admission_date ~ '^\d{4}-\d{2}-\d{2}$'
 LIMIT 3)
UNION ALL
(SELECT 'MM/DD/YYYY', admission_date, admission_date_clean
 FROM emergency_log_clean
 WHERE admission_date ~ '^\d{2}/\d{2}/\d{4}$'
 LIMIT 3)
UNION ALL
(SELECT 'MM-DD-YYYY', admission_date, admission_date_clean
 FROM emergency_log_clean
 WHERE admission_date ~ '^\d{2}-\d{2}-\d{4}$'
 LIMIT 3);
-- FINDING: 9 sampled rows (3 per format) converted to the correct day.
-- Month-first confirmed by slash/dash dates such as 06/18/2026.

-- CLEAN (c): replace the text date with the validated DATE column.
-- DESTRUCTIVE STEP: drops the text column from the clean table only.
-- Safe because the original text remains in emergency_log_unclean.
ALTER TABLE emergency_log_clean
DROP COLUMN admission_date;

ALTER TABLE emergency_log_clean
RENAME COLUMN admission_date_clean TO admission_date;

-- VALIDATE: data type of every column in the clean table
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'emergency_log_clean'
ORDER BY ordinal_position;
-- FINDING: admission_date is DATE. log_id and acuity_score are numeric,
-- the rest are text. admission_date moved to the last column position.

-- ------------------------------------------------------------
-- STEP 6: ACUITY SCORE (profile only, no fix needed)
-- ------------------------------------------------------------

-- QUESTION: What values does acuity_score contain?
SELECT
    acuity_score,
    COUNT(*) AS total_rows
FROM emergency_log_clean
GROUP BY acuity_score
ORDER BY acuity_score;
-- FINDING: acuity_score contains only 1-5, no NULLs, no out-of-range
-- values. Counts add up to 122. No cleaning required.

-- ------------------------------------------------------------
-- STEP 7: ENFORCE ONE ROW PER VISIT
-- ------------------------------------------------------------

-- CLEAN: add a primary key on log_id.
-- Fails if any log_id is duplicated or NULL, so it also acts as a test.
ALTER TABLE emergency_log_clean
ADD PRIMARY KEY (log_id);
-- FINDING: primary key on log_id added without error. One row per
-- visit is now enforced by the database.


-- ============================================================
-- PART 3: FINAL VALIDATION AND BEFORE/AFTER SUMMARY
-- ============================================================

-- VALIDATE (final): one summary of the clean table
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT log_id) AS distinct_ids,
    COUNT(*) FILTER (WHERE admission_date IS NULL) AS null_dates,
    COUNT(*) FILTER (WHERE assigned_room = 'NULL' OR assigned_room = '') AS bad_rooms,
    COUNT(*) FILTER (WHERE insurance_provider = 'NULL' OR insurance_provider = '') AS bad_insurance,
    COUNT(DISTINCT assigned_room) AS distinct_rooms,
    COUNT(DISTINCT insurance_provider) AS distinct_insurers
FROM emergency_log_clean;
-- FINDING: 122 rows, 122 distinct log_ids (one row per visit).
-- 0 NULL dates, 0 text-'NULL' or empty rooms/insurers.
-- 6 distinct rooms and 4 distinct insurers remain.

-- SUMMARY: before (raw) vs after (clean)
SELECT 'rows' AS metric,
       (SELECT COUNT(*) FROM emergency_log_unclean) AS before,
       (SELECT COUNT(*) FROM emergency_log_clean) AS after
UNION ALL
SELECT 'distinct log_ids',
       (SELECT COUNT(DISTINCT log_id) FROM emergency_log_unclean),
       (SELECT COUNT(DISTINCT log_id) FROM emergency_log_clean)
UNION ALL
SELECT 'real NULL rooms',
       (SELECT COUNT(*) FROM emergency_log_unclean WHERE assigned_room IS NULL),
       (SELECT COUNT(*) FROM emergency_log_clean WHERE assigned_room IS NULL)
UNION ALL
SELECT 'real NULL insurance',
       (SELECT COUNT(*) FROM emergency_log_unclean WHERE insurance_provider IS NULL),
       (SELECT COUNT(*) FROM emergency_log_clean WHERE insurance_provider IS NULL)
UNION ALL
SELECT 'distinct room spellings',
       (SELECT COUNT(DISTINCT assigned_room) FROM emergency_log_unclean),
       (SELECT COUNT(DISTINCT assigned_room) FROM emergency_log_clean)
UNION ALL
SELECT 'distinct insurer spellings',
       (SELECT COUNT(DISTINCT insurance_provider) FROM emergency_log_unclean),
       (SELECT COUNT(DISTINCT insurance_provider) FROM emergency_log_clean);
-- FINDING: 250 -> 122 rows; IDs unchanged at 122. Text 'NULL' became
-- real NULLs (17 rooms, 15 insurance). Room spellings 19 -> 6 and
-- insurer spellings 7 -> 4 (raw counts include the text 'NULL').
