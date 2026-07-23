-- SFDC: Accounts missing INDUSTRY_C value
-- Source: FIVETRAN.SALESFORCE.ACCOUNT
--
-- Returns all non-deleted SFDC accounts where INDUSTRY_C is null or blank.
-- INDUSTRY_C is the Snowflake custom industry field (distinct from the standard SFDC INDUSTRY field).
--
-- Also surfaces SFDC_INDUSTRY_STANDARD (INDUSTRY) and other enrichment fields
-- to help prioritize which accounts to classify first.
--
-- Input: optionally filter by TERRITORY_C or OWNER_ID to scope to a specific rep / patch

SELECT
    a.ID                            AS account_id,
    a.NAME                          AS account_name,
    a.TYPE                          AS account_type,
    a.TERRITORY_C                   AS territory,
    a.OWNER_ID,
    a.ACCOUNT_SOURCE,
    a.INDUSTRY                      AS sfdc_industry_standard,
    a.DISCOVER_ORG_INDUSTRY_C       AS discoverorg_industry,
    a.MARKETING_INDUSTRY_C          AS marketing_industry,
    a.NUMBER_OF_EMPLOYEES,
    a.ANNUAL_REVENUE,
    a.BILLING_COUNTRY,
    a.CREATED_DATE
FROM FIVETRAN.SALESFORCE.ACCOUNT a
WHERE a._FIVETRAN_DELETED = FALSE
  AND (a.INDUSTRY_C IS NULL OR a.INDUSTRY_C = '')
  -- OPTIONAL: narrow scope
  -- AND a.TERRITORY_C = ':territory'
  -- AND a.OWNER_ID    = ':sfdc_owner_id'
  -- AND a.TYPE        = 'Customer'
ORDER BY a.ANNUAL_REVENUE DESC NULLS LAST, a.NUMBER_OF_EMPLOYEES DESC NULLS LAST
;
