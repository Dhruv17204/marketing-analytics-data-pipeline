/* =========================================================
   FILE: 01_Phase6_Staging_Setup.sql
   PURPOSE:
     One-time setup for the SSMS warehouse foundation.

     Creates:
       1) Database
       2) Schemas: stg, dw, etl, mart
       3) ETL control tables
       4) Staging table for incremental Databricks Gold load

   STRATEGY ALIGNMENT:
     Databricks Gold
       -> stg.fact_marketing_daily_inc
       -> dw layer
       -> semantic views
       -> Power BI

   NOTES:
     - Run once during initial setup
     - Daily execution should happen through stored procedures/runbook
   ========================================================= */

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* =========================================================
   1) CREATE DATABASE
   ========================================================= */
IF DB_ID('MarketingAnalyticsDW') IS NULL
BEGIN
    CREATE DATABASE MarketingAnalyticsDW;
END
GO

USE MarketingAnalyticsDW;
GO

/* =========================================================
   2) CREATE SCHEMAS
   ========================================================= */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'stg')
    EXEC('CREATE SCHEMA stg');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'dw')
    EXEC('CREATE SCHEMA dw');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'etl')
    EXEC('CREATE SCHEMA etl');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'mart')
    EXEC('CREATE SCHEMA mart');
GO

/* =========================================================
   3) ETL CONTROL TABLE: WATERMARK
   PURPOSE:
     Tracks last successfully loaded Gold timestamp
   ========================================================= */
IF OBJECT_ID('etl.WatermarkControl', 'U') IS NULL
BEGIN
    CREATE TABLE etl.WatermarkControl
    (
        pipeline_name         VARCHAR(200)   NOT NULL,
        source_object         VARCHAR(300)   NOT NULL,
        watermark_column      VARCHAR(128)   NOT NULL,
        last_loaded_ts        DATETIME2(6)   NULL,
        is_active             BIT            NOT NULL CONSTRAINT DF_WatermarkControl_is_active DEFAULT (1),
        created_ts            DATETIME2(6)   NOT NULL CONSTRAINT DF_WatermarkControl_created_ts DEFAULT (SYSUTCDATETIME()),
        updated_ts            DATETIME2(6)   NOT NULL CONSTRAINT DF_WatermarkControl_updated_ts DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_WatermarkControl PRIMARY KEY (pipeline_name)
    );
END
GO

/* Seed watermark row only once */
IF NOT EXISTS (
    SELECT 1
    FROM etl.WatermarkControl
    WHERE pipeline_name = 'MarketingDW_Gold_To_SSMS'
)
BEGIN
    INSERT INTO etl.WatermarkControl
    (
        pipeline_name,
        source_object,
        watermark_column,
        last_loaded_ts,
        is_active
    )
    VALUES
    (
        'MarketingDW_Gold_To_SSMS',
        'workspace.water_bottle_db.fact_marketing_daily',
        'silver_ingestion_ts',
        NULL,
        1
    );
END
GO

/* =========================================================
   4) ETL CONTROL TABLE: BATCH LOG
   PURPOSE:
     Logs every pipeline run for audit and failure tracing
   ========================================================= */
IF OBJECT_ID('etl.BatchLoadLog', 'U') IS NULL
BEGIN
    CREATE TABLE etl.BatchLoadLog
    (
        batch_id              BIGINT         IDENTITY(1,1) NOT NULL,
        pipeline_name         VARCHAR(200)   NOT NULL,
        runbook_name          VARCHAR(200)   NULL,
        source_object         VARCHAR(300)   NULL,

        start_ts              DATETIME2(6)   NOT NULL,
        end_ts                DATETIME2(6)   NULL,

        watermark_before      DATETIME2(6)   NULL,
        watermark_after       DATETIME2(6)   NULL,

        rows_staged           INT            NULL,
        rows_inserted_dw      INT            NULL,
        rows_rejected         INT            NULL,

        status                VARCHAR(20)    NOT NULL, -- STARTED / SUCCESS / FAILED
        error_message         NVARCHAR(4000) NULL,

        created_ts            DATETIME2(6)   NOT NULL CONSTRAINT DF_BatchLoadLog_created_ts DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_BatchLoadLog PRIMARY KEY (batch_id),
        CONSTRAINT CK_BatchLoadLog_status CHECK (status IN ('STARTED', 'SUCCESS', 'FAILED'))
    );
END
GO

/* =========================================================
   5) STAGING TABLE
   PURPOSE:
     Temporary landing zone for only the latest incremental batch
     from Databricks Gold.
   DESIGN:
     - No business logic here
     - Preserve source keys and measures exactly as received
     - Keep fact_row_key for deduplication downstream
   ========================================================= */
