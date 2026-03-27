-- ============================================================
-- SQL Seed Data for Azure SQL Reporting Warehouse
-- Populates dimension tables and 1,000 rows in TicketFact
-- for Power BI development and performance testing.
--
-- Prerequisites:
--   - schema.sql has been executed
--   - seed-date-dim.sql has been executed (DateDim populated)
--
-- Usage:
--   sqlcmd -S helpdesk-sql-test.database.windows.net -d helpdesk-reporting -G -i sql-seed.sql
-- ============================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

-- ============================================================
-- 1. Seed CategoryDim
-- ============================================================
PRINT 'Seeding CategoryDim...';

MERGE dbo.CategoryDim AS target
USING (VALUES
    (NEWID(), 'Hardware',       1),
    (NEWID(), 'Software',       1),
    (NEWID(), 'Network',        1),
    (NEWID(), 'Email',          1),
    (NEWID(), 'Access',         1),
    (NEWID(), 'Telephony',      1),
    (NEWID(), 'Printing',       1),
    (NEWID(), 'Security',       1),
    (NEWID(), 'Cloud Services', 1),
    (NEWID(), 'Other',          1)
) AS source (CategoryId, CategoryName, IsActive)
ON target.CategoryName = source.CategoryName
WHEN NOT MATCHED THEN
    INSERT (CategoryId, CategoryName, IsActive, SyncedOn)
    VALUES (source.CategoryId, source.CategoryName, source.IsActive, GETUTCDATE());

-- Capture category IDs for FK references
DECLARE @Categories TABLE (CategoryId UNIQUEIDENTIFIER, CategoryName NVARCHAR(100));
INSERT INTO @Categories SELECT CategoryId, CategoryName FROM dbo.CategoryDim;

-- ============================================================
-- 2. Seed SubcategoryDim
-- ============================================================
PRINT 'Seeding SubcategoryDim...';

-- Hardware subcategories
INSERT INTO dbo.SubcategoryDim (SubcategoryId, SubcategoryName, CategoryId, IsActive, SyncedOn)
SELECT NEWID(), s.SubName, c.CategoryId, 1, GETUTCDATE()
FROM (VALUES ('Laptop'), ('Desktop'), ('Monitor'), ('Peripheral'), ('Mobile Device')) AS s(SubName)
CROSS JOIN @Categories c WHERE c.CategoryName = 'Hardware'
AND NOT EXISTS (SELECT 1 FROM dbo.SubcategoryDim WHERE SubcategoryName = s.SubName AND CategoryId = c.CategoryId);

-- Software subcategories
INSERT INTO dbo.SubcategoryDim (SubcategoryId, SubcategoryName, CategoryId, IsActive, SyncedOn)
SELECT NEWID(), s.SubName, c.CategoryId, 1, GETUTCDATE()
FROM (VALUES ('Installation'), ('Configuration'), ('License'), ('Bug'), ('Update')) AS s(SubName)
CROSS JOIN @Categories c WHERE c.CategoryName = 'Software'
AND NOT EXISTS (SELECT 1 FROM dbo.SubcategoryDim WHERE SubcategoryName = s.SubName AND CategoryId = c.CategoryId);

-- Network subcategories
INSERT INTO dbo.SubcategoryDim (SubcategoryId, SubcategoryName, CategoryId, IsActive, SyncedOn)
SELECT NEWID(), s.SubName, c.CategoryId, 1, GETUTCDATE()
FROM (VALUES ('Connectivity'), ('VPN'), ('WiFi'), ('Firewall'), ('DNS')) AS s(SubName)
CROSS JOIN @Categories c WHERE c.CategoryName = 'Network'
AND NOT EXISTS (SELECT 1 FROM dbo.SubcategoryDim WHERE SubcategoryName = s.SubName AND CategoryId = c.CategoryId);

-- Email subcategories
INSERT INTO dbo.SubcategoryDim (SubcategoryId, SubcategoryName, CategoryId, IsActive, SyncedOn)
SELECT NEWID(), s.SubName, c.CategoryId, 1, GETUTCDATE()
FROM (VALUES ('Outlook'), ('Calendar'), ('Distribution List'), ('Shared Mailbox')) AS s(SubName)
CROSS JOIN @Categories c WHERE c.CategoryName = 'Email'
AND NOT EXISTS (SELECT 1 FROM dbo.SubcategoryDim WHERE SubcategoryName = s.SubName AND CategoryId = c.CategoryId);

