USE MarketingAnalyticsDW;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* =========================================================
   FILE: 05_Mart_Layer_PowerBI.sql
   PURPOSE:
     Create the semantic / mart layer for Power BI.

   CREATES:
     1) mart.vw_dim_date
     2) mart.vw_dim_product
     3) mart.vw_dim_geo
     4) mart.vw_dim_campaign
     5) mart.vw_dim_seller_channel
     6) mart.vw_fact_marketing_daily_base
     7) mart.vw_fact_marketing_daily
     8) mart.vw_kpi_daily_overall
     9) mart.vw_campaign_summary

   DESIGN GOAL:
     - Power BI friendly naming
     - Clean joins
     - Business-readable columns
     - No direct dependency on raw staging
   ========================================================= */


/* =========================================================
   1) DIM DATE VIEW
   ========================================================= */
USE MarketingAnalyticsDW;
GO

IF OBJECT_ID('mart.vw_dim_date', 'V') IS NOT NULL
    DROP VIEW mart.vw_dim_date;
GO

CREATE VIEW mart.vw_dim_date
AS
SELECT
    d.date_sk,
    d.source_date_key AS date_key,
    d.full_date,
    d.calendar_year,
    d.calendar_quarter,
    d.calendar_month,
    d.month_name,
    d.month_short_name,
    d.day_of_month,
    d.day_of_week,
    d.day_name,
    d.week_of_year,
    d.is_weekend
FROM dw.dim_date d
WHERE d.date_sk <> 0
  AND d.source_date_key <> 0
  AND d.calendar_year IS NOT NULL
  AND d.calendar_year > 2000;
GO


/* =========================================================
   2) DIM PRODUCT VIEW
   ========================================================= */
IF OBJECT_ID('mart.vw_dim_product', 'V') IS NOT NULL
    DROP VIEW mart.vw_dim_product;
GO

CREATE VIEW mart.vw_dim_product
AS
SELECT
    p.product_sk,
    p.source_product_key AS product_key,
    p.brand,
    p.product_name,
    p.pack_size_ml,
    p.product_tier,
    p.category
FROM dw.dim_product p
WHERE p.brand IS NOT NULL
AND p.brand <> 'UNKNOWN'
GO


/* ==============================================================
3) DIM GEO VIEW
============================================================== */

IF OBJECT_ID('mart.vw_dim_geo', 'V') IS NOT NULL
    DROP VIEW mart.vw_dim_geo;
GO

CREATE VIEW mart.vw_dim_geo
AS
SELECT
    g.geo_sk,
    g.source_geo_key AS geo_key,
    g.region_name AS region,
    g.state_name AS state,
    g.city_name AS city
FROM dw.dim_geo g
WHERE g.region_name <> 'UNKNOWN';
GO


/* ==============================================================
4) DIM CAMPAIGN VIEW
============================================================== */

IF OBJECT_ID('mart.vw_dim_campaign', 'V') IS NOT NULL
    DROP VIEW mart.vw_dim_campaign;
GO

CREATE VIEW mart.vw_dim_campaign
AS
SELECT
    c.campaign_sk,
    c.source_campaign_key AS campaign_key,
    c.campaign_name,
    c.campaign_type,
    c.offer_type,
    c.promotion_flag
FROM dw.dim_campaign c
WHERE c.campaign_type <> 'UNKNOWN';
GO


/* =========================================================
   5) DIM SELLER CHANNEL VIEW
   ========================================================= */
IF OBJECT_ID('mart.vw_dim_seller_channel', 'V') IS NOT NULL
    DROP VIEW mart.vw_dim_seller_channel;
GO

CREATE VIEW mart.vw_dim_seller_channel
AS
SELECT
    s.seller_channel_sk,
    s.source_seller_channel_key AS seller_channel_key,
    s.seller_name,
    s.platform_source,
    s.sales_channel,
    s.seller_type
FROM dw.dim_seller_channel s;
GO


/* =========================================================
   6) FACT BASE VIEW
   PURPOSE:
     Expose raw fact with surrogate keys and measures only
   ========================================================= */
