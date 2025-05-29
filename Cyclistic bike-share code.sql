CREATE DATABASE bike_data;
USE bike_data;


--1.DATA PREPARATION

--Create new table "trip_data" after concatenate tables from tripdata_01 to tripdata_12
DECLARE @sql NVARCHAR(MAX) = '';
DECLARE @i INT = 1;

WHILE @i <= 12
BEGIN
    SET @sql += 'SELECT * FROM tripdata_' + RIGHT('0' + CAST(@i AS VARCHAR), 2) + ' UNION ALL ';
    SET @i += 1;
END

SET @sql = LEFT(@sql, LEN(@sql) - 10); 

SET @sql = 'SELECT * INTO trip_data FROM (' + @sql + ') AS combined_data';

EXEC sp_executesql @sql;

--Count NULL 
DECLARE @table_name NVARCHAR(100) = 'trip_data';
DECLARE @sql NVARCHAR(MAX) = '';

SELECT @sql = @sql + '
IF EXISTS (
    SELECT 1 FROM ' + QUOTENAME(@table_name) + ' WHERE [' + COLUMN_NAME + '] IS NULL
)
BEGIN
    SELECT ''' + COLUMN_NAME + ''' AS Column_name, COUNT(*) AS Count_NULL
    FROM ' + QUOTENAME(@table_name) + '
    WHERE [' + COLUMN_NAME + '] IS NULL;
END;
'
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = @table_name AND TABLE_SCHEMA = 'dbo';

EXEC sp_executesql @sql;


--2.DATA CLEANSING

--Remove duplicates
SELECT DISTINCT * INTO #tripdata_dedup
FROM trip_data;

--Handle missing values 
UPDATE #tripdata_dedup
SET start_station_name = ISNULL(start_station_name, 'None'),
	start_station_id = ISNULL(start_station_id, 'None'),
	end_station_name = ISNULL(end_station_name, 'None'),
	end_station_id = ISNULL(end_station_id, 'None'),
	end_lat = ISNULL(end_lat, 0),
	end_lng = ISNULL(end_lng, 0)
WHERE start_station_name IS NULL
   OR start_station_id IS NULL
   OR end_station_name IS NULL
   OR end_station_id IS NULL
   OR end_lat IS NULL
   OR end_lng IS NULL;

--Create new table after cleaning
SELECT * INTO tripdata_cleaned
FROM #tripdata_dedup;


--3.ANALYZE DATA

--Trip duration
WITH RideDurations AS (
  SELECT
    member_casual,
    DATEDIFF(MINUTE, started_at, ended_at) AS ride_duration
  FROM tripdata_cleaned
  WHERE DATEDIFF(MINUTE, started_at, ended_at) > 1
)
SELECT
  member_casual,
  AVG(ride_duration) AS avg_duration_min,
  MAX(ride_duration) AS max_duration_min,
  COUNT(*) AS total_rides
FROM RideDurations
GROUP BY member_casual;

--Rides by day of week
SELECT 
  member_casual,
  DATENAME(WEEKDAY, started_at) AS day_of_week,
  COUNT(*) AS ride_count
FROM tripdata_cleaned
GROUP BY member_casual, DATENAME(WEEKDAY, started_at)
ORDER BY member_casual, 
  CASE DATENAME(WEEKDAY, started_at)
    WHEN 'Monday' THEN 1
    WHEN 'Tuesday' THEN 2
    WHEN 'Wednesday' THEN 3
    WHEN 'Thursday' THEN 4
    WHEN 'Friday' THEN 5
    WHEN 'Saturday' THEN 6
    WHEN 'Sunday' THEN 7
  END;

--Rides by time of day
WITH HourlyRides AS (
  SELECT
    member_casual,
    DATEPART(HOUR, started_at) AS hour_of_day
  FROM tripdata_cleaned
)
SELECT
  member_casual,
  hour_of_day,
  COUNT(*) AS ride_count
FROM HourlyRides
GROUP BY member_casual, hour_of_day
ORDER BY member_casual, hour_of_day;

--Rideable type preference
SELECT DISTINCT
  member_casual,
  rideable_type,
  COUNT(*) OVER (PARTITION BY member_casual, rideable_type) AS count_ride
FROM tripdata_cleaned
ORDER BY member_casual, count_ride DESC;

--Popular start stations
WITH StationCounts AS (
  SELECT
    member_casual,
    start_station_name,
    COUNT(*) AS rides,
    ROW_NUMBER() OVER (PARTITION BY member_casual ORDER BY COUNT(*) DESC) AS rn
  FROM tripdata_cleaned
  GROUP BY member_casual, start_station_name
)
SELECT *
FROM StationCounts
WHERE rn <= 5
ORDER BY member_casual, rides DESC;