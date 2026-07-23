---
name: se-group-populated
description: QC check confirming SE_GROUP and SE_SUB_GROUP are both populated for each active specialist. Returns one row per specialist with a TRUE/FALSE flag and a missing_reason label for actionable rows. Accepts an optional Workday Employee ID to filter to a single person.
metadata:
  type: process-check
  domain: RevOps
  sources:
    - SNOW_CERTIFIED.SOLUTION_ENGINEERING.DD_SOLUTION_ENGINEERING_WORKDAY_HIERARCHY
---

# Skill: SE Group Populated Check

## Purpose
Confirms that every active specialist has both `SE_GROUP` and `SE_SUB_GROUP` populated in the SE Workday hierarchy table. Missing values indicate the specialist classification was not set during onboarding or after a transfer, which breaks downstream reporting and territory assignment logic.

## Inputs

| Parameter | Type | Required | Description |
|---|---|---|---|
| `workday_employee_id` | integer | optional | Filters to one person; omit to run full specialist roster |

## Output columns

| Column | Description |
|---|---|
| `WORKDAY_EMPLOYEE_ID` | Workday EEID |
| `SALESFORCE_USER_ID` | Salesforce User ID |
| `EMPLOYEE_NAME` | Preferred name |
| `EMPLOYEE_EMAIL` | Work email |
| `SE_GROUP` | SE group (AFE, PSE, Architect, Mgmt, etc.) |
| `SE_SUB_GROUP` | SE sub-group (AFE AI/ML, Partner SE, etc.) |
| `THEATER` | SE theater |
| `SE_GROUP_POPULATED` | TRUE if both SE_GROUP and SE_SUB_GROUP are non-null, FALSE otherwise |
| `MISSING_REASON` | Short label explaining what is missing (NULL = no issue) |

## Missing reason labels

| Label | Meaning | Likely action |
|---|---|---|
| `SE_SUB_GROUP_MISSING` | SE_GROUP is set but SE_SUB_GROUP is blank | Update sub-group in Pigment specialist attributes |
| `SE_GROUP_MISSING` | Neither field is set | Set SE_GROUP in Pigment classification |
| `BOTH_MISSING` | Both fields are null | Full classification needed |
| `NULL` | Both fields populated — no action needed | — |

## SQL

```sql
-- QC CHECK: SE group and sub-group population for specialist roster
-- Optional filter: uncomment AND se.WORKDAY_EMPLOYEE_ID = :workday_employee_id

SELECT
    se.WORKDAY_EMPLOYEE_ID,
    se.SALESFORCE_USER_ID,
    CASE
        WHEN se.SE_GROUP    IS NOT NULL
         AND se.SE_SUB_GROUP IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS se_group_populated,
    CASE
        WHEN se.SE_GROUP     IS NULL AND se.SE_SUB_GROUP IS NULL THEN 'BOTH_MISSING'
        WHEN se.SE_GROUP     IS NULL                             THEN 'SE_GROUP_MISSING'
        WHEN se.SE_SUB_GROUP IS NULL                             THEN 'SE_SUB_GROUP_MISSING'
        ELSE NULL
    END AS missing_reason
FROM SNOW_CERTIFIED.SOLUTION_ENGINEERING.DD_SOLUTION_ENGINEERING_WORKDAY_HIERARCHY se
WHERE se.SE_GROUP IN ('Architect','AFE','PSE','Mgmt','PSE/AFE','Leadership')
  AND se.IS_EMPLOYEE_ACTIVE = TRUE
  -- AND se.WORKDAY_EMPLOYEE_ID = :workday_employee_id
ORDER BY se_group_populated ASC, missing_reason, se.WORKDAY_EMPLOYEE_ID
;
```

## Usage examples

**Full roster check:**
```
Run the SE group populated check across all specialists.
```

**Single person:**
```
Run the SE group populated check for workday_employee_id = 2825.
```
