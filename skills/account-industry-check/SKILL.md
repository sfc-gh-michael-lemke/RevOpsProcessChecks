---
name: account-industry-check
description: QC check returning INDUSTRY_C status for one or more SFDC accounts. Given an account ID, account name, territory, or owner ID, returns the account-level industry classification with a populated/missing flag and all available fallback industry values. Run to identify which accounts need INDUSTRY_C set and what data already exists to assist classification.
metadata:
  type: process-check
  domain: RevOps
  sources:
    - FIVETRAN.SALESFORCE.ACCOUNT
---

# Skill: Account Industry Check

## Purpose
Returns the `INDUSTRY_C` status for SFDC accounts. Surfaces missing classifications and shows all available fallback industry fields (standard SFDC industry, DiscoverOrg, Marketing) so you can quickly determine what value should be set.

## Inputs

| Parameter | Type | Required | Description |
|---|---|---|---|
| `account_id` | string | optional | Filter to a single SFDC Account ID (18-char) |
| `account_name` | string | optional | Filter by account name (partial match supported with ILIKE) |
| `territory` | string | optional | Filter to all accounts in a specific territory |
| `sfdc_owner_id` | string | optional | Filter to all accounts owned by a specific SFDC User ID |
| `account_type` | string | optional | Filter by account type (e.g. `Customer`, `Prospect`) |

If no parameters are provided, the skill returns **all accounts missing `INDUSTRY_C`**, sorted by revenue descending.

## Output columns

| Column | Description |
|---|---|
| `ACCOUNT_ID` | SFDC Account ID |
| `ACCOUNT_NAME` | Account name |
| `ACCOUNT_TYPE` | SFDC account type |
| `TERRITORY` | Assigned territory |
| `OWNER_ID` | SFDC User ID of the account owner |
| `INDUSTRY_C` | Snowflake custom industry classification (the field being checked) |
| `INDUSTRY_POPULATED` | TRUE if `INDUSTRY_C` is set, FALSE if missing |
| `SFDC_INDUSTRY_STANDARD` | Standard SFDC `INDUSTRY` picklist value |
| `DISCOVERORG_INDUSTRY` | DiscoverOrg-enriched industry |
| `MARKETING_INDUSTRY` | Marketing-tagged industry |
| `INDUSTRY_SPECIALIZATION_C` | Industry specialization field |
| `NUMBER_OF_EMPLOYEES` | Headcount |
| `ANNUAL_REVENUE` | Annual revenue |
| `BILLING_COUNTRY` | Billing country |
| `CREATED_DATE` | Account creation date |

## SQL

```sql
-- ACCOUNT INDUSTRY CHECK: SFDC accounts — INDUSTRY_C status with fallback fields
-- Optional filters: uncomment relevant lines below
-- If no filters are set, returns all accounts missing INDUSTRY_C (sorted by revenue desc)

SELECT
    a.ID                            AS account_id,
    a.NAME                          AS account_name,
    a.TYPE                          AS account_type,
    a.TERRITORY_C                   AS territory,
    a.OWNER_ID,
    a.INDUSTRY_C,
    CASE
        WHEN a.INDUSTRY_C IS NOT NULL AND a.INDUSTRY_C != '' THEN TRUE
        ELSE FALSE
    END                             AS industry_populated,
    a.INDUSTRY                      AS sfdc_industry_standard,
    a.DISCOVER_ORG_INDUSTRY_C       AS discoverorg_industry,
    a.MARKETING_INDUSTRY_C          AS marketing_industry,
    a.INDUSTRY_SPECIALIZATION_C,
    a.NUMBER_OF_EMPLOYEES,
    a.ANNUAL_REVENUE,
    a.BILLING_COUNTRY,
    a.CREATED_DATE
FROM FIVETRAN.SALESFORCE.ACCOUNT a
WHERE a._FIVETRAN_DELETED = FALSE
  -- OPTIONAL FILTERS — uncomment to scope:
  -- AND a.ID           = ':account_id'
  -- AND a.NAME         ILIKE '%:account_name%'
  -- AND a.TERRITORY_C  = ':territory'
  -- AND a.OWNER_ID     = ':sfdc_owner_id'
  -- AND a.TYPE         = ':account_type'
  -- Remove the line below to see ALL accounts, not just missing ones:
  AND (a.INDUSTRY_C IS NULL OR a.INDUSTRY_C = '')
ORDER BY a.ANNUAL_REVENUE DESC NULLS LAST, a.NUMBER_OF_EMPLOYEES DESC NULLS LAST
;
```

## Usage examples

**All accounts missing INDUSTRY_C (default):**
```
Run the account industry check.
```

**Single account by ID:**
```
Run the account industry check for account_id = 001VI00000Z6DL0YAN.
```

**Single account by name:**
```
Run the account industry check for account_name = Snowflake.
```

**All accounts in a territory:**
```
Run the account industry check for territory = AMSExpansion_ENT_NorCal_01.
```

**All accounts for a specific owner:**
```
Run the account industry check for sfdc_owner_id = 0050Z000009XpMpQAK.
```

**Check a specific account regardless of whether industry is set (remove the missing-only filter):**
```
Run the account industry check for account_id = 001VI00000Z6DL0YAN — show all fields even if industry is populated.
```
(Remove the `AND (a.INDUSTRY_C IS NULL OR a.INDUSTRY_C = '')` line from the SQL)

## Notes
- `INDUSTRY_C` is the Snowflake custom industry field used for RevOps reporting and territory alignment. It is distinct from the standard SFDC `INDUSTRY` picklist.
- When `INDUSTRY_C` is missing, check `SFDC_INDUSTRY_STANDARD`, `DISCOVERORG_INDUSTRY`, and `MARKETING_INDUSTRY` in that order as candidates to backfill from.
- As of the latest snapshot: **~36,852 accounts** are missing `INDUSTRY_C`.
