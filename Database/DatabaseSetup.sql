IF DB_ID(N'BI_Database_RawAndStaging') IS NULL
BEGIN
	CREATE DATABASE [BI_Database_RawAndStaging];
END
GO

IF DB_ID(N'BI_Database_DimFact') IS NULL
BEGIN
	CREATE DATABASE [BI_Database_DimFact];
END
GO

-- =========================================
-- 2. RAW + STAGING adatbázis
-- =========================================

USE [BI_Database_RawAndStaging];
GO
-----------------
--DELETE TABLES--
-----------------
DROP TABLE IF EXISTS [dbo].[STGnewsCategory];
DROP TABLE IF EXISTS [dbo].[RAWcurrencies];
DROP TABLE IF EXISTS [dbo].[RAWexchange];
DROP TABLE IF EXISTS [dbo].[RAWnews];

--------------
--RAW TABLES--
--------------
CREATE TABLE RAWcurrencies (
    CurrencyID INT IDENTITY(1,1) PRIMARY KEY,
    APIfetchedAt DATE NOT NULL,
    ProcessedFlag bit NOT NULL DEFAULT 0,
    Iso_code CHAR(3) NOT NULL UNIQUE,
    Iso_numeric CHAR(3) NULL,
    [Name] NVARCHAR(100) NOT NULL,
    Symbol NVARCHAR(10),
    [Start_date] DATE,
    [End_date] DATE
);

CREATE TABLE RAWexchange (
    ExchangeID INT IDENTITY(1,1) PRIMARY KEY,
    APIfetchedAt DATE NOT NULL,
    ProcessedFlag bit NOT NULL DEFAULT 0,
    BaseCurrency CHAR(3) NOT NULL,
    Currency CHAR(3) NOT NULL,
    Rate DECIMAL(18,6) NOT NULL,
    [Date] DATE NOT NULL,

    CONSTRAINT UQ_RAWexchange_Date_BaseCurrency_Currency
        UNIQUE ([Date], BaseCurrency, Currency)
);

CREATE TABLE RAWnews (
    ArticleID INT IDENTITY(1,1) PRIMARY KEY,
    APIfetchedAt DATE NOT NULL,
    ProcessedFlag bit NOT NULL DEFAULT 0,
    Source_id NVARCHAR(1000),
    Source_name NVARCHAR(1000),
    Author NVARCHAR(1000),
    Title NVARCHAR(1000),
    [Description] NVARCHAR(1000),
    [Url] NVARCHAR(2000) UNIQUE,
    [UrlToImage] NVARCHAR(2000),
    [PublishedAt] DATETIME NOT NULL,
    [Content] NVARCHAR(1000)
);

------------------
-- Staging TABLE--
------------------

CREATE TABLE STGnewsCategory (
    RAWArticleID INT PRIMARY KEY,
    GeneratedCategory NVARCHAR(300),

    CONSTRAINT FK_STGnewsCategory_RAWnews
        FOREIGN KEY (RAWArticleID)
        REFERENCES RAWnews(ArticleID)
);

-----------------------
-- RAW TABLE INDEXES --
-----------------------
-- RAWexchange
CREATE INDEX IX_RAWexchange_ProcessedFlag
ON RAWexchange (ProcessedFlag);	

-- RAWnews
CREATE INDEX IX_RAWnews_ProcessedFlag
ON RAWnews (ProcessedFlag);

CREATE INDEX IX_RAWnews_Source
ON RAWnews (Source_id, Source_name);


-- =========================================
-- 3. DIM + FACT adatbázis
-- =========================================

USE [BI_Database_DimFact];
GO

-----------------
--DELETE TABLES--
-----------------
-- VIEWS
DROP VIEW IF EXISTS dbo.vw_DimBaseCurrency;
DROP VIEW IF EXISTS dbo.vw_DimTargetCurrency;
GO

-- FACTS
DROP TABLE IF EXISTS dbo.FactNews;
DROP TABLE IF EXISTS dbo.FactExchange;

-- DIMS
DROP TABLE IF EXISTS dbo.DimCategory;
DROP TABLE IF EXISTS dbo.DimAuthor;
DROP TABLE IF EXISTS dbo.DimSource;
DROP TABLE IF EXISTS dbo.DimCurrency;
DROP TABLE IF EXISTS dbo.DimDate;
GO

-----------------------
-- DIMENSIONAL TABLES--
-----------------------
CREATE TABLE DimDate (
    DateID INT IDENTITY(1,1) PRIMARY KEY,
    [Date] DATE NOT NULL,  
    [Year] INT NOT NULL,
    [Month] INT NOT NULL,
    [Day] INT NOT NULL
);
GO