-- Access subcategories
INSERT INTO dbo.SubcategoryDim (SubcategoryId, SubcategoryName, CategoryId, IsActive, SyncedOn)
SELECT NEWID(), s.SubName, c.CategoryId, 1, GETUTCDATE()
FROM (VALUES ('Account Lockout'), ('Password Reset'), ('Permissions'), ('New Account'), ('MFA')) AS s(SubName)
CROSS JOIN @Categories c WHERE c.CategoryName = 'Access'
AND NOT EXISTS (SELECT 1 FROM dbo.SubcategoryDim WHERE SubcategoryName = s.SubName AND CategoryId = c.CategoryId);

-- Security subcategories
INSERT INTO dbo.SubcategoryDim (SubcategoryId, SubcategoryName, CategoryId, IsActive, SyncedOn)
SELECT NEWID(), s.SubName, c.CategoryId, 1, GETUTCDATE()
FROM (VALUES ('Phishing'), ('Malware'), ('Data Loss'), ('Compliance'), ('Vulnerability')) AS s(SubName)
CROSS JOIN @Categories c WHERE c.CategoryName = 'Security'
AND NOT EXISTS (SELECT 1 FROM dbo.SubcategoryDim WHERE SubcategoryName = s.SubName AND CategoryId = c.CategoryId);

-- Cloud Services subcategories
INSERT INTO dbo.SubcategoryDim (SubcategoryId, SubcategoryName, CategoryId, IsActive, SyncedOn)
SELECT NEWID(), s.SubName, c.CategoryId, 1, GETUTCDATE()
FROM (VALUES ('SharePoint'), ('Teams'), ('OneDrive'), ('Azure'), ('Power Platform')) AS s(SubName)
CROSS JOIN @Categories c WHERE c.CategoryName = 'Cloud Services'
AND NOT EXISTS (SELECT 1 FROM dbo.SubcategoryDim WHERE SubcategoryName = s.SubName AND CategoryId = c.CategoryId);

-- ============================================================
-- 3. Seed DepartmentDim
-- ============================================================
PRINT 'Seeding DepartmentDim...';

MERGE dbo.DepartmentDim AS target
USING (VALUES
    (NEWID(), 'Information Technology', 'Jane Smith',     'CC-100'),
    (NEWID(), 'Human Resources',       'Bob Johnson',    'CC-200'),
    (NEWID(), 'Finance',               'Alice Brown',    'CC-300'),
    (NEWID(), 'Marketing',             'Charlie Wilson',  'CC-400'),
    (NEWID(), 'Sales',                 'Diana Martinez',  'CC-500'),
    (NEWID(), 'Engineering',           'Eric Lee',        'CC-600'),
    (NEWID(), 'Legal',                 'Fiona Davis',     'CC-700'),
    (NEWID(), 'Operations',            'George White',    'CC-800')
) AS source (DepartmentId, DepartmentName, ManagerName, CostCenter)
ON target.DepartmentName = source.DepartmentName
WHEN NOT MATCHED THEN
    INSERT (DepartmentId, DepartmentName, ManagerName, CostCenter, SyncedOn)
    VALUES (source.DepartmentId, source.DepartmentName, source.ManagerName, source.CostCenter, GETUTCDATE());

-- ============================================================
-- 4. Seed AgentDim
-- ============================================================
PRINT 'Seeding AgentDim...';

MERGE dbo.AgentDim AS target
USING (VALUES
    (NEWID(), 'Sarah Connor',     'sarah.connor@contoso.com',    'Tier 1 Support',   'IT Operations'),
    (NEWID(), 'John Matrix',      'john.matrix@contoso.com',     'Tier 1 Support',   'IT Operations'),
    (NEWID(), 'Ellen Ripley',     'ellen.ripley@contoso.com',    'Tier 2 Support',   'IT Operations'),
    (NEWID(), 'Thomas Anderson',  'thomas.anderson@contoso.com', 'Tier 2 Support',   'IT Operations'),
    (NEWID(), 'Diana Prince',     'diana.prince@contoso.com',    'Network Team',     'Infrastructure'),
    (NEWID(), 'Peter Parker',     'peter.parker@contoso.com',    'Desktop Support',  'IT Operations'),
    (NEWID(), 'Natasha Romanoff', 'natasha.romanoff@contoso.com','Security Team',    'Cybersecurity'),
    (NEWID(), 'Bruce Banner',     'bruce.banner@contoso.com',    'Cloud Team',       'Cloud Services'),
    (NEWID(), 'Tony Stark',       'tony.stark@contoso.com',      'Application Support','IT Operations'),
    (NEWID(), 'Steve Rogers',     'steve.rogers@contoso.com',    'Tier 1 Support',   'IT Operations')
) AS source (AgentId, DisplayName, Email, TeamName, BusinessUnit)
ON target.Email = source.Email
WHEN NOT MATCHED THEN
    INSERT (AgentId, DisplayName, Email, TeamName, BusinessUnit, IsActive, SyncedOn)
    VALUES (source.AgentId, source.DisplayName, source.Email, source.TeamName, source.BusinessUnit, 1, GETUTCDATE());