IF OBJECT_ID('stg.fact_marketing_daily_inc', 'U') IS NULL
BEGIN
    CREATE TABLE stg.fact_marketing_daily_inc
    (
        stg_load_id              BIGINT         IDENTITY(1,1) NOT NULL,
        batch_id                 BIGINT         NULL,

        fact_row_key             VARCHAR(128)   NOT NULL,
        silver_ingestion_ts      DATETIME2(6)   NOT NULL,
        event_date               DATE           NOT NULL,

        date_key                 INT            NOT NULL,
        product_key              VARCHAR(128)   NOT NULL,
        geo_key                  VARCHAR(128)   NOT NULL,
        campaign_key             VARCHAR(128)   NOT NULL,
        seller_channel_key       VARCHAR(128)   NOT NULL,

        sales_units              DECIMAL(18,2)  NULL,
        marketing_spend          DECIMAL(18,2)  NULL,
        gross_revenue            DECIMAL(18,2)  NULL,
        total_cost               DECIMAL(18,2)  NULL,
        gross_profit             DECIMAL(18,2)  NULL,
        discount_amount          DECIMAL(18,2)  NULL,
        avg_rating               DECIMAL(10,2)  NULL,
        ratings_count            INT            NULL,
        reviews_count            INT            NULL,
        stock_out_flag           BIT            NULL,
        delivery_days            INT            NULL,
        distributor_count        INT            NULL,
        retailer_count           INT            NULL,
        avg_mrp                  DECIMAL(18,2)  NULL,
        avg_selling_price        DECIMAL(18,2)  NULL,
        avg_cost_price           DECIMAL(18,2)  NULL,
        avg_discount_percent     DECIMAL(10,2)  NULL,
        campaign_revenue         DECIMAL(18,2)  NULL,
        marketing_roi            DECIMAL(18,4)  NULL,
        roas                     DECIMAL(18,4)  NULL,
        cost_per_unit            DECIMAL(18,4)  NULL,
        engagement_rate          DECIMAL(18,4)  NULL,
        campaign_efficiency      DECIMAL(18,4)  NULL,

        stg_loaded_ts            DATETIME2(6)   NOT NULL CONSTRAINT DF_stg_fact_marketing_daily_inc_stg_loaded_ts DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_stg_fact_marketing_daily_inc PRIMARY KEY (stg_load_id)
    );
END
GO

/* =========================================================
   6) STAGING INDEXES
   PURPOSE:
     Speed up batch validation, dedup checks, and downstream loads
   ========================================================= */
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_stg_fact_marketing_daily_inc_batch_id'
      AND object_id = OBJECT_ID('stg.fact_marketing_daily_inc')
)
BEGIN
    CREATE INDEX IX_stg_fact_marketing_daily_inc_batch_id
        ON stg.fact_marketing_daily_inc(batch_id);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_stg_fact_marketing_daily_inc_fact_row_key'
      AND object_id = OBJECT_ID('stg.fact_marketing_daily_inc')
)
BEGIN
    CREATE INDEX IX_stg_fact_marketing_daily_inc_fact_row_key
        ON stg.fact_marketing_daily_inc(fact_row_key);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_stg_fact_marketing_daily_inc_silver_ingestion_ts'
      AND object_id = OBJECT_ID('stg.fact_marketing_daily_inc')
)
BEGIN
    CREATE INDEX IX_stg_fact_marketing_daily_inc_silver_ingestion_ts
        ON stg.fact_marketing_daily_inc(silver_ingestion_ts);
END
GO

/* =========================================================
   7) OPTIONAL HELPER VIEW FOR LATEST WATERMARK
   ========================================================= */
IF OBJECT_ID('etl.vw_CurrentWatermark', 'V') IS NOT NULL
    DROP VIEW etl.vw_CurrentWatermark;
GO

CREATE VIEW etl.vw_CurrentWatermark
AS
SELECT
    pipeline_name,
    source_object,
    watermark_column,
    last_loaded_ts,
    is_active,
    created_ts,
    updated_ts
FROM etl.WatermarkControl
WHERE is_active = 1;
GO

/* =========================================================
   8) SMOKE TEST
   ========================================================= */
SELECT 'Database Ready' AS msg, DB_NAME() AS current_db;
SELECT * FROM etl.WatermarkControl;
SELECT TOP 5 * FROM etl.BatchLoadLog ORDER BY batch_id DESC;
SELECT TOP 5 * FROM stg.fact_marketing_daily_inc ORDER BY stg_load_id DESC;
GO