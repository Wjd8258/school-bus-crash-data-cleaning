# School Bus Crash Data Cleaning — Project Report

**SQL Data Wrangling — School Bus Crash Data**

**Author:** Jiadi Wu

**Course:** DSCI 6600 Data Wrangling with SQL — Final Project 2

**Database:** MySQL 8.0 (DBeaver) | **Data source:** crash.csv (Washington State 2011 school bus crash reports)

## 1. Background and Research Goal

This project prepares data for later research on how crash injury severity relates to season, time of day, weather, road surface, and lighting conditions. The raw dataset `crash.csv` comes from Washington State school-bus-related traffic crash reports in 2011: 3,684 raw records and 10 fields. This report does not cover the association analysis itself — it records the full data cleaning (data wrangling) process, including the MySQL statements executed in DBeaver and their results, and produces a structured CSV dataset ready for analysis.

Note: the assignment's "lightning conditions" was checked against the dataset fields and corresponds to the `Lighting` field in the raw data, so this report treats it as lighting conditions throughout.

## 2. Raw Dataset Overview

The raw table `crash_raw` has 10 fields:

| Field | Type | Description | Missing / unusual |
| --- | --- | --- | --- |
| ID | Text | Crash record number | 1,434 unique values — the same ID repeats many times |
| City Name | Text | City where the crash happened | 622 / 3,684 (16.9%) missing |
| Collision Report Type | Text | Road type | No missing values, 4 categories |
| Date | Text | Crash date (M/D/YYYY) | No missing values, all in 2011 |
| Full Time | Text | Crash time (H:MM AM/PM) | No missing values |
| Injury Type | Text | Injury severity (header has a leading space) | No missing values, 4 categories |
| Weather | Text | Weather conditions | No missing values, 18 'Unknown' |
| Roadway Surface | Text | Road surface | No missing values, 19 'Unknown' |
| Lighting | Text | Lighting conditions | No missing values, 21 'Unknown' |
| Vehicle Type | Text | Vehicle type | No missing values, 3 categories |

Two key problems surfaced in the initial check:

- The same ID maps to many fully identical records (repeated imports / repeated reports) — for example, ID 2497668 appears 21 times.
- The field name `" Injury Type"` has a leading space, a structural error that needs the column name normalized at table creation.

## 3. Data Cleaning Workflow (8-Step Process)

Each step of the standard 8-step cleaning process was executed and checked; all statements ran in MySQL 8.0 connected through DBeaver. The full script is in `crash_data_cleaning.sql`; key statements and results are quoted here.

### 1) Remove irrelevant data

The research question only involves injury type, date/time, weather, road surface, and lighting. `City Name`, `Collision Report Type`, and `Vehicle Type` are unrelated and are dropped; `ID` is kept as the unique identifier.

```sql
CREATE TABLE crash_step1 AS
SELECT ID, Crash_Date, Full_Time, Injury_Type, Weather, Roadway_Surface, Lighting
FROM crash_raw;
```

Result: 3,684 rows, 7 columns kept (3 irrelevant fields dropped).

### 2) Remove duplicates

564 groups of records are fully duplicated across the kept fields.

```sql
SELECT COUNT(*) AS duplicate_row_groups
FROM (
    SELECT ID, Crash_Date, Full_Time, Injury_Type, Weather, Roadway_Surface, Lighting,
           COUNT(*) AS cnt
    FROM crash_step1
    GROUP BY ID, Crash_Date, Full_Time, Injury_Type, Weather, Roadway_Surface, Lighting
    HAVING cnt > 1
) t;
```

A `ROW_NUMBER()` window function groups by all fields and keeps only the first row of each group.

```sql
CREATE TABLE crash_step2 AS
SELECT ID, Crash_Date, Full_Time, Injury_Type, Weather, Roadway_Surface, Lighting
FROM (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY ID, Crash_Date, Full_Time, Injury_Type, Weather, Roadway_Surface, Lighting
               ORDER BY ID
           ) AS rn
    FROM crash_step1
) x
WHERE rn = 1;
```

Result: 3,684 rows → 1,434 rows; `DISTINCT(ID)` is also 1,434, confirming the duplicates are fully removed and the row count matches the number of unique crash IDs.

