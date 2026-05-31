USE MarketingAnalyticsDW;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* =========================================================
   FILE: 03_Phase6_ETL_Procedures.sql
   PURPOSE:
     Create the ETL automation layer for the Marketing DW.

   CREATES:
     1) etl.usp_Load_Staging_From_Databricks
     2) etl.usp_Load_Dimensions_From_Databricks
     3) etl.usp_Load_Fact_From_Staging
     4) etl.usp_Run_MarketingDW_Pipeline

   NOTES:
     - This is the corrected final version
     - Uses actual Gold dimension columns verified from Databricks
     - Validation procedure is optional for now
   ========================================================= */


/* =========================================================
   0) COMPATIBILITY PATCH
   Make dim_campaign.promotion_flag text-based
   ========================================================= */
IF EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID('dw.dim_campaign')
      AND name = 'promotion_flag'
      AND system_type_id = 104
)
BEGIN
    ALTER TABLE dw.dim_campaign
    ALTER COLUMN promotion_flag VARCHAR(20) NULL;
END
GO


/* =========================================================
   1) LOAD STAGING FROM DATABRICKS
   PURPOSE:
     - Pull incremental fact rows from Gold fact
     - Refresh staging for current batch
     - Use watermark from etl.WatermarkControl
   ========================================================= */
