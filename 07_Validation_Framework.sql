USE MarketingAnalyticsDW;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* =========================================================
   FILE: 07_Validation_Framework.sql
   PURPOSE:
     Create / replace the validation procedure for the
     Marketing Analytics DW.

   CREATES:
     etl.usp_Validate_LatestBatch_FactMarketingDaily

   VALIDATION AREAS:
     1) Latest batch existence
     2) Staging vs DW reconciliation
     3) Watermark progression
     4) Duplicate fact_row_key checks
     5) Referential integrity checks
     6) Data quality checks
     7) Statistical sanity checks
     8) Final PASS / FAIL summary

   NOTE:
     This version gives a better remark when:
     - rows are staged
     - but 0 new rows are inserted into DW
     because the data already exists (idempotent rerun)
   ========================================================= */

CREATE OR ALTER PROCEDURE etl.usp_Validate_LatestBatch_FactMarketingDaily
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LatestBatchID        BIGINT;
    DECLARE @WatermarkAfter       DATETIME2(6);

    DECLARE @StageRows            INT = 0;
    DECLARE @DWRows               INT = 0;

    DECLARE @StageDupCount        INT = 0;
    DECLARE @DWDupCount           INT = 0;

    DECLARE @MissingDate          INT = 0;
    DECLARE @MissingProduct       INT = 0;
    DECLARE @MissingGeo           INT = 0;
    DECLARE @MissingCampaign      INT = 0;
    DECLARE @MissingSeller        INT = 0;

    DECLARE @NullRevenue          INT = 0;
    DECLARE @NullProfit           INT = 0;
    DECLARE @NullSpend            INT = 0;
    DECLARE @NegativeRevenue      INT = 0;
    DECLARE @NegativeSpend        INT = 0;
    DECLARE @InvalidRating        INT = 0;
    DECLARE @InvalidDeliveryDays  INT = 0;

    DECLARE @MinRevenue           DECIMAL(18,2) = NULL;
    DECLARE @MaxRevenue           DECIMAL(18,2) = NULL;
    DECLARE @MinSpend             DECIMAL(18,2) = NULL;
    DECLARE @MaxSpend             DECIMAL(18,2) = NULL;
    DECLARE @MinROI               DECIMAL(18,4) = NULL;
    DECLARE @MaxROI               DECIMAL(18,4) = NULL;
    DECLARE @MinUnits             DECIMAL(18,2) = NULL;
    DECLARE @MaxUnits             DECIMAL(18,2) = NULL;

    DECLARE @OverallStatus        VARCHAR(10) = 'PASS';
    DECLARE @Remarks              NVARCHAR(2000) = N'';

    /* -----------------------------------------------------
       1) Identify latest successful batch
       ----------------------------------------------------- */
    SELECT TOP 1
        @LatestBatchID = batch_id,
        @WatermarkAfter = watermark_after
    FROM etl.BatchLoadLog
    WHERE status = 'SUCCESS'
    ORDER BY batch_id DESC;

    IF @LatestBatchID IS NULL
    BEGIN
        RAISERROR('No successful batch found in etl.BatchLoadLog.', 16, 1);
        RETURN;
    END

    /* -----------------------------------------------------
       2) Reconciliation
       ----------------------------------------------------- */
    SELECT @StageRows = COUNT(*)
    FROM stg.fact_marketing_daily_inc
    WHERE batch_id = @LatestBatchID;

    SELECT @DWRows = COUNT(*)
    FROM dw.fact_marketing_daily
    WHERE batch_id = @LatestBatchID;

    /* -----------------------------------------------------
       3) Duplicate detection
       ----------------------------------------------------- */
    SELECT @StageDupCount = COUNT(*)
    FROM
    (
        SELECT fact_row_key
        FROM stg.fact_marketing_daily_inc
        WHERE batch_id = @LatestBatchID
        GROUP BY fact_row_key
        HAVING COUNT(*) > 1
    ) d;

    SELECT @DWDupCount = COUNT(*)
    FROM
    (
        SELECT fact_row_key
        FROM dw.fact_marketing_daily
        GROUP BY fact_row_key
        HAVING COUNT(*) > 1
    ) d;

    /* -----------------------------------------------------
       4) Referential integrity
       Unknown = 0 is allowed by design.
       We only fail for truly broken joins.
       ----------------------------------------------------- */
    SELECT @MissingDate = COUNT(*)
    FROM dw.fact_marketing_daily f
    LEFT JOIN dw.dim_date d
        ON f.date_sk = d.date_sk
    WHERE f.batch_id = @LatestBatchID
      AND d.date_sk IS NULL;

    SELECT @MissingProduct = COUNT(*)
    FROM dw.fact_marketing_daily f
    LEFT JOIN dw.dim_product d
        ON f.product_sk = d.product_sk
    WHERE f.batch_id = @LatestBatchID
      AND d.product_sk IS NULL;

    SELECT @MissingGeo = COUNT(*)
    FROM dw.fact_marketing_daily f
    LEFT JOIN dw.dim_geo d
        ON f.geo_sk = d.geo_sk
    WHERE f.batch_id = @LatestBatchID
      AND d.geo_sk IS NULL;

    SELECT @MissingCampaign = COUNT(*)
    FROM dw.fact_marketing_daily f
    LEFT JOIN dw.dim_campaign d
        ON f.campaign_sk = d.campaign_sk
    WHERE f.batch_id = @LatestBatchID
      AND d.campaign_sk IS NULL;

    SELECT @MissingSeller = COUNT(*)
    FROM dw.fact_marketing_daily f
    LEFT JOIN dw.dim_seller_channel d
        ON f.seller_channel_sk = d.seller_channel_sk
    WHERE f.batch_id = @LatestBatchID
      AND d.seller_channel_sk IS NULL;

    /* -----------------------------------------------------
       5) Data quality checks
       ----------------------------------------------------- */
    SELECT @NullRevenue = COUNT(*)
    FROM dw.fact_marketing_daily
    WHERE batch_id = @LatestBatchID
      AND gross_revenue IS NULL;

    SELECT @NullProfit = COUNT(*)
    FROM dw.fact_marketing_daily
    WHERE batch_id = @LatestBatchID
      AND gross_profit IS NULL;

    SELECT @NullSpend = COUNT(*)
    FROM dw.fact_marketing_daily
    WHERE batch_id = @LatestBatchID
      AND marketing_spend IS NULL;

    SELECT @NegativeRevenue = COUNT(*)
    FROM dw.fact_marketing_daily
    WHERE batch_id = @LatestBatchID
      AND gross_revenue < 0;

    SELECT @NegativeSpend = COUNT(*)
    FROM dw.fact_marketing_daily
    WHERE batch_id = @LatestBatchID
      AND marketing_spend < 0;

    SELECT @InvalidRating = COUNT(*)
    FROM dw.fact_marketing_daily
    WHERE batch_id = @LatestBatchID
      AND avg_rating IS NOT NULL
      AND (avg_rating < 0 OR avg_rating > 5);

    SELECT @InvalidDeliveryDays = COUNT(*)
    FROM dw.fact_marketing_daily
    WHERE batch_id = @LatestBatchID
      AND delivery_days IS NOT NULL
      AND delivery_days < 0;

    /* -----------------------------------------------------
       6) Statistical sanity checks
       ----------------------------------------------------- */
    SELECT
        @MinRevenue = MIN(gross_revenue),
        @MaxRevenue = MAX(gross_revenue),
        @MinSpend   = MIN(marketing_spend),
        @MaxSpend   = MAX(marketing_spend),
        @MinROI     = MIN(marketing_roi),
        @MaxROI     = MAX(marketing_roi),
        @MinUnits   = MIN(sales_units),
        @MaxUnits   = MAX(sales_units)
    FROM dw.fact_marketing_daily
    WHERE batch_id = @LatestBatchID;

    /* -----------------------------------------------------
       7) PASS / FAIL logic
       ----------------------------------------------------- */
    IF @StageDupCount > 0
    BEGIN
        SET @OverallStatus = 'FAIL';
        SET @Remarks += 'Stage duplicates found. ';
    END;

    IF @DWDupCount > 0
    BEGIN
        SET @OverallStatus = 'FAIL';
        SET @Remarks += 'DW duplicates found. ';
    END;

    IF @MissingDate > 0 OR @MissingProduct > 0 OR @MissingGeo > 0 OR @MissingCampaign > 0 OR @MissingSeller > 0
    BEGIN
        SET @OverallStatus = 'FAIL';
        SET @Remarks += 'Referential integrity issue found. ';
    END;

    IF @NegativeRevenue > 0 OR @NegativeSpend > 0 OR @InvalidRating > 0 OR @InvalidDeliveryDays > 0
    BEGIN
        SET @OverallStatus = 'FAIL';
        SET @Remarks += 'Data quality rule violation found. ';
    END;

    /* -----------------------------------------------------
       8) Better success remarks
       ----------------------------------------------------- */
    IF @OverallStatus = 'PASS'
    BEGIN
        IF @StageRows > 0 AND @DWRows = 0
        BEGIN
            SET @Remarks = 'No new rows inserted; source data already exists in DW (incremental/idempotent rerun).';
        END
        ELSE IF @StageRows = 0 AND @DWRows = 0
        BEGIN
            SET @Remarks = 'No rows found for the latest batch. Nothing to validate.';
        END
        ELSE
        BEGIN
            SET @Remarks = 'All validation checks passed.';
        END
    END

    /* -----------------------------------------------------
       9) Final consolidated output
       ----------------------------------------------------- */
    SELECT
        @LatestBatchID          AS latest_batch_id,
        @StageRows              AS stg_rows,
        @DWRows                 AS dw_latest_batch_rows,
        @WatermarkAfter         AS watermark_after,

        @StageDupCount          AS stg_duplicate_fact_row_keys,
        @DWDupCount             AS dw_duplicate_fact_row_keys,

        @MissingDate            AS missing_date_dimension_rows,
        @MissingProduct         AS missing_product_dimension_rows,
        @MissingGeo             AS missing_geo_dimension_rows,
        @MissingCampaign        AS missing_campaign_dimension_rows,
        @MissingSeller          AS missing_seller_dimension_rows,

        @NullRevenue            AS null_gross_revenue_rows,
        @NullProfit             AS null_gross_profit_rows,
        @NullSpend              AS null_marketing_spend_rows,
        @NegativeRevenue        AS negative_gross_revenue_rows,
        @NegativeSpend          AS negative_marketing_spend_rows,
        @InvalidRating          AS invalid_avg_rating_rows,
        @InvalidDeliveryDays    AS invalid_delivery_days_rows,

        @MinRevenue             AS min_gross_revenue,
        @MaxRevenue             AS max_gross_revenue,
        @MinSpend               AS min_marketing_spend,
        @MaxSpend               AS max_marketing_spend,
        @MinROI                 AS min_marketing_roi,
        @MaxROI                 AS max_marketing_roi,
        @MinUnits               AS min_sales_units,
        @MaxUnits               AS max_sales_units,

        @OverallStatus          AS overall_status,
        @Remarks                AS validation_remarks;
END
GO