### 3) Fix structural errors

The leading-space field name was fixed by naming the column `Injury_Type` at table creation, and `TRIM()` is applied to all text fields to remove leading/trailing whitespace, so that stray spaces cannot break grouping or comparisons.

```sql
CREATE TABLE crash_step3 AS
SELECT
    TRIM(ID)               AS ID,
    TRIM(Crash_Date)       AS Crash_Date,
    TRIM(Full_Time)        AS Full_Time,
    TRIM(Injury_Type)      AS Injury_Type,
    TRIM(Weather)          AS Weather,
    TRIM(Roadway_Surface)  AS Roadway_Surface,
    TRIM(Lighting)         AS Lighting
FROM crash_step2;
```

Result: 1,434 rows; field names and text formats normalized, row count unchanged.

### 4) Convert data types

`Crash_Date` is converted from `M/D/YYYY` strings to `DATE`, and `Full_Time` from 12-hour strings to 24-hour `TIME`.

```sql
CREATE TABLE crash_step4 AS
SELECT
    ID,
    STR_TO_DATE(Crash_Date, '%m/%d/%Y')  AS Crash_Date,
    STR_TO_DATE(Full_Time,  '%h:%i %p')  AS Crash_Time,
    Injury_Type,
    Weather,
    Roadway_Surface,
    Lighting
FROM crash_step3;
```

Conversion is checked for failures (a failed conversion returns `NULL`):

```sql
SELECT
    SUM(CASE WHEN Crash_Date IS NULL THEN 1 ELSE 0 END) AS bad_dates,
    SUM(CASE WHEN Crash_Time IS NULL THEN 1 ELSE 0 END) AS bad_times
FROM crash_step4;
```

Result: `bad_dates = 0`, `bad_times = 0` — all 1,434 rows converted successfully, no parse failures.

### 5) Handle missing values

A NULL / empty-string check across the kept fields returns all zeros — no true missing values in the core fields.

```sql
SELECT
    SUM(Injury_Type IS NULL OR Injury_Type='') AS na_injury,
    SUM(Weather IS NULL OR Weather='')         AS na_weather,
    SUM(Roadway_Surface IS NULL OR Roadway_Surface='') AS na_surface,
    SUM(Lighting IS NULL OR Lighting='')       AS na_lighting
FROM crash_step4;
-- Result: na_injury=0, na_weather=0, na_surface=0, na_lighting=0
```

Weather, Roadway Surface, and Lighting contain 18, 19, and 21 records with the value `'Unknown'` respectively. These are an "unknown" category explicitly labeled by the data collector, not missing data, so they are kept as their own category — nothing deleted or imputed — to keep the information transparent and avoid introducing human bias. The 622 missing City Name values need no handling because that field was dropped as a whole in step 1.

### 6) Standardize / normalize data

The value lists of each categorical field were checked and confirmed uniformly named (all Title Case, no synonyms or casing conflicts), so no further standardization is needed. Dates are unified to standard `DATE` format (YYYY-MM-DD) and times to `TIME` format (HH:MM:SS).

- `Injury_Type`: 4 standard categories
- `Weather`: 4 standard categories
- `Roadway_Surface`: 3 standard categories
- `Lighting`: 5 standard categories

### 7) Handle outliers

Range and format checks were run on the three key fields — date, time, and ID: dates should all fall within 2011, times within 00:00:00–23:59:59, and IDs should match "6–7 digits" or "E + 6 digits".

```sql
SELECT MIN(Crash_Date), MAX(Crash_Date) FROM crash_step6;
-- Result: 2011-01-01 to 2011-12-31 (no out-of-year records)

SELECT ID FROM crash_step6
WHERE ID NOT REGEXP '^[0-9]{6,7}$' AND ID NOT REGEXP '^E[0-9]{6}$';
-- Result: empty set, no IDs with an abnormal format
```

Conclusion: no outliers found that need handling.

### 8) Data validation

Final integrity checks on the cleaned dataset: total rows, unique ID count, and NULL counts per field.

