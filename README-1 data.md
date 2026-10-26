# Emergency Department Log Data Cleaning with PostgreSQL

Cleaning a messy, simulated emergency department log (250 raw rows) into a trustworthy one-row-per-visit table, using SQL only. The focus is data quality: profiling before fixing, previewing and counting every change, and proving the result.

> **Simulated data.** The dataset is synthetic. Nothing here describes real patients or real hospital operations.

## Skills demonstrated

- Data profiling: row counts, distinct values, format checks, grain
- Deduplication with evidence (exact copies vs conflicting versions)
- Standardizing text with `TRIM`, `REPLACE`, `REGEXP_REPLACE`, `UPPER`, `NULLIF`, `CASE`
- Handling missing values (text `'NULL'` vs real `NULL`)
- Converting mixed text dates to a real `DATE` and validating the result
- Safe, traceable changes: raw table untouched, `SELECT` preview and count before each `UPDATE`, a rerunnable script, a primary key as a final guard

## Dataset

| | |
|---|---|
| Table | `emergency_log_unclean` (raw, never modified) |
| Rows | 250 |
| Columns | `log_id`, `patient_name`, `admission_date`, `acuity_score`, `assigned_room`, `insurance_provider` |
| Source | *(add the dataset link or how it was generated)* |
| Grain | One row = one admission (visit), identified by `log_id` |

## Environment

- Supabase (PostgreSQL). Version: *(paste the result of `SELECT version();`)*
- The raw CSV was imported as `emergency_log_unclean` with `admission_date` kept as **text**, so the mixed date formats were preserved. *(confirm how you imported it)*

## What "clean" means (defined before fixing)

| Column | Clean rule |
|---|---|
| `log_id` | Unique, never NULL (enforced with a primary key) |
| `patient_name` | Underscores to spaces, single spaces, trimmed, UPPER case |
| `admission_date` | Real `DATE` type |
| `acuity_score` | Whole number from 1 to 5 |
| `assigned_room` | `Room ###` format, or real `NULL` if missing |
| `insurance_provider` | One consistent spelling per insurer, or real `NULL` if missing |

## Findings and fixes

| Problem found | Evidence | Fix |
|---|---|---|
| Repeated visits | 250 rows, 122 distinct `log_id`s, and 122 distinct full rows | Every repeat was an exact copy, so `SELECT DISTINCT` was safe |
| Missing values stored as the word `'NULL'` | 34 rooms and 30 insurers in the raw rows, 0 real NULLs, 0 empty strings | `NULLIF(col, 'NULL')` makes them real NULLs |
| Room spellings | 19 distinct values for 6 real rooms (`Room`, `ROOM`, `room`, `Rm`) | Rebuilt as `'Room ' \|\| RIGHT(assigned_room, 3)` (54 rows changed) |
| Insurance casing | `axa mansard` vs `AXA Mansard`, `RELIANCE HEALTH` vs `Reliance Health` | `CASE` on `LOWER()` (3 rows changed). `INITCAP` was rejected because it turns AXA into Axa |
| Messy names | 60 with edge spaces, 117 with underscores, 59 with double spaces | `UPPER(TRIM(REGEXP_REPLACE(REPLACE(name, '_', ' '), '\s+', ' ', 'g')))`. `INITCAP` was previewed and rejected because it broke names like 2Baba and BNXN |
| Dates in 3 text formats | 93 `YYYY-MM-DD`, 15 `MM/DD/YYYY`, 14 `MM-DD-YYYY`, 0 unrecognised | Converted with `TO_DATE`. Month-first confirmed: no first part above 12, 18 second parts above 12 |
| Acuity score | Only values 1 to 5, no NULLs | No fix needed |

## Before and after

| Metric | Before (raw) | After (clean) |
|---|---|---|
| Rows | 250 | 122 |
| Distinct `log_id`s | 122 | 122 |
| Real NULL rooms | 0 | 17 |
| Real NULL insurance | 0 | 15 |
| Distinct room spellings | 19 | 6 |
| Distinct insurer spellings | 7 | 4 |

The raw counts of 19 and 7 include the text `'NULL'` as a value. The clean table has 17 and 15 real NULLs, which `COUNT(DISTINCT)` does not count.

## How to run

1. Import the raw CSV as `emergency_log_unclean` (keep `admission_date` as text).
2. Run `emergency_log_cleaning.sql` top to bottom in the Supabase SQL Editor.
3. The script drops and rebuilds `emergency_log_clean` each time, so it is safe to rerun.
4. Check the last query against the before/after table above.

## Design decisions

- **Raw table is never modified.** All fixes go on `emergency_log_clean`, so every change is traceable and reversible.
- **Missing values are real NULLs, not placeholder labels.** `COUNT(col)` skips them, and a label such as `'Not Assigned'` can be added at report time with `COALESCE`.
- **Every `UPDATE` has a `WHERE` clause.** Each was preceded by a count of affected rows.
- **Dates were converted in a new column first,** compared against the original text for each format, and only then swapped in.

## Known limitations

- `RIGHT(assigned_room, 3)` works because every room number has exactly 3 digits and no value has trailing spaces. A different room scheme would need a different rule.
- Uppercase names are a presentation choice for this project, not a claim that uppercase is more correct.
- Deduplication removed exact copies only. It was verified that every repeated ID was an exact copy, but the table cannot tell whether two *different* IDs describe the same real admission.
- `acuity_score` was only checked for range (1 to 5), not for whether the scale is 1-is-most-urgent or the reverse.

## Files

- `emergency_log_cleaning.sql`: the full script (profile, clean, validate, summary)
