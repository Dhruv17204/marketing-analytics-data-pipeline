USE MarketingAnalyticsDW;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* =========================================================
   FILE: 06_Runbook_DailyRun.sql
   PURPOSE:
     Direct daily runbook for the Marketing Analytics DW.

   WHAT IT DOES:
     1) Executes the end-to-end ETL pipeline
     2) Shows latest batch summary
     3) Shows current watermark
     4) Shows top 5 rows from all key tables/views

   DAILY USAGE:
     - This is the only file to run daily
     - Safe for manual monitoring and demo review
   ========================================================= */

PRINT '============================================================';
PRINT 'MARKETING ANALYTICS DW - DAILY RUNBOOK STARTED';
PRINT 'Run Time: ' + CONVERT(VARCHAR(19), GETDATE(), 120);
PRINT '============================================================';

BEGIN TRY

    /* ---------------------------------------------
       STEP 1: RUN MAIN PIPELINE
       --------------------------------------------- */
    EXEC etl.usp_Run_MarketingDW_Pipeline;

    PRINT '------------------------------------------------------------';
    PRINT 'PIPELINE EXECUTED SUCCESSFULLY';
    PRINT '------------------------------------------------------------';

    /* ---------------------------------------------
       STEP 2: LATEST BATCH SUMMARY
       --------------------------------------------- */
    SELECT TOP 1
        batch_id,
        pipeline_name,
        runbook_name,
        source_object,
        start_ts,
        end_ts,
        watermark_before,
        watermark_after,
        rows_staged,
        rows_inserted_dw,
        rows_rejected,
        status,
        error_message
    FROM etl.BatchLoadLog
    ORDER BY batch_id DESC;

    /* ---------------------------------------------
       STEP 3: CURRENT WATERMARK
       --------------------------------------------- */
    SELECT
        pipeline_name,
        source_object,
        watermark_column,
        last_loaded_ts,
        is_active,
        updated_ts
    FROM etl.WatermarkControl
    WHERE pipeline_name = 'MarketingDW_Gold_To_SSMS';

    /* ---------------------------------------------
       STEP 4: TOP 5 ROWS - STAGING TABLE
       --------------------------------------------- */
    SELECT TOP 5 *
    FROM stg.fact_marketing_daily_inc
    ORDER BY stg_load_id DESC;

    /* ---------------------------------------------
       STEP 5: TOP 5 ROWS - DW DIMENSIONS
       --------------------------------------------- */
    SELECT TOP 5 *
    FROM dw.dim_date
    ORDER BY date_sk DESC;

    SELECT TOP 5 *
    FROM dw.dim_product
    ORDER BY product_sk DESC;

    SELECT TOP 5 *
    FROM dw.dim_geo
    ORDER BY geo_sk DESC;

    SELECT TOP 5 *
    FROM dw.dim_campaign
    ORDER BY campaign_sk DESC;

    SELECT TOP 5 *
    FROM dw.dim_seller_channel
    ORDER BY seller_channel_sk DESC;

    /* ---------------------------------------------
       STEP 6: TOP 5 ROWS - DW FACT
       --------------------------------------------- */
    SELECT TOP 5 *
    FROM dw.fact_marketing_daily
    ORDER BY fact_sk DESC;

    /* ---------------------------------------------
       STEP 7: TOP 5 ROWS - MART VIEWS
       --------------------------------------------- */
    SELECT TOP 5 *
    FROM mart.vw_dim_date
    ORDER BY date_sk DESC;

    SELECT TOP 5 *
    FROM mart.vw_dim_product
    ORDER BY product_sk DESC;

    SELECT TOP 5 *
    FROM mart.vw_dim_geo
    ORDER BY geo_sk DESC;

    SELECT TOP 5 *
    FROM mart.vw_dim_campaign
    ORDER BY campaign_sk DESC;

    SELECT TOP 5 *
    FROM mart.vw_dim_seller_channel
    ORDER BY seller_channel_sk DESC;

    SELECT TOP 5 *
    FROM mart.vw_fact_marketing_daily_base
    ORDER BY fact_sk DESC;

    SELECT TOP 5 *
    FROM mart.vw_fact_marketing_daily
    ORDER BY fact_sk DESC;

    SELECT TOP 5 *
    FROM mart.vw_kpi_daily_overall
    ORDER BY event_date DESC;

    SELECT TOP 5 *
    FROM mart.vw_campaign_summary
    ORDER BY total_gross_revenue DESC;

    PRINT '============================================================';
    PRINT 'MARKETING ANALYTICS DW - DAILY RUNBOOK COMPLETED';
    PRINT 'End Time: ' + CONVERT(VARCHAR(19), GETDATE(), 120);
    PRINT '============================================================';

END TRY
BEGIN CATCH

    PRINT '============================================================';
    PRINT 'MARKETING ANALYTICS DW - DAILY RUNBOOK FAILED';
    PRINT 'Error: ' + ERROR_MESSAGE();
    PRINT '============================================================';

    THROW;

END CATCH
GO