USE MarketingAnalyticsDW;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* =========================================================
   FILE: 04_DW_Performance_Indexing.sql
   PURPOSE:
     One-time performance optimization for the Marketing DW.

   OBJECTIVE:
     Improve:
     - fact-to-dimension joins
     - Power BI query speed
     - filtering on date/product/geo/campaign/seller
     - incremental ETL lookup performance

   NOTES:
     - Run once after DW + ETL procedures are created
     - Do NOT run daily in the runbook
     - Uses current rebuilt warehouse schema
   ========================================================= */


/* =========================================================
   1) DIMENSION LOOKUP INDEXES
   PURPOSE:
     Speed up source-key to surrogate-key mapping during fact load
   ========================================================= */

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_dim_date_source_date_key'
      AND object_id = OBJECT_ID('dw.dim_date')
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX IX_dim_date_source_date_key
        ON dw.dim_date(source_date_key);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_dim_product_source_product_key'
      AND object_id = OBJECT_ID('dw.dim_product')
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX IX_dim_product_source_product_key
        ON dw.dim_product(source_product_key);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_dim_geo_source_geo_key'
      AND object_id = OBJECT_ID('dw.dim_geo')
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX IX_dim_geo_source_geo_key
        ON dw.dim_geo(source_geo_key);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_dim_campaign_source_campaign_key'
      AND object_id = OBJECT_ID('dw.dim_campaign')
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX IX_dim_campaign_source_campaign_key
        ON dw.dim_campaign(source_campaign_key);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_dim_seller_channel_source_key'
      AND object_id = OBJECT_ID('dw.dim_seller_channel')
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX IX_dim_seller_channel_source_key
        ON dw.dim_seller_channel(source_seller_channel_key);
END
GO


/* =========================================================
   2) FACT TABLE ANALYTICS INDEXES
   PURPOSE:
     Improve Power BI slicing, joins, and common aggregations
   ========================================================= */

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_fact_marketing_daily_date_sk'
      AND object_id = OBJECT_ID('dw.fact_marketing_daily')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_marketing_daily_date_sk
        ON dw.fact_marketing_daily(date_sk)
        INCLUDE (gross_revenue, gross_profit, marketing_spend, sales_units, campaign_revenue);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_fact_marketing_daily_product_sk'
      AND object_id = OBJECT_ID('dw.fact_marketing_daily')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_marketing_daily_product_sk
        ON dw.fact_marketing_daily(product_sk)
        INCLUDE (gross_revenue, gross_profit, marketing_spend, sales_units, campaign_revenue);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_fact_marketing_daily_geo_sk'
      AND object_id = OBJECT_ID('dw.fact_marketing_daily')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_marketing_daily_geo_sk
        ON dw.fact_marketing_daily(geo_sk)
        INCLUDE (gross_revenue, gross_profit, marketing_spend, sales_units, campaign_revenue);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_fact_marketing_daily_campaign_sk'
      AND object_id = OBJECT_ID('dw.fact_marketing_daily')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_marketing_daily_campaign_sk
        ON dw.fact_marketing_daily(campaign_sk)
        INCLUDE (gross_revenue, gross_profit, marketing_spend, sales_units, campaign_revenue, marketing_roi, roas);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_fact_marketing_daily_seller_channel_sk'
      AND object_id = OBJECT_ID('dw.fact_marketing_daily')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_marketing_daily_seller_channel_sk
        ON dw.fact_marketing_daily(seller_channel_sk)
        INCLUDE (gross_revenue, gross_profit, marketing_spend, sales_units, campaign_revenue);
END
GO


/* =========================================================
   3) FACT TABLE ETL / INCREMENTAL INDEXES
   PURPOSE:
     Support deduplication, watermark-based loads, and batch tracing
   ========================================================= */

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_fact_marketing_daily_fact_row_key'
      AND object_id = OBJECT_ID('dw.fact_marketing_daily')
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX IX_fact_marketing_daily_fact_row_key
        ON dw.fact_marketing_daily(fact_row_key);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_fact_marketing_daily_silver_ingestion_ts'
      AND object_id = OBJECT_ID('dw.fact_marketing_daily')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_marketing_daily_silver_ingestion_ts
        ON dw.fact_marketing_daily(silver_ingestion_ts);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_fact_marketing_daily_batch_id'
      AND object_id = OBJECT_ID('dw.fact_marketing_daily')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_marketing_daily_batch_id
        ON dw.fact_marketing_daily(batch_id);
END
GO


/* =========================================================
   4) STAGING TABLE INDEXES
   PURPOSE:
     Support staging validation, batch filtering, and downstream joins
   ========================================================= */

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_stg_fact_marketing_daily_inc_batch_id'
      AND object_id = OBJECT_ID('stg.fact_marketing_daily_inc')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_stg_fact_marketing_daily_inc_batch_id
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
    CREATE NONCLUSTERED INDEX IX_stg_fact_marketing_daily_inc_fact_row_key
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
    CREATE NONCLUSTERED INDEX IX_stg_fact_marketing_daily_inc_silver_ingestion_ts
        ON stg.fact_marketing_daily_inc(silver_ingestion_ts);
END
GO


/* =========================================================
   5) ETL CONTROL TABLE INDEXES
   PURPOSE:
     Faster run history and operational monitoring
   ========================================================= */

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_BatchLoadLog_pipeline_name_start_ts'
      AND object_id = OBJECT_ID('etl.BatchLoadLog')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_BatchLoadLog_pipeline_name_start_ts
        ON etl.BatchLoadLog(pipeline_name, start_ts DESC);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_BatchLoadLog_status_start_ts'
      AND object_id = OBJECT_ID('etl.BatchLoadLog')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_BatchLoadLog_status_start_ts
        ON etl.BatchLoadLog(status, start_ts DESC);
END
GO


/* =========================================================
   6) OPTIONAL COMPOSITE BI INDEX
   PURPOSE:
     Helpful for common dashboard queries with date + dimensions
   ========================================================= */
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_fact_marketing_daily_bi_composite'
      AND object_id = OBJECT_ID('dw.fact_marketing_daily')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_marketing_daily_bi_composite
        ON dw.fact_marketing_daily(date_sk, product_sk, geo_sk, campaign_sk, seller_channel_sk)
        INCLUDE (gross_revenue, gross_profit, marketing_spend, sales_units, campaign_revenue, marketing_roi, roas);
END
GO


/* =========================================================
   7) INDEX VALIDATION
   PURPOSE:
     Show created indexes for verification
   ========================================================= */
SELECT
    SCHEMA_NAME(t.schema_id) AS schema_name,
    t.name AS table_name,
    i.name AS index_name,
    i.type_desc,
    i.is_unique
FROM sys.indexes i
JOIN sys.tables t
    ON i.object_id = t.object_id
WHERE SCHEMA_NAME(t.schema_id) IN ('stg', 'dw', 'etl')
  AND i.name IS NOT NULL
ORDER BY schema_name, table_name, index_name;
GO
