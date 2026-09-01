/* Scoreboard OLTP schema - SQL Server 2017. Source for Transform / DMS schema
   conversion to Aurora PostgreSQL. */

IF DB_ID('Scoreboard') IS NULL
    CREATE DATABASE Scoreboard;
GO
USE Scoreboard;
GO

CREATE SEQUENCE dbo.EventSeq AS BIGINT START WITH 1 INCREMENT BY 1;
GO

CREATE FUNCTION dbo.fn_RankBucket (@score INT)
RETURNS NVARCHAR(16)
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE
        WHEN @score >= 1000 THEN N'gold'
        WHEN @score >= 250  THEN N'silver'
        WHEN @score > 0     THEN N'bronze'
        ELSE N'unranked'
    END;
END;
GO

CREATE TABLE dbo.Teams
(
    TeamId          INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    Name            NVARCHAR(64)      NOT NULL,
    CountryCode     CHAR(2)           NULL,
    Score           INT               NOT NULL CONSTRAINT DF_Teams_Score DEFAULT (0),
    RankBucket      AS (dbo.fn_RankBucket(Score)) PERSISTED,
    IsDisqualified  BIT               NOT NULL CONSTRAINT DF_Teams_DQ DEFAULT (0),
    LastCaptureUtc  DATETIME2(3)      NULL,
    CreatedUtc      DATETIME2(3)      NOT NULL CONSTRAINT DF_Teams_Created DEFAULT (SYSUTCDATETIME())
);
GO

CREATE UNIQUE INDEX UX_Teams_Name ON dbo.Teams (Name);
GO

CREATE TABLE dbo.Flags
(
    FlagId      INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    FlagValue   NVARCHAR(64)      NOT NULL UNIQUE,
    Category    NVARCHAR(32)      NOT NULL,
    Points      INT               NOT NULL,
    IsActive    BIT               NOT NULL CONSTRAINT DF_Flags_Active DEFAULT (1)
);
GO

CREATE TABLE dbo.Captures
(
    CaptureId    BIGINT           NOT NULL PRIMARY KEY
                     CONSTRAINT DF_Captures_Id DEFAULT (NEXT VALUE FOR dbo.EventSeq),
    TeamId       INT              NOT NULL REFERENCES dbo.Teams (TeamId),
    FlagValue    NVARCHAR(64)     NOT NULL,
    SourceIp     VARCHAR(45)      NULL,
    CapturedUtc  DATETIME2(3)     NOT NULL CONSTRAINT DF_Captures_Ts DEFAULT (SYSUTCDATETIME())
);
GO

CREATE INDEX IX_Captures_Team ON dbo.Captures (TeamId, CapturedUtc);
GO

CREATE TABLE dbo.CaptureAudit
(
    AuditId      BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CaptureId    BIGINT               NOT NULL,
    TeamId       INT                  NOT NULL,
    Points       INT                  NOT NULL,
    RecordedUtc  DATETIME2(3)         NOT NULL CONSTRAINT DF_Audit_Ts DEFAULT (SYSUTCDATETIME())
);
GO
