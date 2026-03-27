-- Migration 001: Add SyncState table for Dataverse change tracking tokens
-- Referenced by DataverseSyncService to persist delta sync tokens between runs

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'SyncState')
CREATE TABLE dbo.SyncState (
    EntityName  NVARCHAR(100)   NOT NULL PRIMARY KEY,
    TokenValue  NVARCHAR(MAX)   NOT NULL,
    LastSyncUtc DATETIME2       NOT NULL DEFAULT GETUTCDATE()
);
GO