CREATE TABLE DimCurrency (
    CurrencyID INT IDENTITY(1,1) PRIMARY KEY,
    CurrencyCode CHAR(3) NOT NULL UNIQUE,
    CurrencyName NVARCHAR(100) NULL,
    CurrencySymbol NVARCHAR(10) NULL
);
GO

CREATE TABLE DimSource (
    SourceID INT IDENTITY(1,1) PRIMARY KEY,
    SourceName NVARCHAR(1000) NOT NULL UNIQUE
);
GO

CREATE TABLE DimAuthor (
    AuthorID INT IDENTITY(1,1) PRIMARY KEY,
    AuthorName NVARCHAR(1000) NOT NULL
);
GO

CREATE TABLE DimCategory (
    CategoryID INT IDENTITY(1,1) PRIMARY KEY,
    CategoryName NVARCHAR(300) NOT NULL UNIQUE
);
GO

---------------
--FACT TABLES--
---------------
CREATE TABLE FactExchange (
    ExchangeID INT IDENTITY(1,1) PRIMARY KEY,

    DateID INT NOT NULL,
    BaseCurrencyID INT NOT NULL,
    CurrencyID INT NOT NULL,

    Rate DECIMAL(18,6) NOT NULL,

    CONSTRAINT FK_FactExchange_Date
        FOREIGN KEY (DateID) REFERENCES DimDate(DateID),

    CONSTRAINT FK_FactExchange_BaseCurrency
        FOREIGN KEY (BaseCurrencyID) REFERENCES DimCurrency(CurrencyID),

    CONSTRAINT FK_FactExchange_Currency
        FOREIGN KEY (CurrencyID) REFERENCES DimCurrency(CurrencyID),

    CONSTRAINT UQ_FactExchange_Date_BaseCurrency_Currency
        UNIQUE ([DateID], BaseCurrencyID, CurrencyID)
);
GO

CREATE TABLE FactNews (
    NewsID INT IDENTITY(1,1) PRIMARY KEY,

    DateID INT NOT NULL,
    SourceID INT NOT NULL,
    AuthorID INT NOT NULL,
    CategoryID INT NOT NULL,

    Title NVARCHAR(1000) NOT NULL,
    [Url] NVARCHAR(2000) NOT NULL UNIQUE,

    CONSTRAINT FK_FactNews_Date
        FOREIGN KEY (DateID) REFERENCES DimDate(DateID),

    CONSTRAINT FK_FactNews_Source
        FOREIGN KEY (SourceID) REFERENCES DimSource(SourceID),

    CONSTRAINT FK_FactNews_Author
        FOREIGN KEY (AuthorID) REFERENCES DimAuthor(AuthorID),

    CONSTRAINT FK_FactNews_Category
        FOREIGN KEY (CategoryID) REFERENCES DimCategory(CategoryID)
);
GO

-----------------------
-- DIM TABLE INDEXES --
-----------------------
-- DimDate
CREATE UNIQUE INDEX UX_DimDate_Date
ON DimDate ([Date]);

CREATE INDEX IX_DimDate_YearMonth
ON DimDate ([Year], [Month]);

-- DimAuthor
CREATE INDEX IX_DimAuthor_Name
ON DimAuthor (AuthorName);

------------------------
-- FACT TABLE INDEXES --
------------------------
-- FactExchange
CREATE INDEX IX_FactExchange_CurrencyLookup
ON FactExchange (BaseCurrencyID, CurrencyID);

-- FactNews
CREATE INDEX IX_FactNews_Source
ON FactNews (SourceID);

CREATE INDEX IX_FactNews_Author
ON FactNews (AuthorID);

CREATE INDEX IX_FactNews_Category
ON FactNews (CategoryID);

CREATE INDEX IX_FactNews_DimCombo
ON FactNews (DateID, SourceID, CategoryID);
GO

---------
--VIEWS--
---------
CREATE VIEW dbo.vw_DimBaseCurrency AS
SELECT CurrencyID AS BaseCurrencyID, CurrencyCode, CurrencyName, CurrencySymbol
FROM dbo.DimCurrency;
GO

CREATE VIEW dbo.vw_DimTargetCurrency AS
SELECT CurrencyID AS TargetCurrencyID, CurrencyCode, CurrencyName, CurrencySymbol
FROM dbo.DimCurrency;
GO