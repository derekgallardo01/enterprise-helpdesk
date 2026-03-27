-- Populate DateDim from 2020-01-01 to 2030-12-31
-- Run once after schema.sql to populate the date dimension table.
-- Uses a recursive CTE; MAXRECURSION 0 required for >100 rows.

SET NOCOUNT ON;

-- Only seed if DateDim is empty (idempotent)
IF NOT EXISTS (SELECT 1 FROM dbo.DateDim)
BEGIN
    ;WITH DateCTE AS (
        SELECT CAST('2020-01-01' AS DATE) AS FullDate
        UNION ALL
        SELECT DATEADD(DAY, 1, FullDate)
        FROM DateCTE
        WHERE FullDate < '2030-12-31'
    )
    INSERT INTO dbo.DateDim (
        DateKey,
        FullDate,
        DayOfWeek,
        DayName,
        MonthNumber,
        MonthName,
        Quarter,
        Year,
        FiscalYear,
        FiscalQuarter,
        IsWeekend,
        IsBusinessDay
    )
    SELECT
        CAST(FORMAT(FullDate, 'yyyyMMdd') AS INT)       AS DateKey,
        FullDate,
        DATEPART(WEEKDAY, FullDate)                      AS DayOfWeek,
        DATENAME(WEEKDAY, FullDate)                      AS DayName,
        MONTH(FullDate)                                  AS MonthNumber,
        DATENAME(MONTH, FullDate)                        AS MonthName,
        DATEPART(QUARTER, FullDate)                      AS Quarter,
        YEAR(FullDate)                                   AS Year,
        -- Fiscal year starts July 1
        CASE
            WHEN MONTH(FullDate) >= 7 THEN YEAR(FullDate) + 1
            ELSE YEAR(FullDate)
        END                                              AS FiscalYear,
        CASE
            WHEN MONTH(FullDate) IN (7, 8, 9)   THEN 1
            WHEN MONTH(FullDate) IN (10, 11, 12) THEN 2
            WHEN MONTH(FullDate) IN (1, 2, 3)   THEN 3
            ELSE 4
        END                                              AS FiscalQuarter,
        CASE
            WHEN DATEPART(WEEKDAY, FullDate) IN (1, 7) THEN 1
            ELSE 0
        END                                              AS IsWeekend,
        CASE
            WHEN DATEPART(WEEKDAY, FullDate) BETWEEN 2 AND 6 THEN 1
            ELSE 0
        END                                              AS IsBusinessDay
    FROM DateCTE
    OPTION (MAXRECURSION 0);

    PRINT 'DateDim seeded with ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' rows.';
END
ELSE
BEGIN
    PRINT 'DateDim already populated. Skipping seed.';
END
GO
