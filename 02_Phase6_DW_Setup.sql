/* =========================================================
   FILE: 02_Phase6_DW_Setup.sql
   PURPOSE:
     Create the normalized Data Warehouse layer (DW)
     for the Marketing Analytics warehouse.

   CREATES:
     1) dw.dim_date
     2) dw.dim_product
     3) dw.dim_geo
     4) dw.dim_campaign
     5) dw.dim_seller_channel
     6) dw.fact_marketing_daily

   DESIGN PRINCIPLES:
     - Star schema
     - Surrogate keys in SQL Server
     - Source/business keys from Databricks retained as unique natural keys
     - Unknown member = 0 in every dimension
     - Fact contains only dimension keys + measures + lineage columns
     - Power BI-friendly normalized model

   PREREQUISITE:
     01_Phase6_Staging_Setup.sql must already be executed
   ========================================================= */

USE MarketingAnalyticsDW;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* =========================================================
   1) DIM DATE
   NOTE:
     Gold/staging already has date_key and event_date.
     We keep an SSMS surrogate key (date_sk) for consistency,
     and store Gold date_key as source_date_key.
   ========================================================= */
IF OBJECT_ID('dw.dim_date', 'U') IS NULL
BEGIN
    CREATE TABLE dw.dim_date
    (
        date_sk              INT            NOT NULL IDENTITY(1,1),
        source_date_key      INT            NOT NULL,
        full_date            DATE           NOT NULL,

        calendar_year        INT            NULL,
        calendar_quarter     TINYINT        NULL,
        calendar_month       TINYINT        NULL,
        month_name           VARCHAR(20)    NULL,
        month_short_name     VARCHAR(10)    NULL,
        day_of_month         TINYINT        NULL,
        day_of_week          TINYINT        NULL,
        day_name             VARCHAR(20)    NULL,
        week_of_year         TINYINT        NULL,
        is_weekend           BIT            NULL,

        created_ts           DATETIME2(6)   NOT NULL CONSTRAINT DF_dim_date_created_ts DEFAULT (SYSUTCDATETIME()),
        updated_ts           DATETIME2(6)   NOT NULL CONSTRAINT DF_dim_date_updated_ts DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_dim_date PRIMARY KEY (date_sk),
        CONSTRAINT UQ_dim_date_source_date_key UNIQUE (source_date_key),
        CONSTRAINT UQ_dim_date_full_date UNIQUE (full_date)
    );
END
GO

/* Insert Unknown row if missing */
IF NOT EXISTS (SELECT 1 FROM dw.dim_date WHERE date_sk = 0)
BEGIN
    SET IDENTITY_INSERT dw.dim_date ON;

    INSERT INTO dw.dim_date
    (
        date_sk,
        source_date_key,
        full_date,
        calendar_year,
        calendar_quarter,
        calendar_month,
        month_name,
        month_short_name,
        day_of_month,
        day_of_week,
        day_name,
        week_of_year,
        is_weekend
    )
    VALUES
    (
        0,
        0,
        '1900-01-01',
        1900,
        1,
        1,
        'Unknown',
        'UNK',
        1,
        1,
        'Unknown',
        1,
        0
    );

    SET IDENTITY_INSERT dw.dim_date OFF;
END
GO

/* =========================================================
   2) DIM PRODUCT
   NOTE:
     This will be loaded from Databricks Gold dim_product later.
     Structure is designed for normalized product slicing in BI.
   ========================================================= */
IF OBJECT_ID('dw.dim_product', 'U') IS NULL
BEGIN
    CREATE TABLE dw.dim_product
    (
        product_sk           INT            NOT NULL IDENTITY(1,1),
        source_product_key   VARCHAR(128)   NOT NULL,

        brand                VARCHAR(200)   NULL,
        product_name         VARCHAR(300)   NULL,
        pack_size_ml         INT            NULL,
        product_tier         VARCHAR(100)   NULL,
        category             VARCHAR(100)   NULL,

        created_ts           DATETIME2(6)   NOT NULL CONSTRAINT DF_dim_product_created_ts DEFAULT (SYSUTCDATETIME()),
        updated_ts           DATETIME2(6)   NOT NULL CONSTRAINT DF_dim_product_updated_ts DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_dim_product PRIMARY KEY (product_sk),
        CONSTRAINT UQ_dim_product_source_product_key UNIQUE (source_product_key)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM dw.dim_product WHERE product_sk = 0)