CREATE OR ALTER PROCEDURE etl.usp_Load_Staging_From_Databricks
    @BatchID BIGINT,
    @RowsStaged INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LastLoadedTs DATETIME2(6);
    DECLARE @RemoteSql NVARCHAR(MAX);
    DECLARE @Sql NVARCHAR(MAX);
    DECLARE @TsLiteral VARCHAR(30);

    SELECT @LastLoadedTs = last_loaded_ts
    FROM etl.WatermarkControl
    WHERE pipeline_name = 'MarketingDW_Gold_To_SSMS'
      AND is_active = 1;

    TRUNCATE TABLE stg.fact_marketing_daily_inc;

    IF @LastLoadedTs IS NULL
    BEGIN
        SET @RemoteSql = '
            SELECT
                fact_row_key,
                silver_ingestion_ts,
                event_date,
                date_key,
                product_key,
                geo_key,
                campaign_key,
                seller_channel_key,
                sales_units,
                marketing_spend,
                gross_revenue,
                total_cost,
                gross_profit,
                discount_amount,
                avg_rating,
                ratings_count,
                reviews_count,
                stock_out_flag,
                delivery_days,
                distributor_count,
                retailer_count,
                avg_mrp,
                avg_selling_price,
                avg_cost_price,
                avg_discount_percent,
                campaign_revenue,
                marketing_roi,
                roas,
                cost_per_unit,
                engagement_rate,
                campaign_efficiency
            FROM workspace.water_bottle_db.fact_marketing_daily
        ';
    END
    ELSE
    BEGIN
        SET @TsLiteral = REPLACE(CONVERT(VARCHAR(27), @LastLoadedTs, 126), 'T', ' ');

        SET @RemoteSql = '
            SELECT
                fact_row_key,
                silver_ingestion_ts,
                event_date,
                date_key,
                product_key,
                geo_key,
                campaign_key,
                seller_channel_key,
                sales_units,
                marketing_spend,
                gross_revenue,
                total_cost,
                gross_profit,
                discount_amount,
                avg_rating,
                ratings_count,
                reviews_count,
                stock_out_flag,
                delivery_days,
                distributor_count,
                retailer_count,
                avg_mrp,
                avg_selling_price,
                avg_cost_price,
                avg_discount_percent,
                campaign_revenue,
                marketing_roi,
                roas,
                cost_per_unit,
                engagement_rate,
                campaign_efficiency
            FROM workspace.water_bottle_db.fact_marketing_daily
            WHERE silver_ingestion_ts >= TIMESTAMP ''' + @TsLiteral + '''
        ';
    END

    SET @Sql = N'
        INSERT INTO stg.fact_marketing_daily_inc
        (
            batch_id,
            fact_row_key,
            silver_ingestion_ts,
            event_date,
            date_key,
            product_key,
            geo_key,
            campaign_key,
            seller_channel_key,
            sales_units,
            marketing_spend,
            gross_revenue,
            total_cost,
            gross_profit,
            discount_amount,
            avg_rating,
            ratings_count,
            reviews_count,
            stock_out_flag,
            delivery_days,
            distributor_count,
            retailer_count,
            avg_mrp,
            avg_selling_price,
            avg_cost_price,
            avg_discount_percent,
            campaign_revenue,
            marketing_roi,
            roas,
            cost_per_unit,
            engagement_rate,
            campaign_efficiency
        )
        SELECT
            ' + CAST(@BatchID AS VARCHAR(20)) + ',
            CAST(q.fact_row_key AS VARCHAR(128)),
            CAST(q.silver_ingestion_ts AS DATETIME2(6)),
            CAST(q.event_date AS DATE),
            CAST(q.date_key AS INT),
            CAST(q.product_key AS VARCHAR(128)),
            CAST(q.geo_key AS VARCHAR(128)),
            CAST(q.campaign_key AS VARCHAR(128)),
            CAST(q.seller_channel_key AS VARCHAR(128)),
            CAST(q.sales_units AS DECIMAL(18,2)),
            CAST(q.marketing_spend AS DECIMAL(18,2)),
            CAST(q.gross_revenue AS DECIMAL(18,2)),
            CAST(q.total_cost AS DECIMAL(18,2)),
            CAST(q.gross_profit AS DECIMAL(18,2)),
            CAST(q.discount_amount AS DECIMAL(18,2)),
            CAST(q.avg_rating AS DECIMAL(10,2)),
            CAST(q.ratings_count AS INT),
            CAST(q.reviews_count AS INT),
            CAST(q.stock_out_flag AS BIT),
            CAST(q.delivery_days AS INT),
            CAST(q.distributor_count AS INT),
            CAST(q.retailer_count AS INT),
            CAST(q.avg_mrp AS DECIMAL(18,2)),
            CAST(q.avg_selling_price AS DECIMAL(18,2)),
            CAST(q.avg_cost_price AS DECIMAL(18,2)),
            CAST(q.avg_discount_percent AS DECIMAL(10,2)),
            CAST(q.campaign_revenue AS DECIMAL(18,2)),
            CAST(q.marketing_roi AS DECIMAL(18,4)),
            CAST(q.roas AS DECIMAL(18,4)),
            CAST(q.cost_per_unit AS DECIMAL(18,4)),
            CAST(q.engagement_rate AS DECIMAL(18,4)),
            CAST(q.campaign_efficiency AS DECIMAL(18,4))
        FROM OPENQUERY(DATABRICKS_GOLD, ''' + REPLACE(@RemoteSql, '''', '''''') + ''') q;
    ';

    EXEC sys.sp_executesql @Sql;

    SET @RowsStaged = @@ROWCOUNT;
END
GO


/* =========================================================
   2) LOAD DIMENSIONS FROM DATABRICKS
   PURPOSE:
     - Sync SSMS dimensions from Gold dimensions
     - Uses actual verified Gold columns
   ========================================================= */