IF OBJECT_ID('mart.vw_fact_marketing_daily_base', 'V') IS NOT NULL
    DROP VIEW mart.vw_fact_marketing_daily_base;
GO

CREATE VIEW mart.vw_fact_marketing_daily_base
AS
SELECT
    f.fact_sk,
    f.batch_id,
    f.fact_row_key,
    f.silver_ingestion_ts,
    f.event_date,

    f.date_sk,
    f.product_sk,
    f.geo_sk,
    f.campaign_sk,
    f.seller_channel_sk,

    f.sales_units,
    f.marketing_spend,
    f.gross_revenue,
    f.total_cost,
    f.gross_profit,
    f.discount_amount,
    f.avg_rating,
    f.ratings_count,
    f.reviews_count,
    f.stock_out_flag,
    f.delivery_days,
    f.distributor_count,
    f.retailer_count,
    f.avg_mrp,
    f.avg_selling_price,
    f.avg_cost_price,
    f.avg_discount_percent,
    f.campaign_revenue,
    f.marketing_roi,
    f.roas,
    f.cost_per_unit,
    f.engagement_rate,
    f.campaign_efficiency
FROM dw.fact_marketing_daily f;
GO


/* =========================================================
   7) ANALYTICS FACT VIEW
   PURPOSE:
     Flattened business-friendly fact for Power BI
   ========================================================= */
IF OBJECT_ID('mart.vw_fact_marketing_daily', 'V') IS NOT NULL
    DROP VIEW mart.vw_fact_marketing_daily;
GO

CREATE VIEW mart.vw_fact_marketing_daily
AS
SELECT
    f.fact_sk,
    f.batch_id,
    f.fact_row_key,
    f.silver_ingestion_ts,
    f.event_date,

    d.date_key,
    d.full_date,
    d.calendar_year,
    d.calendar_quarter,
    d.calendar_month,
    d.month_name,
    d.week_of_year,
    d.day_name,
    d.is_weekend,

    p.product_key,
    p.brand,
    p.product_name,
    p.pack_size_ml,
    p.product_tier,
    p.category,

    g.geo_key,
    g.region,
    g.state,
    g.city,

    c.campaign_key,
    c.campaign_name,
    c.campaign_type,
    c.offer_type,
    c.promotion_flag,

    s.seller_channel_key,
    s.seller_name,
    s.platform_source,
    s.sales_channel,
    s.seller_type,

    f.sales_units,
    f.marketing_spend,
    f.gross_revenue,
    f.total_cost,
    f.gross_profit,
    f.discount_amount,
    f.avg_rating,
    f.ratings_count,
    f.reviews_count,
    f.stock_out_flag,
    f.delivery_days,
    f.distributor_count,
    f.retailer_count,
    f.avg_mrp,
    f.avg_selling_price,
    f.avg_cost_price,
    f.avg_discount_percent,
    f.campaign_revenue,
    f.marketing_roi,
    f.roas,
    f.cost_per_unit,
    f.engagement_rate,
    f.campaign_efficiency
FROM mart.vw_fact_marketing_daily_base f
LEFT JOIN mart.vw_dim_date d
    ON f.date_sk = d.date_sk
LEFT JOIN mart.vw_dim_product p
    ON f.product_sk = p.product_sk
LEFT JOIN mart.vw_dim_geo g
    ON f.geo_sk = g.geo_sk
LEFT JOIN mart.vw_dim_campaign c
    ON f.campaign_sk = c.campaign_sk
LEFT JOIN mart.vw_dim_seller_channel s
    ON f.seller_channel_sk = s.seller_channel_sk;
GO


/* =========================================================
   8) KPI DAILY OVERALL VIEW
   PURPOSE:
     Ready-made daily KPI summary for Power BI cards/charts
   ========================================================= */
IF OBJECT_ID('mart.vw_kpi_daily_overall', 'V') IS NOT NULL
    DROP VIEW mart.vw_kpi_daily_overall;
GO

