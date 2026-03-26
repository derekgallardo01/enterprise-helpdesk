-- Enterprise Help Desk — Azure SQL Reporting Warehouse
-- Star schema optimized for Power BI DirectQuery
-- Synced from Dataverse via Azure Function (DataverseSyncToSQL) using change tracking

-- ============================================================
-- Dimension Tables
-- ============================================================

CREATE TABLE dbo.DateDim (
    DateKey         INT             PRIMARY KEY,    -- YYYYMMDD format
    FullDate        DATE            NOT NULL,
    DayOfWeek       INT             NOT NULL,       -- 1=Sunday, 7=Saturday
    DayName         NVARCHAR(10)    NOT NULL,
    MonthNumber     INT             NOT NULL,
    MonthName       NVARCHAR(10)    NOT NULL,
    Quarter         INT             NOT NULL,
    Year            INT             NOT NULL,
    IsBusinessDay   BIT             NOT NULL,       -- M-F, excluding holidays
    IsWeekend       BIT             NOT NULL,
    FiscalYear      INT             NOT NULL,
    FiscalQuarter   INT             NOT NULL
);

CREATE TABLE dbo.CategoryDim (
    CategoryId      UNIQUEIDENTIFIER    PRIMARY KEY,
    CategoryName    NVARCHAR(100)       NOT NULL,
    IsActive        BIT                 NOT NULL DEFAULT 1,
    SyncedOn        DATETIME2           NOT NULL DEFAULT GETUTCDATE()
);

CREATE TABLE dbo.SubcategoryDim (
    SubcategoryId   UNIQUEIDENTIFIER    PRIMARY KEY,
    SubcategoryName NVARCHAR(100)       NOT NULL,
    CategoryId      UNIQUEIDENTIFIER    NOT NULL REFERENCES dbo.CategoryDim(CategoryId),
    IsActive        BIT                 NOT NULL DEFAULT 1,
    SyncedOn        DATETIME2           NOT NULL DEFAULT GETUTCDATE()
);

CREATE TABLE dbo.DepartmentDim (
    DepartmentId    UNIQUEIDENTIFIER    PRIMARY KEY,
    DepartmentName  NVARCHAR(100)       NOT NULL,
    ManagerName     NVARCHAR(200)       NULL,
    CostCenter      NVARCHAR(20)        NULL,
    SyncedOn        DATETIME2           NOT NULL DEFAULT GETUTCDATE()
);

CREATE TABLE dbo.AgentDim (
    AgentId         UNIQUEIDENTIFIER    PRIMARY KEY,
    DisplayName     NVARCHAR(200)       NOT NULL,
    Email           NVARCHAR(200)       NULL,
    TeamName        NVARCHAR(100)       NULL,
    BusinessUnit    NVARCHAR(100)       NULL,
    IsActive        BIT                 NOT NULL DEFAULT 1,
    SyncedOn        DATETIME2           NOT NULL DEFAULT GETUTCDATE()
);

-- ============================================================
-- Fact Table
-- ============================================================

CREATE TABLE dbo.TicketFact (
    TicketId                UNIQUEIDENTIFIER    PRIMARY KEY,
    TicketNumber            NVARCHAR(20)        NOT NULL,
    Title                   NVARCHAR(200)       NOT NULL,

    -- Dimension keys
    CategoryId              UNIQUEIDENTIFIER    NULL REFERENCES dbo.CategoryDim(CategoryId),
    SubcategoryId           UNIQUEIDENTIFIER    NULL REFERENCES dbo.SubcategoryDim(SubcategoryId),
    DepartmentId            UNIQUEIDENTIFIER    NULL REFERENCES dbo.DepartmentDim(DepartmentId),
    RequestedById           UNIQUEIDENTIFIER    NULL,
    AssignedToId            UNIQUEIDENTIFIER    NULL REFERENCES dbo.AgentDim(AgentId),

    -- Measures (choice values stored as integers)
    Priority                INT                 NOT NULL,   -- 1=Critical, 2=High, 3=Medium, 4=Low
    Status                  INT                 NOT NULL,   -- 1=New .. 8=Cancelled
    Impact                  INT                 NULL,       -- 1=Enterprise, 2=Department, 3=Individual
    Urgency                 INT                 NULL,       -- 1=Critical, 2=High, 3=Medium, 4=Low
    Source                  INT                 NULL,       -- 1=Portal, 2=Email, 3=Teams Bot, 4=Phone, 5=Walk-up
    SLABreached             BIT                 NOT NULL DEFAULT 0,
    SatisfactionRating      INT                 NULL,       -- 1-5

    -- Timestamps
    CreatedOn               DATETIME2           NOT NULL,
    ResolvedOn              DATETIME2           NULL,
    DueDate                 DATETIME2           NULL,
    FirstResponseAt         DATETIME2           NULL,

    -- Computed measures (calculated at write time for query performance)
    ResolutionMinutes       AS DATEDIFF(MINUTE, CreatedOn, ResolvedOn),
    FirstResponseMinutes    AS DATEDIFF(MINUTE, CreatedOn, FirstResponseAt),
    IsOverdue               AS CASE
                                WHEN DueDate < GETUTCDATE() AND Status NOT IN (6, 7, 8) THEN 1
                                ELSE 0
                            END,

    -- Date keys for joining to DateDim
    CreatedDateKey          AS CAST(FORMAT(CreatedOn, 'yyyyMMdd') AS INT) PERSISTED,
    ResolvedDateKey         AS CAST(FORMAT(ResolvedOn, 'yyyyMMdd') AS INT) PERSISTED,

    -- Sync metadata
    SyncedOn                DATETIME2           NOT NULL DEFAULT GETUTCDATE(),
    DataverseModifiedOn     DATETIME2           NOT NULL
);

