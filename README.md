# School Bus Crash Data Cleaning

**Author:** Jiadi Wu

**Course:** DSCI 6600 Data Wrangling with SQL, M.S. in Artificial Intelligence, Hawaii Pacific University (2026) — Final Project 2

**Tools:** MySQL 8.0+, DBeaver

## Overview

This project cleans a dataset of school-bus-related traffic crash reports from Washington State (2011) and prepares it for later research on how injury severity relates to season, time of day, weather, road surface, and lighting conditions. The raw file `crash.csv` has 3,684 records and 10 columns; the cleaned output has **1,434 unique records and 10 columns, with zero missing values**.

Note: the assignment's "lightning conditions" refers to the dataset's `Lighting` field, so this project treats it as lighting conditions throughout.

## The data

| Field | Description | Missing / unusual |
| --- | --- | --- |
| ID | Crash record number | 1,434 unique values — the same ID repeats many times in the raw file |
| City Name | City where the crash happened | 622 / 3,684 (16.9%) missing |
| Collision Report Type | Road type | No missing values, 4 categories |
| Date | Crash date (M/D/YYYY) | No missing values, all in 2011 |
| Full Time | Crash time (H:MM AM/PM) | No missing values |
| Injury Type | Injury severity (header has a leading space) | No missing values, 4 categories |
| Weather | Weather conditions | No missing values, 18 'Unknown' |
| Roadway Surface | Road surface | No missing values, 19 'Unknown' |
| Lighting | Lighting conditions | No missing values, 21 'Unknown' |
| Vehicle Type | Vehicle type | No missing values, 3 categories |

The raw file `crash.csv` is not included in this repo; the cleaning script and the cleaned output are.

## Pipeline

The script [`crash_data_cleaning.sql`](crash_data_cleaning.sql) runs in stages:

1. **Drop irrelevant data:** `City Name`, `Collision Report Type`, and `Vehicle Type` are unrelated to the research question and are dropped; `ID` is kept as the unique identifier. 3,684 rows × 7 columns remain.
2. **Remove duplicates:** 564 groups of records are fully duplicated across the kept fields (e.g. ID 2497668 appears 21 times). A `ROW_NUMBER()` window function keeps the first row of each group. **3,684 → 1,434 rows**, and `COUNT(DISTINCT ID)` is also 1,434, confirming the duplicates are gone.
3. **Fix structural errors:** the leading space in the `" Injury Type"` header is fixed by naming the column `Injury_Type` at table creation, and `TRIM()` is applied to all text fields.
4. **Convert types:** `Crash_Date` goes from `M/D/YYYY` strings to `DATE`, and `Full_Time` from 12-hour strings to 24-hour `TIME`. Validation: `bad_dates = 0`, `bad_times = 0` — all 1,434 rows converted successfully.
5. **Handle missing values:** no NULLs or empty strings in any kept field. The 18 / 19 / 21 `'Unknown'` values in Weather / Roadway Surface / Lighting are a category the data collector explicitly labeled, not missing data, so they are kept as their own category — nothing deleted or imputed. The 622 missing City Name values need no handling because that field was dropped in step 1.
6. **Standardize:** category names are already uniform Title Case with no synonyms or casing conflicts, so no further standardization is needed. Dates are `YYYY-MM-DD` and times are `HH:MM:SS`.
7. **Handle outliers:** dates all fall within 2011-01-01 to 2011-12-31, times within 00:00:00–23:59:59, and every ID matches `6–7 digits` or `E + 6 digits` — no outliers found, nothing to fix.
8. **Validate:** 1,434 rows, 1,434 distinct IDs, `total_nulls = 0`.

**Derived columns:** `Season` from the month (Winter: Dec/Jan/Feb, Spring: Mar–May, Summer: Jun–Aug, Autumn: Sep–Nov) and `Time_Period` from the hour (Daytime 06:00–19:59, Nighttime 20:00–05:59 — together they cover all 24 hours with no overlap or gap).

**Category merges:** Injury Type — `'Possible Injury'` + `'Evident Injury'` → `'Minor Injury'` (keeping `'No Injury'` and `'Serious Injury'`); Lighting — `'Dark-Street Lights Off'` + `'Dark-No Street Lights'` → `'Dark'` (keeping `'Daylight'`, `'Dark-Street Lights On'`, `'Unknown'`).

## Final dataset

[`outputs/cleaned_school_bus_crash_data.csv`](outputs/cleaned_school_bus_crash_data.csv) — 1,434 rows × 10 columns:

| Column | Description |
| --- | --- |
| ID | Unique crash record number |
| Crash_Date | Crash date (YYYY-MM-DD) |
| Crash_Time | Crash time (HH:MM:SS, 24-hour) |
| Crash_Month | Month of the crash (1–12) |
| Season | Spring / Summer / Autumn / Winter |
| Time_Period | Daytime / Nighttime |
| Injury_Type_Grouped | No Injury / Minor Injury / Serious Injury |
| Weather | Clear or Partly Cloudy / Overcast / Raining / Unknown |
| Roadway_Surface | Dry / Wet / Unknown |
| Lighting_Grouped | Daylight / Dark-Street Lights On / Dark / Unknown |

Distributions in the final dataset (counted from the CSV):

| Breakdown | Counts |
| --- | --- |
| Season | Autumn 404, Spring 391, Winter 331, Summer 308 |
| Time period | Daytime 1,233, Nighttime 201 |
| Injury severity | No Injury 1,037, Minor Injury 379, Serious Injury 18 |
| Weather | Clear or Partly Cloudy 933, Raining 248, Overcast 235, Unknown 18 |
| Road surface | Dry 1,043, Wet 372, Unknown 19 |
| Lighting | Daylight 1,117, Dark-Street Lights On 263, Dark 33, Unknown 21 |

## How to run

1. Create the database and import `crash.csv` into `crash_raw` (DBeaver Import Data wizard, or the `LOAD DATA LOCAL INFILE` statement in the script — update the file path to your own download location).
2. Run [`crash_data_cleaning.sql`](crash_data_cleaning.sql) in MySQL 8.0 / DBeaver; it builds the step tables (`crash_step1` … `crash_step7`) and the final `crash_final` table, with a check query after each step.
3. Export `crash_final` from DBeaver (right-click the table → Export Data → CSV) to reproduce `cleaned_school_bus_crash_data.csv`.

## Repo layout

```
├── README.md                              # this file
├── REPORT.md                              # full project report (English)
├── crash_data_cleaning.sql                # full pipeline: 8-step cleaning → derived columns → merges
└── outputs/
    └── cleaned_school_bus_crash_data.csv  # final dataset: 1,434 rows × 10 columns
```
