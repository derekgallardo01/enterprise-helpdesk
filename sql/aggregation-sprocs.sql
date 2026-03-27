-- Aggregation stored procedures for pre-computed Power BI tables
-- Called by DataverseSyncService.RefreshAggregationsAsync after each sync cycle

-- ============================================================
-- 1. Daily ticket volume by status and category
-- ============================================================

IF OBJECT_ID('dbo.usp_RefreshTicketVolumeDaily', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_RefreshTicketVolumeDaily;
GO

CREATE PROCEDURE dbo.usp_RefreshTicketVolumeDaily
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.TicketVolumeDaily;

    INSERT INTO dbo.TicketVolumeDaily (
        DateKey,
        CategoryId,
        Priority,
        TicketsCreated,
        TicketsResolved,
        TicketsBreached,
        AvgResolutionMinutes
    )
    SELECT
        tf.CreatedDateKey                                       AS DateKey,
        tf.CategoryId,
        tf.Priority,
        COUNT(*)                                                AS TicketsCreated,
        SUM(CASE WHEN tf.Status IN (6, 7) THEN 1 ELSE 0 END)  AS TicketsResolved,
        SUM(CASE WHEN tf.SLABreached = 1 THEN 1 ELSE 0 END)   AS TicketsBreached,
        AVG(CAST(tf.ResolutionMinutes AS DECIMAL(10, 2)))       AS AvgResolutionMinutes
    FROM dbo.TicketFact tf
    WHERE tf.CreatedDateKey IS NOT NULL
      AND tf.CategoryId IS NOT NULL
    GROUP BY
        tf.CreatedDateKey,
        tf.CategoryId,
        tf.Priority;
END
GO

-- ============================================================
-- 2. Monthly SLA compliance by category
-- ============================================================

IF OBJECT_ID('dbo.usp_RefreshSLAComplianceMonthly', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_RefreshSLAComplianceMonthly;
GO

CREATE PROCEDURE dbo.usp_RefreshSLAComplianceMonthly
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.SLAComplianceMonthly;

    INSERT INTO dbo.SLAComplianceMonthly (
        Year,
        Month,
        CategoryId,
        TotalTickets,
        WithinSLA,
        Breached
    )
    SELECT
        YEAR(tf.CreatedOn)                                      AS [Year],
        MONTH(tf.CreatedOn)                                     AS [Month],
        tf.CategoryId,
        COUNT(*)                                                AS TotalTickets,
        SUM(CASE WHEN tf.SLABreached = 0 THEN 1 ELSE 0 END)   AS WithinSLA,
        SUM(CASE WHEN tf.SLABreached = 1 THEN 1 ELSE 0 END)   AS Breached
    FROM dbo.TicketFact tf
    WHERE tf.CategoryId IS NOT NULL
    GROUP BY
        YEAR(tf.CreatedOn),
        MONTH(tf.CreatedOn),
        tf.CategoryId;
END
GO

-- ============================================================
-- 3. Weekly agent performance
-- ============================================================

IF OBJECT_ID('dbo.usp_RefreshAgentPerformanceWeekly', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_RefreshAgentPerformanceWeekly;
GO

CREATE PROCEDURE dbo.usp_RefreshAgentPerformanceWeekly
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.AgentPerformanceWeekly;

    INSERT INTO dbo.AgentPerformanceWeekly (
        Year,
        WeekNumber,
        AgentId,
        TicketsAssigned,
        TicketsResolved,
        AvgResolutionMinutes,
        AvgSatisfaction,
        SLABreachCount
    )
    SELECT
        YEAR(tf.CreatedOn)                                          AS [Year],
        DATEPART(ISO_WEEK, tf.CreatedOn)                            AS WeekNumber,
        tf.AssignedToId                                             AS AgentId,
        COUNT(*)                                                    AS TicketsAssigned,
        SUM(CASE WHEN tf.Status IN (6, 7) THEN 1 ELSE 0 END)      AS TicketsResolved,
        AVG(CAST(tf.ResolutionMinutes AS DECIMAL(10, 2)))           AS AvgResolutionMinutes,
        AVG(CAST(tf.SatisfactionRating AS DECIMAL(3, 2)))           AS AvgSatisfaction,
        SUM(CASE WHEN tf.SLABreached = 1 THEN 1 ELSE 0 END)       AS SLABreachCount
    FROM dbo.TicketFact tf
    WHERE tf.AssignedToId IS NOT NULL
    GROUP BY
        YEAR(tf.CreatedOn),
        DATEPART(ISO_WEEK, tf.CreatedOn),
        tf.AssignedToId;
END
GO