BEGIN
    SET IDENTITY_INSERT dw.dim_product ON;

    INSERT INTO dw.dim_product
    (
        product_sk,
        source_product_key,
        brand,
        product_name,
        pack_size_ml,
        product_tier,
        category
    )
    VALUES
    (
        0,
        '0',
        'UNKNOWN',
        'UNKNOWN',
        0,
        'UNKNOWN',
        'UNKNOWN'
    );

    SET IDENTITY_INSERT dw.dim_product OFF;
END
GO

/* =========================================================
   3) DIM GEO
   ========================================================= */
IF OBJECT_ID('dw.dim_geo', 'U') IS NULL
BEGIN
    CREATE TABLE dw.dim_geo
    (
        geo_sk               INT            NOT NULL IDENTITY(1,1),
        source_geo_key       VARCHAR(128)   NOT NULL,

        region_name          VARCHAR(150)   NULL,
        state_name           VARCHAR(150)   NULL,
        city_name            VARCHAR(150)   NULL,

        created_ts           DATETIME2(6)   NOT NULL CONSTRAINT DF_dim_geo_created_ts DEFAULT (SYSUTCDATETIME()),
        updated_ts           DATETIME2(6)   NOT NULL CONSTRAINT DF_dim_geo_updated_ts DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_dim_geo PRIMARY KEY (geo_sk),
        CONSTRAINT UQ_dim_geo_source_geo_key UNIQUE (source_geo_key)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM dw.dim_geo WHERE geo_sk = 0)
BEGIN
    SET IDENTITY_INSERT dw.dim_geo ON;

    INSERT INTO dw.dim_geo
    (
        geo_sk,
        source_geo_key,
        region_name,
        state_name,
        city_name
    )
    VALUES
    (
        0,
        '0',
        'UNKNOWN',
        'UNKNOWN',
        'UNKNOWN'
    );

    SET IDENTITY_INSERT dw.dim_geo OFF;
END
GO

/* =========================================================
   4) DIM CAMPAIGN
   ========================================================= */
IF OBJECT_ID('dw.dim_campaign', 'U') IS NULL
BEGIN
    CREATE TABLE dw.dim_campaign
    (
        campaign_sk          INT            NOT NULL IDENTITY(1,1),
        source_campaign_key  VARCHAR(128)   NOT NULL,

        campaign_name        VARCHAR(250)   NULL,
        campaign_type        VARCHAR(100)   NULL,
        offer_type           VARCHAR(100)   NULL,
        promotion_flag       BIT            NULL,

        created_ts           DATETIME2(6)   NOT NULL CONSTRAINT DF_dim_campaign_created_ts DEFAULT (SYSUTCDATETIME()),
        updated_ts           DATETIME2(6)   NOT NULL CONSTRAINT DF_dim_campaign_updated_ts DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_dim_campaign PRIMARY KEY (campaign_sk),
        CONSTRAINT UQ_dim_campaign_source_campaign_key UNIQUE (source_campaign_key)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM dw.dim_campaign WHERE campaign_sk = 0)
BEGIN
    SET IDENTITY_INSERT dw.dim_campaign ON;

    INSERT INTO dw.dim_campaign
    (
        campaign_sk,
        source_campaign_key,
        campaign_name,
        campaign_type,
        offer_type,
        promotion_flag
    )
    VALUES
    (
        0,
        '0',
        'UNKNOWN',
        'UNKNOWN',
        'UNKNOWN',
        0
    );

    SET IDENTITY_INSERT dw.dim_campaign OFF;
END
GO

/* =========================================================
   5) DIM SELLER CHANNEL
   ========================================================= */
IF OBJECT_ID('dw.dim_seller_channel', 'U') IS NULL
BEGIN
    CREATE TABLE dw.dim_seller_channel
    (
        seller_channel_sk           INT            NOT NULL IDENTITY(1,1),
        source_seller_channel_key   VARCHAR(128)   NOT NULL,

        seller_name                 VARCHAR(250)   NULL,
        platform_source             VARCHAR(100)   NULL,
        sales_channel               VARCHAR(100)   NULL,
        seller_type                 VARCHAR(100)   NULL,

        created_ts                  DATETIME2(6)   NOT NULL CONSTRAINT DF_dim_seller_channel_created_ts DEFAULT (SYSUTCDATETIME()),
        updated_ts                  DATETIME2(6)   NOT NULL CONSTRAINT DF_dim_seller_channel_updated_ts DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_dim_seller_channel PRIMARY KEY (seller_channel_sk),
        CONSTRAINT UQ_dim_seller_channel_source_seller_channel_key UNIQUE (source_seller_channel_key)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM dw.dim_seller_channel WHERE seller_channel_sk = 0)