-- Capture agent IDs
DECLARE @Agents TABLE (AgentId UNIQUEIDENTIFIER, RowNum INT);
INSERT INTO @Agents SELECT AgentId, ROW_NUMBER() OVER (ORDER BY DisplayName) FROM dbo.AgentDim;

-- Capture subcategory IDs with their categories
DECLARE @Subcategories TABLE (SubcategoryId UNIQUEIDENTIFIER, CategoryId UNIQUEIDENTIFIER, RowNum INT);
INSERT INTO @Subcategories SELECT SubcategoryId, CategoryId, ROW_NUMBER() OVER (ORDER BY SubcategoryName) FROM dbo.SubcategoryDim;

-- Capture department IDs
DECLARE @Departments TABLE (DepartmentId UNIQUEIDENTIFIER, RowNum INT);
INSERT INTO @Departments SELECT DepartmentId, ROW_NUMBER() OVER (ORDER BY DepartmentName) FROM dbo.DepartmentDim;

-- ============================================================
-- 5. Generate 1,000 TicketFact rows
-- ============================================================
PRINT 'Generating 1,000 TicketFact rows...';

-- Use a numbers table approach for batch generation
;WITH Numbers AS (
    SELECT TOP 1000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS N
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
),
TicketData AS (
    SELECT
        N,
        NEWID()                                                     AS TicketId,
        'HD-' + RIGHT('00000' + CAST(10000 + N AS VARCHAR), 5)     AS TicketNumber,

        -- Random category/subcategory
        ABS(CHECKSUM(NEWID())) % (SELECT COUNT(*) FROM @Subcategories) + 1 AS SubcatRow,

        -- Random agent
        ABS(CHECKSUM(NEWID())) % (SELECT COUNT(*) FROM @Agents) + 1 AS AgentRow,

        -- Random department
        ABS(CHECKSUM(NEWID())) % (SELECT COUNT(*) FROM @Departments) + 1 AS DeptRow,

        -- Priority distribution: 5% Critical, 15% High, 50% Medium, 30% Low
        CASE
            WHEN ABS(CHECKSUM(NEWID())) % 100 < 5  THEN 1
            WHEN ABS(CHECKSUM(NEWID())) % 100 < 20 THEN 2
            WHEN ABS(CHECKSUM(NEWID())) % 100 < 70 THEN 3
            ELSE 4
        END                                                         AS Priority,

        -- Status distribution: 20% New, 30% Active, 5% Pending, 25% Resolved, 15% Closed, 5% Cancelled
        CASE
            WHEN ABS(CHECKSUM(NEWID())) % 100 < 20 THEN 1
            WHEN ABS(CHECKSUM(NEWID())) % 100 < 50 THEN 3
            WHEN ABS(CHECKSUM(NEWID())) % 100 < 55 THEN 4
            WHEN ABS(CHECKSUM(NEWID())) % 100 < 80 THEN 6
            WHEN ABS(CHECKSUM(NEWID())) % 100 < 95 THEN 7
            ELSE 8
        END                                                         AS Status,

        -- Impact: 10% Enterprise, 30% Department, 60% Individual
        CASE
            WHEN ABS(CHECKSUM(NEWID())) % 100 < 10 THEN 1
            WHEN ABS(CHECKSUM(NEWID())) % 100 < 40 THEN 2
            ELSE 3
        END                                                         AS Impact,

        -- Source: 40% Portal, 30% Email, 15% Teams, 10% Phone, 5% Walk-up
        CASE
            WHEN ABS(CHECKSUM(NEWID())) % 100 < 40 THEN 1
            WHEN ABS(CHECKSUM(NEWID())) % 100 < 70 THEN 2
            WHEN ABS(CHECKSUM(NEWID())) % 100 < 85 THEN 3
            WHEN ABS(CHECKSUM(NEWID())) % 100 < 95 THEN 4
            ELSE 5
        END                                                         AS Source,

        -- Created date: random within last 90 days
        DATEADD(MINUTE, -(ABS(CHECKSUM(NEWID())) % (90 * 24 * 60)), GETUTCDATE()) AS CreatedOn,

        -- SLA breach: 15%
        CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 15 THEN 1 ELSE 0 END AS SLABreached,

        -- Resolution minutes (for resolved/closed): 30 min to 4320 min (3 days)
        ABS(CHECKSUM(NEWID())) % 4290 + 30                         AS ResolutionMinutes,

        -- First response minutes: 5 to 480 (8 hours)
        ABS(CHECKSUM(NEWID())) % 475 + 5                           AS FirstResponseMinutes,

        -- Satisfaction for resolved/closed (70% have a rating)
        CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 70 THEN
            CASE
                WHEN ABS(CHECKSUM(NEWID())) % 100 < 5  THEN 1
                WHEN ABS(CHECKSUM(NEWID())) % 100 < 15 THEN 2
                WHEN ABS(CHECKSUM(NEWID())) % 100 < 30 THEN 3
                WHEN ABS(CHECKSUM(NEWID())) % 100 < 60 THEN 4
                ELSE 5
            END
        ELSE NULL END                                               AS SatisfactionRating
    FROM Numbers
)
INSERT INTO dbo.TicketFact (
    TicketId, TicketNumber, Title,
    CategoryId, SubcategoryId, DepartmentId,
    RequestedById, AssignedToId,
    Priority, Status, Impact, Urgency, Source,
    SLABreached, SatisfactionRating,
    CreatedOn, ResolvedOn, DueDate, FirstResponseAt,
    SyncedOn, DataverseModifiedOn
)
SELECT
    td.TicketId,
    td.TicketNumber,
    '[SEED] Test ticket #' + CAST(td.N AS VARCHAR(5)),

    -- Category and subcategory from random row
    sc.CategoryId,
    sc.SubcategoryId,

    -- Department
    d.DepartmentId,

    -- RequestedBy (use a deterministic GUID based on N)
    NEWID(),

    -- AssignedTo
    a.AgentId,

    td.Priority,
    td.Status,
    td.Impact,
    td.Priority,  -- Urgency mirrors priority for seed data
    td.Source,
    td.SLABreached,

    -- Satisfaction only for resolved/closed
    CASE WHEN td.Status IN (6, 7) THEN td.SatisfactionRating ELSE NULL END,

    td.CreatedOn,

    -- ResolvedOn only for resolved/closed status
    CASE WHEN td.Status IN (6, 7) THEN DATEADD(MINUTE, td.ResolutionMinutes, td.CreatedOn) ELSE NULL END,

    -- DueDate based on priority SLA
    DATEADD(HOUR,
        CASE td.Priority WHEN 1 THEN 4 WHEN 2 THEN 8 WHEN 3 THEN 24 ELSE 72 END,
        td.CreatedOn),

    -- FirstResponseAt for non-new tickets (80%)
    CASE WHEN td.Status <> 1 AND ABS(CHECKSUM(NEWID())) % 100 < 80
         THEN DATEADD(MINUTE, td.FirstResponseMinutes, td.CreatedOn)
         ELSE NULL END,

    GETUTCDATE(),
    td.CreatedOn  -- DataverseModifiedOn = CreatedOn for seed data

