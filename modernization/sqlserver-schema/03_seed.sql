USE Scoreboard;
GO

SET IDENTITY_INSERT dbo.Flags ON;
INSERT INTO dbo.Flags (FlagId, FlagValue, Category, Points, IsActive) VALUES
    (1, N'FLG-WEB-XSS-01',   N'web',      150, 1),
    (2, N'FLG-WEB-SQLI-0',   N'web',       75, 1),
    (3, N'FLG-CRYPTO-RSA',   N'crypto',    50, 1),
    (4, N'FLG-CRYPTO-AES',   N'crypto',    60, 1),
    (5, N'FLG-PWN-STACK-',   N'pwn',       35, 1),
    (6, N'FLG-PWN-HEAP--',   N'pwn',      120, 1),
    (7, N'FLG-REV-UNPACK',   N'rev',       90, 1),
    (8, N'FLG-MISC-OSINT',   N'misc',      25, 1),
    (9, N'FLG-FORENSIC-1',   N'forensic', 100, 1);
SET IDENTITY_INSERT dbo.Flags OFF;
GO

EXEC dbo.usp_UpsertTeam @Name = N'null-terminators', @CountryCode = 'CO';
EXEC dbo.usp_UpsertTeam @Name = N'segfault-supremacy', @CountryCode = 'US';
EXEC dbo.usp_UpsertTeam @Name = N'the-cache-money',   @CountryCode = 'CA';
GO