-- ============================================================
-- Aggregation Tables (pre-computed for Power BI performance)
-- ============================================================

-- Daily ticket volume by category — avoids scanning TicketFact for trend charts
CREATE TABLE dbo.TicketVolumeDaily (
    DateKey         INT                 NOT NULL,
    CategoryId      UNIQUEIDENTIFIER    NOT NULL,
    Priority        INT                 NOT NULL,
    TicketsCreated  INT                 NOT NULL DEFAULT 0,
    TicketsResolved INT                 NOT NULL DEFAULT 0,
    TicketsBreached INT                 NOT NULL DEFAULT 0,
    AvgResolutionMinutes    DECIMAL(10,2)   NULL,
    PRIMARY KEY (DateKey, CategoryId, Priority)
);

-- Monthly SLA compliance — expensive to compute live
CREATE TABLE dbo.SLAComplianceMonthly (
    Year            INT                 NOT NULL,
    Month           INT                 NOT NULL,
    CategoryId      UNIQUEIDENTIFIER    NOT NULL,
    TotalTickets    INT                 NOT NULL DEFAULT 0,
    WithinSLA       INT                 NOT NULL DEFAULT 0,
    Breached        INT                 NOT NULL DEFAULT 0,
    CompliancePct   AS CASE
                        WHEN TotalTickets > 0
                        THEN CAST(WithinSLA AS DECIMAL(5,2)) / TotalTickets * 100
                        ELSE 0
                    END,
    PRIMARY KEY (Year, Month, CategoryId)
);

-- Weekly agent performance — avoids complex window functions at query time
CREATE TABLE dbo.AgentPerformanceWeekly (
    Year            INT                 NOT NULL,
    WeekNumber      INT                 NOT NULL,
    AgentId         UNIQUEIDENTIFIER    NOT NULL REFERENCES dbo.AgentDim(AgentId),
    TicketsAssigned INT                 NOT NULL DEFAULT 0,
    TicketsResolved INT                 NOT NULL DEFAULT 0,
    AvgResolutionMinutes    DECIMAL(10,2)   NULL,
    AvgSatisfaction         DECIMAL(3,2)    NULL,
    SLABreachCount  INT                 NOT NULL DEFAULT 0,
    PRIMARY KEY (Year, WeekNumber, AgentId)
);

-- ============================================================
-- Indexes (optimized for Power BI query patterns)
-- ============================================================

-- Most common filter: status + date range
CREATE INDEX IX_TicketFact_Status_CreatedOn
    ON dbo.TicketFact (Status, CreatedOn)
    INCLUDE (Priority, CategoryId, AssignedToId);

-- Category drill-down
CREATE INDEX IX_TicketFact_CategoryId
    ON dbo.TicketFact (CategoryId)
    INCLUDE (Status, Priority, CreatedOn, ResolvedOn, SLABreached);

-- Agent performance queries
CREATE INDEX IX_TicketFact_AssignedToId
    ON dbo.TicketFact (AssignedToId)
    INCLUDE (Status, CreatedOn, ResolvedOn, SatisfactionRating, SLABreached);

-- Date dimension joins
CREATE INDEX IX_TicketFact_CreatedDateKey
    ON dbo.TicketFact (CreatedDateKey)
    INCLUDE (CategoryId, Priority, Status);

-- SLA breach analysis
CREATE INDEX IX_TicketFact_SLABreached
    ON dbo.TicketFact (SLABreached)
    WHERE SLABreached = 1;

-- Department breakdown
CREATE INDEX IX_TicketFact_DepartmentId
    ON dbo.TicketFact (DepartmentId)
    INCLUDE (CategoryId, Priority, Status, CreatedOn);

-- Sync tracking (used by DataverseSyncToSQL to find stale rows)
CREATE INDEX IX_TicketFact_SyncedOn
    ON dbo.TicketFact (SyncedOn);

-- ============================================================
-- DateDim Population (generate 10 years of dates)
-- ============================================================

-- Run this once to populate the date dimension
-- Adjust date range as needed

/*
DECLARE @StartDate DATE = '2020-01-01';
DECLARE @EndDate DATE = '2030-12-31';

;WITH DateCTE AS (
    SELECT @StartDate AS FullDate
    UNION ALL
    SELECT DATEADD(DAY, 1, FullDate)
    FROM DateCTE
    WHERE FullDate < @EndDate
)
INSERT INTO dbo.DateDim (DateKey, FullDate, DayOfWeek, DayName, MonthNumber, MonthName, Quarter, Year, IsBusinessDay, IsWeekend, FiscalYear, FiscalQuarter)
SELECT
    CAST(FORMAT(FullDate, 'yyyyMMdd') AS INT),
    FullDate,
    DATEPART(WEEKDAY, FullDate),
    DATENAME(WEEKDAY, FullDate),
    MONTH(FullDate),
    DATENAME(MONTH, FullDate),
    DATEPART(QUARTER, FullDate),
    YEAR(FullDate),
    CASE WHEN DATEPART(WEEKDAY, FullDate) BETWEEN 2 AND 6 THEN 1 ELSE 0 END,
    CASE WHEN DATEPART(WEEKDAY, FullDate) IN (1, 7) THEN 1 ELSE 0 END,
    CASE WHEN MONTH(FullDate) >= 7 THEN YEAR(FullDate) + 1 ELSE YEAR(FullDate) END,
    CASE
        WHEN MONTH(FullDate) IN (7,8,9) THEN 1
        WHEN MONTH(FullDate) IN (10,11,12) THEN 2
        WHEN MONTH(FullDate) IN (1,2,3) THEN 3
        ELSE 4
    END
FROM DateCTE
OPTION (MAXRECURSION 0);
*/