BEGIN
    SET IDENTITY_INSERT dw.dim_seller_channel ON;

    INSERT INTO dw.dim_seller_channel
    (
        seller_channel_sk,
        source_seller_channel_key,
        seller_name,
        platform_source,
        sales_channel,
        seller_type
    )
    VALUES
    (
        0,
        '0',
        'UNKNOWN',
        'UNKNOWN',
        'UNKNOWN',
        'UNKNOWN'
    );

    SET IDENTITY_INSERT dw.dim_seller_channel OFF;
END
GO

/* =========================================================
   6) FACT TABLE
   NOTE:
     This is the normalized fact table.
     It contains:
       - surrogate foreign keys to dimensions
       - measures
       - lineage columns
     It does NOT store descriptive attributes already present
     in dimensions.
   ========================================================= */
IF OBJECT_ID('dw.fact_marketing_daily', 'U') IS NULL
BEGIN
    CREATE TABLE dw.fact_marketing_daily
    (
        fact_sk                   BIGINT         NOT NULL IDENTITY(1,1),
        batch_id                  BIGINT         NULL,

        fact_row_key              VARCHAR(128)   NOT NULL,
        silver_ingestion_ts       DATETIME2(6)   NOT NULL,
        event_date                DATE           NOT NULL,

        date_sk                   INT            NOT NULL,
        product_sk                INT            NOT NULL,
        geo_sk                    INT            NOT NULL,
        campaign_sk               INT            NOT NULL,
        seller_channel_sk         INT            NOT NULL,

        sales_units               DECIMAL(18,2)  NULL,
        marketing_spend           DECIMAL(18,2)  NULL,
        gross_revenue             DECIMAL(18,2)  NULL,
        total_cost                DECIMAL(18,2)  NULL,
        gross_profit              DECIMAL(18,2)  NULL,
        discount_amount           DECIMAL(18,2)  NULL,
        avg_rating                DECIMAL(10,2)  NULL,
        ratings_count             INT            NULL,
        reviews_count             INT            NULL,
        stock_out_flag            BIT            NULL,
        delivery_days             INT            NULL,
        distributor_count         INT            NULL,
        retailer_count            INT            NULL,
        avg_mrp                   DECIMAL(18,2)  NULL,
        avg_selling_price         DECIMAL(18,2)  NULL,
        avg_cost_price            DECIMAL(18,2)  NULL,
        avg_discount_percent      DECIMAL(10,2)  NULL,
        campaign_revenue          DECIMAL(18,2)  NULL,
        marketing_roi             DECIMAL(18,4)  NULL,
        roas                      DECIMAL(18,4)  NULL,
        cost_per_unit             DECIMAL(18,4)  NULL,
        engagement_rate           DECIMAL(18,4)  NULL,
        campaign_efficiency       DECIMAL(18,4)  NULL,

        created_ts                DATETIME2(6)   NOT NULL CONSTRAINT DF_fact_marketing_daily_created_ts DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_fact_marketing_daily PRIMARY KEY (fact_sk),
        CONSTRAINT UQ_fact_marketing_daily_fact_row_key UNIQUE (fact_row_key)
    );
END
GO

/* =========================================================
   7) FACT FOREIGN KEYS
   ========================================================= */
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_fact_marketing_daily_dim_date'
)
BEGIN
    ALTER TABLE dw.fact_marketing_daily
    ADD CONSTRAINT FK_fact_marketing_daily_dim_date
        FOREIGN KEY (date_sk) REFERENCES dw.dim_date(date_sk);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_fact_marketing_daily_dim_product'
)
BEGIN
    ALTER TABLE dw.fact_marketing_daily
    ADD CONSTRAINT FK_fact_marketing_daily_dim_product
        FOREIGN KEY (product_sk) REFERENCES dw.dim_product(product_sk);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_fact_marketing_daily_dim_geo'
)
BEGIN
    ALTER TABLE dw.fact_marketing_daily
    ADD CONSTRAINT FK_fact_marketing_daily_dim_geo
        FOREIGN KEY (geo_sk) REFERENCES dw.dim_geo(geo_sk);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_fact_marketing_daily_dim_campaign'
)
BEGIN
    ALTER TABLE dw.fact_marketing_daily
    ADD CONSTRAINT FK_fact_marketing_daily_dim_campaign
        FOREIGN KEY (campaign_sk) REFERENCES dw.dim_campaign(campaign_sk);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_fact_marketing_daily_dim_seller_channel'
)
BEGIN
    ALTER TABLE dw.fact_marketing_daily
    ADD CONSTRAINT FK_fact_marketing_daily_dim_seller_channel
        FOREIGN KEY (seller_channel_sk) REFERENCES dw.dim_seller_channel(seller_channel_sk);