```sql
SELECT COUNT(*) FROM crash_step6;                 -- 1434
SELECT COUNT(DISTINCT ID) FROM crash_step6;      -- 1434 (row count matches unique ID count)
SELECT
    SUM(Crash_Date IS NULL) + SUM(Crash_Time IS NULL) +
    SUM(Injury_Type IS NULL) + SUM(Weather IS NULL) +
    SUM(Roadway_Surface IS NULL) + SUM(Lighting IS NULL) AS total_nulls
FROM crash_step6;   -- Result: total_nulls = 0, validation passed
```

## 4. Step 2: Create Derived Columns (Season / Time Period)

Season is derived from the month of `Crash_Date` (Northern Hemisphere convention): December/January/February = Winter, March/April/May = Spring, June/July/August = Summer, September/October/November = Autumn. Time period is derived from the hour of `Crash_Time`: 06:00–19:59 = Daytime, 20:00–05:59 = Nighttime. Together the two periods cover all 24 hours with no overlap and no gap.

```sql
CREATE TABLE crash_step7 AS
SELECT
    ID,
    Crash_Date,
    Crash_Time,
    MONTH(Crash_Date) AS Crash_Month,
    CASE
        WHEN MONTH(Crash_Date) IN (12, 1, 2) THEN 'Winter'
        WHEN MONTH(Crash_Date) IN (3, 4, 5)  THEN 'Spring'
        WHEN MONTH(Crash_Date) IN (6, 7, 8)  THEN 'Summer'
        ELSE 'Autumn'
    END AS Season,
    CASE
        WHEN HOUR(Crash_Time) BETWEEN 6 AND 19 THEN 'Daytime'
        ELSE 'Nighttime'
    END AS Time_Period,
    Injury_Type,
    Weather,
    Roadway_Surface,
    Lighting
FROM crash_step6;
```

Distributions in the final dataset (counted from the cleaned CSV):

| Season | Count |
| --- | --- |
| Autumn | 404 |
| Spring | 391 |
| Winter | 331 |
| Summer | 308 |

| Time period | Count |
| --- | --- |
| Daytime | 1,233 |
| Nighttime | 201 |

## 5. Step 3: Merge Some Categories

**Injury Type:** `'Possible Injury'` and `'Evident Injury'` are merged into `'Minor Injury'`, keeping `'No Injury'` and `'Serious Injury'`. **Lighting:** `'Dark-Street Lights Off'` and `'Dark-No Street Lights'` are merged into `'Dark'`, keeping `'Daylight'`, `'Dark-Street Lights On'`, and `'Unknown'`.

```sql
CREATE TABLE crash_final AS
SELECT
    ID,
    Crash_Date,
    Crash_Time,
    Crash_Month,
    Season,
    Time_Period,
    CASE
        WHEN Injury_Type IN ('Possible Injury', 'Evident Injury') THEN 'Minor Injury'
        ELSE Injury_Type
    END AS Injury_Type_Grouped,
    Weather,
    Roadway_Surface,
    CASE
        WHEN Lighting IN ('Dark-Street Lights Off', 'Dark-No Street Lights') THEN 'Dark'
        ELSE Lighting
    END AS Lighting_Grouped
FROM crash_step7;
```

Merged distributions (counted from the cleaned CSV):

| Injury severity (merged) | Count |
| --- | --- |
| No Injury | 1,037 |
| Minor Injury | 379 |
| Serious Injury | 18 |

| Lighting (merged) | Count |
| --- | --- |
| Daylight | 1,117 |
| Dark-Street Lights On | 263 |
| Dark | 33 |
| Unknown | 21 |

## 6. Final Dataset

The final cleaned table `crash_final` has 1,434 rows and 10 columns, exported from DBeaver (Export Data → CSV) as `cleaned_school_bus_crash_data.csv`.

| Field | Description |
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

Summary: from 3,684 raw records, deduplication and field reduction produced 1,434 unique valid records with 10 fields, no missing values, correct field types, and standardized category names — ready for cross-analysis of injury severity by season, time period, weather, road surface, and lighting.

## 7. Deliverables

- `crash_data_cleaning.sql` — the fully commented MySQL cleaning script (runnable directly in DBeaver)
- `cleaned_school_bus_crash_data.csv` — the cleaned final dataset (1,434 rows × 10 columns)
- This report — the data wrangling methods and the results of each step
