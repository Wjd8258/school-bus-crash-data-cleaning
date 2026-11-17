-- ============================================================================
-- Jiadi Wu
-- DSCI 6600 基于结构化查询语言（SQL）的数据整理 期末作业项目2
-- 项目：校车事故数据清理 (School Bus Crash Data Wrangling)
-- 目的：清理原始事故数据，生成可用于研究"伤亡程度 vs 季节/时间/天气/
-- 路面状况/照明(雷电)状况"关联性的分析用数据集
-- 工具：MySQL 8.0 (DBeaver)
-- 原始数据：crash.csv (3684 行, 10 列)

-- ----------------------------------------------------------------------------
-- 0. 建库建表，导入原始数据
-- ----------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS school_bus_crash;
USE school_bus_crash;

DROP TABLE IF EXISTS crash_raw;
CREATE TABLE crash_raw (
    ID                     VARCHAR(20),
    City_Name              VARCHAR(100),
    Collision_Report_Type  VARCHAR(50),
    Crash_Date             VARCHAR(20),
    Full_Time              VARCHAR(20),
    Injury_Type            VARCHAR(30),
    Weather                VARCHAR(40),
    Roadway_Surface        VARCHAR(20),
    Lighting               VARCHAR(30),
    Vehicle_Type           VARCHAR(30)
);

-- 通过 DBeaver 的 "Import Data" 向导，将 crash.csv 导入 crash_raw 表
-- （字段对应关系：CSV 表头 -> 上方列名；" Injury Type" 前导空格在建表时
--   已通过重命名列名 Injury_Type 规避，避免后续引用出错）

SET GLOBAL local_infile = 1;
SHOW VARIABLES LIKE 'local_infile';

-- =====================================================
-- 导入crash.csv 数据到 crash_raw 表
-- =====================================================
LOAD DATA LOCAL INFILE '/Users/jiadiwu/Downloads/crash.csv'
INTO TABLE crash_raw
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
    ID,
    City_Name,
    Collision_Report_Type,
    Crash_Date,
    Full_Time,
    Injury_Type,
    Weather,
    Roadway_Surface,
    Lighting,
    Vehicle_Type
);


SELECT COUNT(*) AS raw_row_count FROM crash_raw;   -- 期望结果：3684

-- ============================================================================
-- 步骤 1：遵循并核查 8 步数据清理流程
-- ============================================================================

-- ---------- 1) 剔除无关数据 --------------------------------------------------
-- 研究目标只涉及：受伤类型、季节(由日期得出)、时间段(由时间得出)、天气、
-- 路面状况、照明(灯光)状况。City_Name、Collision_Report_Type、Vehicle_Type
-- 与研究问题无直接关系，予以剔除；ID 保留作为记录唯一标识。
DROP TABLE IF EXISTS crash_step1;
CREATE TABLE crash_step1 AS
SELECT
    ID,
    Crash_Date,
    Full_Time,
    Injury_Type,
    Weather,
    Roadway_Surface,
    Lighting
FROM crash_raw;

SELECT COUNT(*) AS step1_row_count FROM crash_step1;  -- 3684 行，7 列

-- ---------- 2) 消除重复数据 ---------------------------------------------------
-- 先检测在保留字段范围内的重复记录数
SELECT COUNT(*) AS duplicate_row_groups
FROM (
    SELECT ID, Crash_Date, Full_Time, Injury_Type, Weather, Roadway_Surface, Lighting,
           COUNT(*) AS cnt
    FROM crash_step1
    GROUP BY ID, Crash_Date, Full_Time, Injury_Type, Weather, Roadway_Surface, Lighting
    HAVING cnt > 1
) t;   -- 结果：564 组重复

-- 使用窗口函数 ROW_NUMBER() 按全部字段分组去重，只保留每组第一条
DROP TABLE IF EXISTS crash_step2;
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

