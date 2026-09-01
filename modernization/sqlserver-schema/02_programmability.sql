USE Scoreboard;
GO

CREATE OR ALTER TRIGGER dbo.trg_Captures_Audit
ON dbo.Captures
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.CaptureAudit (CaptureId, TeamId, Points, RecordedUtc)
    SELECT i.CaptureId,
           i.TeamId,
           f.Points,
           SYSUTCDATETIME()
    FROM inserted AS i
    JOIN dbo.Flags AS f ON f.FlagValue = i.FlagValue;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_UpsertTeam
    @Name        NVARCHAR(64),
    @CountryCode CHAR(2) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.Teams AS tgt
    USING (SELECT @Name AS Name, @CountryCode AS CountryCode) AS src
    ON tgt.Name = src.Name
    WHEN MATCHED THEN
        UPDATE SET CountryCode = src.CountryCode
    WHEN NOT MATCHED THEN
        INSERT (Name, CountryCode) VALUES (src.Name, src.CountryCode);

    SELECT TeamId FROM dbo.Teams WHERE Name = @Name;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_RecordCapture
    @TeamId    INT,
    @FlagValue NVARCHAR(64),
    @SourceIp  VARCHAR(45),
    @NewScore  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Points INT;
    SELECT @Points = Points FROM dbo.Flags WHERE FlagValue = @FlagValue AND IsActive = 1;

    IF @Points IS NULL
    BEGIN
        SET @NewScore = -1;
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM dbo.Captures WHERE TeamId = @TeamId AND FlagValue = @FlagValue)
    BEGIN
        SELECT @NewScore = Score FROM dbo.Teams WHERE TeamId = @TeamId;
        RETURN;
    END;

    BEGIN TRAN;
        INSERT INTO dbo.Captures (TeamId, FlagValue, SourceIp)
        VALUES (@TeamId, @FlagValue, @SourceIp);

        UPDATE dbo.Teams
        SET Score = Score + @Points,
            LastCaptureUtc = SYSUTCDATETIME()
        WHERE TeamId = @TeamId;

        SELECT @NewScore = Score FROM dbo.Teams WHERE TeamId = @TeamId;
    COMMIT TRAN;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_RecalculateRanks
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TeamId INT, @Rank INT = 0;
    DECLARE rank_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT TeamId
        FROM dbo.Teams
        WHERE IsDisqualified = 0
        ORDER BY Score DESC, LastCaptureUtc ASC;

    IF OBJECT_ID('dbo.TeamRank') IS NULL
        CREATE TABLE dbo.TeamRank (TeamId INT PRIMARY KEY, Rank INT NOT NULL);

    TRUNCATE TABLE dbo.TeamRank;

    OPEN rank_cur;
    FETCH NEXT FROM rank_cur INTO @TeamId;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Rank += 1;
        INSERT INTO dbo.TeamRank (TeamId, Rank) VALUES (@TeamId, @Rank);
        FETCH NEXT FROM rank_cur INTO @TeamId;
    END;
    CLOSE rank_cur;
    DEALLOCATE rank_cur;
END;
GO

CREATE OR ALTER VIEW dbo.vw_Leaderboard
AS
    SELECT TOP (25) WITH TIES
           t.TeamId,
           t.Name,
           t.Score,
           t.RankBucket,
           COUNT(c.CaptureId) AS Captures,
           DATEDIFF(MINUTE, MIN(c.CapturedUtc), MAX(c.CapturedUtc)) AS ActiveMinutes
    FROM dbo.Teams AS t
    LEFT JOIN dbo.Captures AS c ON c.TeamId = t.TeamId
    WHERE t.IsDisqualified = 0
    GROUP BY t.TeamId, t.Name, t.Score, t.RankBucket
    ORDER BY t.Score DESC;
GO
