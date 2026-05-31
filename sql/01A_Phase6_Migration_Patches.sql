USE MarketingDW;
GO

-- Force watermark to exact max ingestion timestamp from DW (keeps milliseconds)
UPDATE etl.WatermarkControl
SET last_loaded_ts = (SELECT MAX(silver_ingestion_timestamp) FROM dw.fact_marketing_daily),
    last_run_utc    = SYSUTCDATETIME()
WHERE pipeline_name = 'MarketingDW_Pipeline';
GO

-- Show the exact value (must end with milliseconds, not .0000000)
SELECT pipeline_name, last_loaded_ts
FROM etl.WatermarkControl
WHERE pipeline_name = 'MarketingDW_Pipeline';
GO