CREATE VIEW mart.vw_kpi_daily_overall
AS
SELECT
    f.event_date,
    d.calendar_year,
    d.calendar_quarter,
    d.calendar_month,
    d.month_name,

    COUNT(*) AS fact_rows,
    SUM(ISNULL(f.sales_units, 0)) AS total_sales_units,
    SUM(ISNULL(f.marketing_spend, 0)) AS total_marketing_spend,
    SUM(ISNULL(f.gross_revenue, 0)) AS total_gross_revenue,
    SUM(ISNULL(f.total_cost, 0)) AS total_total_cost,
    SUM(ISNULL(f.gross_profit, 0)) AS total_gross_profit,
    SUM(ISNULL(f.discount_amount, 0)) AS total_discount_amount,
    SUM(ISNULL(f.campaign_revenue, 0)) AS total_campaign_revenue,

    AVG(CAST(f.avg_rating AS DECIMAL(18,4))) AS avg_rating,
    SUM(ISNULL(f.ratings_count, 0)) AS total_ratings_count,
    SUM(ISNULL(f.reviews_count, 0)) AS total_reviews_count,
    AVG(CAST(f.avg_discount_percent AS DECIMAL(18,4))) AS avg_discount_percent,
    AVG(CAST(f.marketing_roi AS DECIMAL(18,4))) AS avg_marketing_roi,
    AVG(CAST(f.roas AS DECIMAL(18,4))) AS avg_roas,
    AVG(CAST(f.cost_per_unit AS DECIMAL(18,4))) AS avg_cost_per_unit,
    AVG(CAST(f.engagement_rate AS DECIMAL(18,4))) AS avg_engagement_rate,
    AVG(CAST(f.campaign_efficiency AS DECIMAL(18,4))) AS avg_campaign_efficiency
FROM dw.fact_marketing_daily f
LEFT JOIN dw.dim_date d
    ON f.date_sk = d.date_sk
GROUP BY
    f.event_date,
    d.calendar_year,
    d.calendar_quarter,
    d.calendar_month,
    d.month_name;
GO


/* =========================================================
   9) CAMPAIGN SUMMARY VIEW
   PURPOSE:
     Campaign-level rollup for Power BI analysis
   ========================================================= */
IF OBJECT_ID('mart.vw_campaign_summary', 'V') IS NOT NULL
    DROP VIEW mart.vw_campaign_summary;
GO

CREATE VIEW mart.vw_campaign_summary
AS
SELECT
    c.campaign_sk,
    c.source_campaign_key AS campaign_key,
    c.campaign_name,
    c.campaign_type,
    c.offer_type,
    c.promotion_flag,

    COUNT(*) AS fact_rows,
    SUM(ISNULL(f.sales_units, 0)) AS total_sales_units,
    SUM(ISNULL(f.marketing_spend, 0)) AS total_marketing_spend,
    SUM(ISNULL(f.gross_revenue, 0)) AS total_gross_revenue,
    SUM(ISNULL(f.total_cost, 0)) AS total_total_cost,
    SUM(ISNULL(f.gross_profit, 0)) AS total_gross_profit,
    SUM(ISNULL(f.campaign_revenue, 0)) AS total_campaign_revenue,

    AVG(CAST(f.marketing_roi AS DECIMAL(18,4))) AS avg_marketing_roi,
    AVG(CAST(f.roas AS DECIMAL(18,4))) AS avg_roas,
    AVG(CAST(f.engagement_rate AS DECIMAL(18,4))) AS avg_engagement_rate,
    AVG(CAST(f.campaign_efficiency AS DECIMAL(18,4))) AS avg_campaign_efficiency
FROM dw.fact_marketing_daily f
LEFT JOIN dw.dim_campaign c
    ON f.campaign_sk = c.campaign_sk
GROUP BY
    c.campaign_sk,
    c.source_campaign_key,
    c.campaign_name,
    c.campaign_type,
    c.offer_type,
    c.promotion_flag;
GO


/* =========================================================
   10) VIEW VALIDATION
   ========================================================= */
SELECT
    TABLE_SCHEMA,
    TABLE_NAME
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'mart'
ORDER BY TABLE_NAME;
GO