CREATE OR ALTER PROCEDURE etl.usp_Load_Dimensions_From_Databricks
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* -------------------------
       DIM DATE
       Gold columns:
       date_key, event_date, day, month, month_name,
       quarter, year, week_of_year, day_name, is_weekend
       ------------------------- */
    IF OBJECT_ID('tempdb..#dim_date_src') IS NOT NULL DROP TABLE #dim_date_src;

    CREATE TABLE #dim_date_src
    (
        source_date_key   INT,
        full_date         DATE,
        day_of_month      TINYINT,
        calendar_month    TINYINT,
        month_name        VARCHAR(20),
        calendar_quarter  TINYINT,
        calendar_year     INT,
        week_of_year      TINYINT,
        day_name          VARCHAR(20),
        is_weekend        BIT
    );

    INSERT INTO #dim_date_src
    SELECT
        CAST(q.date_key AS INT),
        CAST(q.event_date AS DATE),
        CAST(q.day AS TINYINT),
        CAST(q.month AS TINYINT),
        CAST(q.month_name AS VARCHAR(20)),
        CAST(q.quarter AS TINYINT),
        CAST(q.year AS INT),
        CAST(q.week_of_year AS TINYINT),
        CAST(q.day_name AS VARCHAR(20)),
        CAST(q.is_weekend AS BIT)
    FROM OPENQUERY(
        DATABRICKS_GOLD,
        'SELECT date_key, event_date, day, month, month_name, quarter, year, week_of_year, day_name, is_weekend
         FROM workspace.water_bottle_db.dim_date'
    ) q;

    UPDATE d
       SET d.full_date         = s.full_date,
           d.calendar_year     = s.calendar_year,
           d.calendar_quarter  = s.calendar_quarter,
           d.calendar_month    = s.calendar_month,
           d.month_name        = s.month_name,
           d.month_short_name  = LEFT(s.month_name, 3),
           d.day_of_month      = s.day_of_month,
           d.day_of_week       = DATEPART(WEEKDAY, s.full_date),
           d.day_name          = s.day_name,
           d.week_of_year      = s.week_of_year,
           d.is_weekend        = s.is_weekend,
           d.updated_ts        = SYSUTCDATETIME()
    FROM dw.dim_date d
    JOIN #dim_date_src s
      ON d.source_date_key = s.source_date_key
    WHERE d.date_sk <> 0;

    INSERT INTO dw.dim_date
    (
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
    SELECT
        s.source_date_key,
        s.full_date,
        s.calendar_year,
        s.calendar_quarter,
        s.calendar_month,
        s.month_name,
        LEFT(s.month_name, 3),
        s.day_of_month,
        DATEPART(WEEKDAY, s.full_date),
        s.day_name,
        s.week_of_year,
        s.is_weekend
    FROM #dim_date_src s
    WHERE NOT EXISTS (
        SELECT 1
        FROM dw.dim_date d
        WHERE d.source_date_key = s.source_date_key
    );


    /* -------------------------
       DIM PRODUCT
       Gold columns:
       product_key, brand, product_name, pack_size_ml
       ------------------------- */
    IF OBJECT_ID('tempdb..#dim_product_src') IS NOT NULL DROP TABLE #dim_product_src;

    CREATE TABLE #dim_product_src
    (
        source_product_key  VARCHAR(128),
        brand               VARCHAR(200),
        product_name        VARCHAR(300),
        pack_size_ml        INT
    );

    INSERT INTO #dim_product_src
    SELECT
        CAST(q.product_key AS VARCHAR(128)),
        CAST(q.brand AS VARCHAR(200)),
        CAST(q.product_name AS VARCHAR(300)),
        CAST(q.pack_size_ml AS INT)
    FROM OPENQUERY(
        DATABRICKS_GOLD,
        'SELECT product_key, brand, product_name, pack_size_ml
         FROM workspace.water_bottle_db.dim_product'
    ) q;

    UPDATE d
       SET d.brand         = s.brand,
           d.product_name  = s.product_name,
           d.pack_size_ml  = s.pack_size_ml,
           d.updated_ts    = SYSUTCDATETIME()
    FROM dw.dim_product d
    JOIN #dim_product_src s
      ON d.source_product_key = s.source_product_key
    WHERE d.product_sk <> 0;

    INSERT INTO dw.dim_product
    (
        source_product_key,
        brand,
        product_name,
        pack_size_ml
    )
    SELECT
        s.source_product_key,
        s.brand,
        s.product_name,
        s.pack_size_ml
    FROM #dim_product_src s
    WHERE NOT EXISTS (
        SELECT 1
        FROM dw.dim_product d
        WHERE d.source_product_key = s.source_product_key
    );


    /* -------------------------
       DIM GEO
       Gold columns:
       geo_key, region, state, city
       ------------------------- */
    IF OBJECT_ID('tempdb..#dim_geo_src') IS NOT NULL DROP TABLE #dim_geo_src;

    CREATE TABLE #dim_geo_src
    (
        source_geo_key  VARCHAR(128),
        region_name     VARCHAR(150),
        state_name      VARCHAR(150),
        city_name       VARCHAR(150)
    );

    INSERT INTO #dim_geo_src
    SELECT
        CAST(q.geo_key AS VARCHAR(128)),
        CAST(q.region AS VARCHAR(150)),
        CAST(q.state AS VARCHAR(150)),
        CAST(q.city AS VARCHAR(150))
    FROM OPENQUERY(
        DATABRICKS_GOLD,
        'SELECT geo_key, region, state, city
         FROM workspace.water_bottle_db.dim_geo'
    ) q;

    UPDATE d
       SET d.region_name = s.region_name,
           d.state_name  = s.state_name,
           d.city_name   = s.city_name,
           d.updated_ts  = SYSUTCDATETIME()
    FROM dw.dim_geo d
    JOIN #dim_geo_src s
      ON d.source_geo_key = s.source_geo_key
    WHERE d.geo_sk <> 0;

    INSERT INTO dw.dim_geo
    (
        source_geo_key,
        region_name,
        state_name,
        city_name
    )
    SELECT
        s.source_geo_key,
        s.region_name,
        s.state_name,
        s.city_name
    FROM #dim_geo_src s
    WHERE NOT EXISTS (
        SELECT 1
        FROM dw.dim_geo d
        WHERE d.source_geo_key = s.source_geo_key
    );


    /* -------------------------
       DIM CAMPAIGN
       Gold columns:
       campaign_key, campaign_name, campaign_type,
       offer_type, promotion_flag
       ------------------------- */
    IF OBJECT_ID('tempdb..#dim_campaign_src') IS NOT NULL DROP TABLE #dim_campaign_src;

    CREATE TABLE #dim_campaign_src
    (
        source_campaign_key VARCHAR(128),
        campaign_name       VARCHAR(250),
        campaign_type       VARCHAR(100),
        offer_type          VARCHAR(100),
        promotion_flag      VARCHAR(20)
    );

    INSERT INTO #dim_campaign_src
    SELECT
        CAST(q.campaign_key AS VARCHAR(128)),
        CAST(q.campaign_name AS VARCHAR(250)),
        CAST(q.campaign_type AS VARCHAR(100)),
        CAST(q.offer_type AS VARCHAR(100)),
        CAST(q.promotion_flag AS VARCHAR(20))
    FROM OPENQUERY(
        DATABRICKS_GOLD,
        'SELECT campaign_key, campaign_name, campaign_type, offer_type, promotion_flag
         FROM workspace.water_bottle_db.dim_campaign'
    ) q;

    UPDATE d
       SET d.campaign_name   = s.campaign_name,
           d.campaign_type   = s.campaign_type,
           d.offer_type      = s.offer_type,
           d.promotion_flag  = s.promotion_flag,
           d.updated_ts      = SYSUTCDATETIME()
    FROM dw.dim_campaign d
    JOIN #dim_campaign_src s
      ON d.source_campaign_key = s.source_campaign_key
    WHERE d.campaign_sk <> 0;

    INSERT INTO dw.dim_campaign
    (
        source_campaign_key,
        campaign_name,
        campaign_type,
        offer_type,
        promotion_flag
    )
    SELECT
        s.source_campaign_key,
        s.campaign_name,
        s.campaign_type,
        s.offer_type,
        s.promotion_flag
    FROM #dim_campaign_src s
    WHERE NOT EXISTS (
        SELECT 1
        FROM dw.dim_campaign d
        WHERE d.source_campaign_key = s.source_campaign_key
    );


    /* -------------------------
       DIM SELLER CHANNEL
       Gold columns:
       seller_channel_key, seller, platform_source,
       channel, seller_type
       ------------------------- */
    IF OBJECT_ID('tempdb..#dim_seller_src') IS NOT NULL DROP TABLE #dim_seller_src;

    CREATE TABLE #dim_seller_src
    (
        source_seller_channel_key VARCHAR(128),
        seller_name               VARCHAR(250),
        platform_source           VARCHAR(100),
        sales_channel             VARCHAR(100),
        seller_type               VARCHAR(100)
    );

    INSERT INTO #dim_seller_src
    SELECT
        CAST(q.seller_channel_key AS VARCHAR(128)),
        CAST(q.seller AS VARCHAR(250)),
        CAST(q.platform_source AS VARCHAR(100)),
        CAST(q.channel AS VARCHAR(100)),
        CAST(q.seller_type AS VARCHAR(100))
    FROM OPENQUERY(
        DATABRICKS_GOLD,
        'SELECT seller_channel_key, seller, platform_source, channel, seller_type
         FROM workspace.water_bottle_db.dim_seller_channel'
    ) q;

    UPDATE d
       SET d.seller_name     = s.seller_name,
           d.platform_source = s.platform_source,
           d.sales_channel   = s.sales_channel,
           d.seller_type     = s.seller_type,
           d.updated_ts      = SYSUTCDATETIME()
    FROM dw.dim_seller_channel d
    JOIN #dim_seller_src s
      ON d.source_seller_channel_key = s.source_seller_channel_key
    WHERE d.seller_channel_sk <> 0;

    INSERT INTO dw.dim_seller_channel
    (
        source_seller_channel_key,
        seller_name,
        platform_source,
        sales_channel,
        seller_type
    )
    SELECT
        s.source_seller_channel_key,
        s.seller_name,
        s.platform_source,
        s.sales_channel,
        s.seller_type
    FROM #dim_seller_src s
    WHERE NOT EXISTS (
        SELECT 1
        FROM dw.dim_seller_channel d
        WHERE d.source_seller_channel_key = s.source_seller_channel_key
    );
END
GO


/* =========================================================
   3) LOAD FACT FROM STAGING
   PURPOSE:
     - Map source keys to SSMS surrogate keys
     - Insert only new fact_row_key values
   ========================================================= */
CREATE OR ALTER PROCEDURE etl.usp_Load_Fact_From_Staging
    @BatchID BIGINT,
    @RowsInsertedDW INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    INSERT INTO dw.fact_marketing_daily
    (
        batch_id,
        fact_row_key,
        silver_ingestion_ts,
        event_date,
        date_sk,
        product_sk,
        geo_sk,
        campaign_sk,
        seller_channel_sk,
        sales_units,
        marketing_spend,
        gross_revenue,
        total_cost,
        gross_profit,
        discount_amount,
        avg_rating,
        ratings_count,
        reviews_count,
        stock_out_flag,
        delivery_days,
        distributor_count,
        retailer_count,
        avg_mrp,
        avg_selling_price,
        avg_cost_price,
        avg_discount_percent,
        campaign_revenue,
        marketing_roi,
        roas,
        cost_per_unit,
        engagement_rate,
        campaign_efficiency
    )
    SELECT
        s.batch_id,
        s.fact_row_key,
        s.silver_ingestion_ts,
        s.event_date,
        ISNULL(dd.date_sk, 0),
        ISNULL(dp.product_sk, 0),
        ISNULL(dg.geo_sk, 0),
        ISNULL(dc.campaign_sk, 0),
        ISNULL(ds.seller_channel_sk, 0),
        s.sales_units,
        s.marketing_spend,
        s.gross_revenue,
        s.total_cost,
        s.gross_profit,
        s.discount_amount,
        s.avg_rating,
        s.ratings_count,
        s.reviews_count,
        s.stock_out_flag,
        s.delivery_days,
        s.distributor_count,
        s.retailer_count,
        s.avg_mrp,
        s.avg_selling_price,
        s.avg_cost_price,
        s.avg_discount_percent,
        s.campaign_revenue,
        s.marketing_roi,
        s.roas,
        s.cost_per_unit,
        s.engagement_rate,
        s.campaign_efficiency
    FROM stg.fact_marketing_daily_inc s
    LEFT JOIN dw.dim_date dd
        ON dd.source_date_key = s.date_key
    LEFT JOIN dw.dim_product dp
        ON dp.source_product_key = s.product_key
    LEFT JOIN dw.dim_geo dg
        ON dg.source_geo_key = s.geo_key
    LEFT JOIN dw.dim_campaign dc
        ON dc.source_campaign_key = s.campaign_key
    LEFT JOIN dw.dim_seller_channel ds
        ON ds.source_seller_channel_key = s.seller_channel_key
    WHERE s.batch_id = @BatchID
      AND NOT EXISTS
      (
          SELECT 1
          FROM dw.fact_marketing_daily f
          WHERE f.fact_row_key = s.fact_row_key
      );

    SET @RowsInsertedDW = @@ROWCOUNT;
END
GO


/* =========================================================
   4) MASTER PIPELINE RUNNER
   PURPOSE:
     - Run stage load
     - Run dimension sync
     - Run fact load
     - Update watermark
     - Log success/failure
   ========================================================= */
CREATE OR ALTER PROCEDURE etl.usp_Run_MarketingDW_Pipeline
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @BatchID BIGINT;
    DECLARE @RowsStaged INT = 0;
    DECLARE @RowsInsertedDW INT = 0;
    DECLARE @WatermarkBefore DATETIME2(6);
    DECLARE @WatermarkAfter DATETIME2(6);
    DECLARE @PipelineName VARCHAR(200) = 'MarketingDW_Gold_To_SSMS';
    DECLARE @SourceObject VARCHAR(300);

    BEGIN TRY
        SELECT
            @WatermarkBefore = last_loaded_ts,
            @SourceObject = source_object
        FROM etl.WatermarkControl
        WHERE pipeline_name = @PipelineName
          AND is_active = 1;

        INSERT INTO etl.BatchLoadLog
        (
            pipeline_name,
            runbook_name,
            source_object,
            start_ts,
            watermark_before,
            status
        )
        VALUES
        (
            @PipelineName,
            '13_Daily_Runbook.sql',
            @SourceObject,
            SYSUTCDATETIME(),
            @WatermarkBefore,
            'STARTED'
        );

        SET @BatchID = SCOPE_IDENTITY();

        EXEC etl.usp_Load_Staging_From_Databricks
            @BatchID = @BatchID,
            @RowsStaged = @RowsStaged OUTPUT;

        EXEC etl.usp_Load_Dimensions_From_Databricks;

        EXEC etl.usp_Load_Fact_From_Staging
            @BatchID = @BatchID,
            @RowsInsertedDW = @RowsInsertedDW OUTPUT;

        SELECT @WatermarkAfter = MAX(silver_ingestion_ts)
        FROM stg.fact_marketing_daily_inc
        WHERE batch_id = @BatchID;

        IF @WatermarkAfter IS NOT NULL
        BEGIN
            UPDATE etl.WatermarkControl
            SET last_loaded_ts = @WatermarkAfter,
                updated_ts = SYSUTCDATETIME()
            WHERE pipeline_name = @PipelineName;
        END
        ELSE
        BEGIN
            SET @WatermarkAfter = @WatermarkBefore;
        END

        IF OBJECT_ID('etl.usp_Validate_LatestBatch_FactMarketingDaily', 'P') IS NOT NULL
        BEGIN
            EXEC etl.usp_Validate_LatestBatch_FactMarketingDaily;
        END

        UPDATE etl.BatchLoadLog
        SET end_ts = SYSUTCDATETIME(),
            watermark_after = @WatermarkAfter,
            rows_staged = @RowsStaged,
            rows_inserted_dw = @RowsInsertedDW,
            status = 'SUCCESS'
        WHERE batch_id = @BatchID;
    END TRY
    BEGIN CATCH
        UPDATE etl.BatchLoadLog
        SET end_ts = SYSUTCDATETIME(),
            rows_staged = @RowsStaged,
            rows_inserted_dw = @RowsInsertedDW,
            status = 'FAILED',
            error_message = ERROR_MESSAGE()
        WHERE batch_id = @BatchID;

        THROW;
    END CATCH
END
GO


/* =========================================================
   5) SMOKE TEST
   ========================================================= */
SELECT
    p.name AS procedure_name
FROM sys.procedures p
WHERE SCHEMA_NAME(p.schema_id) = 'etl'
  AND p.name IN
  (
      'usp_Load_Staging_From_Databricks',
      'usp_Load_Dimensions_From_Databricks',
      'usp_Load_Fact_From_Staging',
      'usp_Run_MarketingDW_Pipeline'
  )
ORDER BY p.name;
GO