SELECT COUNT(*) AS step2_row_count FROM crash_step2;   -- 结果：1434 行（等于唯一 ID 数）
SELECT COUNT(DISTINCT ID) AS distinct_id_count FROM crash_step2;  -- 1434，与上一致，确认去重彻底

-- ---------- 3) 修正结构错误 ----------------------------------------------------
-- 原始 CSV 表头 " Injury Type" 存在前导空格（已在建表阶段通过命名 Injury_Type 修正）；
-- 此处再对所有文本字段做首尾空白清理，防止导入过程中夹带空格导致后续分组出错。
DROP TABLE IF EXISTS crash_step3;
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

SELECT COUNT(*) AS step3_row_count FROM crash_step3;   -- 1434 行

-- ---------- 4) 执行数据类型转换 -------------------------------------------------
-- Crash_Date: 'M/D/YYYY' 字符串 -> DATE 类型
-- Full_Time : 'H:MM AM/PM' 字符串 -> TIME 类型（24 小时制）
DROP TABLE IF EXISTS crash_step4;
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

-- 校验转换是否产生 NULL（转换失败会返回 NULL）
SELECT
    SUM(CASE WHEN Crash_Date IS NULL THEN 1 ELSE 0 END) AS bad_dates,
    SUM(CASE WHEN Crash_Time IS NULL THEN 1 ELSE 0 END) AS bad_times
FROM crash_step4;   -- 期望结果：bad_dates = 0, bad_times = 0

-- ---------- 5) 处理缺失值 ------------------------------------------------------
-- 检查保留字段是否存在 NULL / 空字符串
SELECT
    SUM(ID IS NULL)                              AS na_id,
    SUM(Crash_Date IS NULL)                      AS na_date,
    SUM(Crash_Time IS NULL)                      AS na_time,
    SUM(Injury_Type IS NULL OR Injury_Type='')   AS na_injury,
    SUM(Weather IS NULL OR Weather='')           AS na_weather,
    SUM(Roadway_Surface IS NULL OR Roadway_Surface='') AS na_surface,
    SUM(Lighting IS NULL OR Lighting='')         AS na_lighting
FROM crash_step4;   -- 结果：全部为 0，核心字段无真正缺失

-- 说明：Weather / Roadway_Surface / Lighting 中存在取值为 'Unknown' 的记录
-- （分别 18 / 19 / 21 条），这是数据采集方明确标注的"未知"类别，而非缺失，
-- 予以保留作为独立分类，不做删除或插补，保证信息透明、不产生人为偏差。
SELECT Weather, COUNT(*) FROM crash_step4 GROUP BY Weather;
SELECT Roadway_Surface, COUNT(*) FROM crash_step4 GROUP BY Roadway_Surface;
SELECT Lighting, COUNT(*) FROM crash_step4 GROUP BY Lighting;

-- City_Name 字段（622/3684 缺失, 约17%）已在步骤1中整体剔除，故无需在此处理其缺失值。

-- ---------- 6) 标准化/规范化数据 ------------------------------------------------
-- 检查分类字段是否存在大小写/拼写不一致问题
SELECT DISTINCT Injury_Type FROM crash_step4;
SELECT DISTINCT Weather FROM crash_step4;
SELECT DISTINCT Roadway_Surface FROM crash_step4;
SELECT DISTINCT Lighting FROM crash_step4;
-- 核查结果：各分类字段命名规范统一（Title Case），无需额外标准化；
-- 日期已在步骤4统一为标准 DATE 类型 (YYYY-MM-DD)，时间已统一为 TIME 类型 (HH:MM:SS)。

DROP TABLE IF EXISTS crash_step6;
CREATE TABLE crash_step6 AS SELECT * FROM crash_step4;

-- ---------- 7) 处理异常值 ------------------------------------------------------
-- 日期范围检查（数据集应仅覆盖 2011 年）
SELECT MIN(Crash_Date) AS min_date, MAX(Crash_Date) AS max_date FROM crash_step6;
SELECT YEAR(Crash_Date) AS yr, COUNT(*) FROM crash_step6 GROUP BY yr;  -- 仅 2011 年，无异常