END
GO

/* =========================================================
   8) FACT CHECK CONSTRAINTS
   NOTE:
     Keep them realistic so valid business data does not fail.
   ========================================================= */
IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_fact_marketing_daily_nonnegative_core'
)
BEGIN
    ALTER TABLE dw.fact_marketing_daily
    ADD CONSTRAINT CK_fact_marketing_daily_nonnegative_core
    CHECK
    (
        (sales_units IS NULL OR sales_units >= 0) AND
        (marketing_spend IS NULL OR marketing_spend >= 0) AND
        (gross_revenue IS NULL OR gross_revenue >= 0) AND
        (total_cost IS NULL OR total_cost >= 0) AND
        (discount_amount IS NULL OR discount_amount >= 0) AND
        (ratings_count IS NULL OR ratings_count >= 0) AND
        (reviews_count IS NULL OR reviews_count >= 0) AND
        (delivery_days IS NULL OR delivery_days >= 0) AND
        (distributor_count IS NULL OR distributor_count >= 0) AND
        (retailer_count IS NULL OR retailer_count >= 0) AND
        (avg_mrp IS NULL OR avg_mrp >= 0) AND
        (avg_selling_price IS NULL OR avg_selling_price >= 0) AND
        (avg_cost_price IS NULL OR avg_cost_price >= 0) AND
        (avg_discount_percent IS NULL OR avg_discount_percent >= 0) AND
        (campaign_revenue IS NULL OR campaign_revenue >= 0) AND
        (roas IS NULL OR roas >= 0) AND
        (cost_per_unit IS NULL OR cost_per_unit >= 0) AND
        (engagement_rate IS NULL OR engagement_rate >= 0) AND
        (campaign_efficiency IS NULL OR campaign_efficiency >= 0)
    );
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_fact_marketing_daily_rating_range'
)
BEGIN
    ALTER TABLE dw.fact_marketing_daily
    ADD CONSTRAINT CK_fact_marketing_daily_rating_range
    CHECK
    (
        avg_rating IS NULL OR (avg_rating >= 0 AND avg_rating <= 5)
    );
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_fact_marketing_daily_stock_out_flag'
)
BEGIN
    ALTER TABLE dw.fact_marketing_daily
    ADD CONSTRAINT CK_fact_marketing_daily_stock_out_flag
    CHECK
    (
        stock_out_flag IS NULL OR stock_out_flag IN (0,1)
    );
END
GO

/* =========================================================
   9) CORE INDEXES
   ========================================================= */
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_fact_marketing_daily_batch_id'
      AND object_id = OBJECT_ID('dw.fact_marketing_daily')
)
BEGIN
    CREATE INDEX IX_fact_marketing_daily_batch_id
        ON dw.fact_marketing_daily(batch_id);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_fact_marketing_daily_silver_ingestion_ts'
      AND object_id = OBJECT_ID('dw.fact_marketing_daily')
)
BEGIN
    CREATE INDEX IX_fact_marketing_daily_silver_ingestion_ts
        ON dw.fact_marketing_daily(silver_ingestion_ts);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_fact_marketing_daily_dim_keys'
      AND object_id = OBJECT_ID('dw.fact_marketing_daily')
)
BEGIN
    CREATE INDEX IX_fact_marketing_daily_dim_keys
        ON dw.fact_marketing_daily(date_sk, product_sk, geo_sk, campaign_sk, seller_channel_sk);
END
GO

/* =========================================================
   10) SMOKE TEST
   ========================================================= */
SELECT 'DW Layer Ready' AS msg, DB_NAME() AS current_db;
SELECT TOP 5 * FROM dw.dim_date ORDER BY date_sk;
SELECT TOP 5 * FROM dw.dim_product ORDER BY product_sk;
SELECT TOP 5 * FROM dw.dim_geo ORDER BY geo_sk;
SELECT TOP 5 * FROM dw.dim_campaign ORDER BY campaign_sk;
SELECT TOP 5 * FROM dw.dim_seller_channel ORDER BY seller_channel_sk;
SELECT TOP 5 * FROM dw.fact_marketing_daily ORDER BY fact_sk DESC;
GO