FROM TicketData td
JOIN @Subcategories sc ON sc.RowNum = td.SubcatRow
JOIN @Agents a ON a.RowNum = td.AgentRow
JOIN @Departments d ON d.RowNum = td.DeptRow
WHERE NOT EXISTS (SELECT 1 FROM dbo.TicketFact WHERE TicketNumber = td.TicketNumber);

PRINT 'TicketFact rows inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

COMMIT TRANSACTION;

-- ============================================================
-- 6. Refresh aggregation tables
-- ============================================================
PRINT 'Refreshing aggregation tables...';

EXEC dbo.usp_RefreshTicketVolumeDaily;
PRINT '  TicketVolumeDaily refreshed.';

EXEC dbo.usp_RefreshSLAComplianceMonthly;
PRINT '  SLAComplianceMonthly refreshed.';

EXEC dbo.usp_RefreshAgentPerformanceWeekly;
PRINT '  AgentPerformanceWeekly refreshed.';

-- ============================================================
-- 7. Verify counts
-- ============================================================
PRINT '';
PRINT '=== Seed Data Summary ===';

SELECT 'CategoryDim'            AS TableName, COUNT(*) AS RowCount FROM dbo.CategoryDim
UNION ALL
SELECT 'SubcategoryDim',        COUNT(*) FROM dbo.SubcategoryDim
UNION ALL
SELECT 'DepartmentDim',         COUNT(*) FROM dbo.DepartmentDim
UNION ALL
SELECT 'AgentDim',              COUNT(*) FROM dbo.AgentDim
UNION ALL
SELECT 'TicketFact',            COUNT(*) FROM dbo.TicketFact
UNION ALL
SELECT 'TicketVolumeDaily',     COUNT(*) FROM dbo.TicketVolumeDaily
UNION ALL
SELECT 'SLAComplianceMonthly',  COUNT(*) FROM dbo.SLAComplianceMonthly
UNION ALL
SELECT 'AgentPerformanceWeekly',COUNT(*) FROM dbo.AgentPerformanceWeekly
ORDER BY TableName;

PRINT '';
PRINT 'Seed data generation complete.';