-- 时间范围检查（应落在 00:00:00 - 23:59:59 之间）
SELECT MIN(Crash_Time) AS min_time, MAX(Crash_Time) AS max_time FROM crash_step6;

-- ID 格式检查（应为 6-7 位数字，或以 E 开头的 6 位编码）
SELECT ID FROM crash_step6
WHERE ID NOT REGEXP '^[0-9]{6,7}$' AND ID NOT REGEXP '^E[0-9]{6}$';  -- 期望结果：空集
-- 核查结果：日期/时间/ID 均在合理范围内，未发现异常值需要处理。

-- ---------- 8) 数据验证 --------------------------------------------------------
SELECT COUNT(*) AS final_row_count FROM crash_step6;              -- 1434
SELECT COUNT(DISTINCT ID) AS distinct_ids FROM crash_step6;        -- 1434（与总行数一致，无重复）
SELECT
    SUM(Crash_Date IS NULL) + SUM(Crash_Time IS NULL) +
    SUM(Injury_Type IS NULL) + SUM(Weather IS NULL) +
    SUM(Roadway_Surface IS NULL) + SUM(Lighting IS NULL) AS total_nulls
FROM crash_step6;   -- 期望结果：0

-- ============================================================================
-- 步骤 2：根据数据创建必要列（季节 Season、时间段 Time_Period）
-- ============================================================================
DROP TABLE IF EXISTS crash_step7;
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
        WHEN HOUR(Crash_Time) BETWEEN 6 AND 19 THEN 'Daytime'    -- 6:00–19:59
        ELSE 'Nighttime'                                          -- 20:00–5:59
    END AS Time_Period,
    Injury_Type,
    Weather,
    Roadway_Surface,
    Lighting
FROM crash_step6;

SELECT Season, COUNT(*) FROM crash_step7 GROUP BY Season ORDER BY 2 DESC;
SELECT Time_Period, COUNT(*) FROM crash_step7 GROUP BY Time_Period;

-- ============================================================================
-- 步骤 3：合并部分分类
-- ============================================================================
DROP TABLE IF EXISTS crash_final;
CREATE TABLE crash_final AS
SELECT
    ID,
    Crash_Date,
    Crash_Time,
    Crash_Month,
    Season,
    Time_Period,
    -- 受伤类型：将 'Possible Injury' 与 'Evident Injury' 合并为 'Minor Injury'（轻伤）
    CASE
        WHEN Injury_Type IN ('Possible Injury', 'Evident Injury') THEN 'Minor Injury'
        ELSE Injury_Type   -- 保留 'No Injury' / 'Serious Injury'
    END AS Injury_Type_Grouped,
    Weather,
    Roadway_Surface,
    -- 照明状况：将 'Dark-Street Lights Off' 与 'Dark-No Street Lights' 合并为 'Dark'（黑暗）
    CASE
        WHEN Lighting IN ('Dark-Street Lights Off', 'Dark-No Street Lights') THEN 'Dark'
        ELSE Lighting      -- 保留 'Daylight' / 'Dark-Street Lights On' / 'Unknown'
    END AS Lighting_Grouped
FROM crash_step7;

-- 最终结果核查
SELECT COUNT(*) AS final_total FROM crash_final;                       -- 1434
SELECT Injury_Type_Grouped, COUNT(*) FROM crash_final GROUP BY Injury_Type_Grouped ORDER BY 2 DESC;
SELECT Lighting_Grouped, COUNT(*) FROM crash_final GROUP BY Lighting_Grouped ORDER BY 2 DESC;

SELECT * FROM crash_final ORDER BY Crash_Date, Crash_Time LIMIT 20;

-- ============================================================================
-- 导出：在 DBeaver 中右键 crash_final 表 -> Export Data -> CSV
-- 输出文件：cleaned_school_bus_crash_data.csv
-- ============================================================================