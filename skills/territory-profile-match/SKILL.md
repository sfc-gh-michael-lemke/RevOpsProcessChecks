---
name: territory-profile-match
description: QC check comparing Pigment vs SFDC territory profile for the specialist roster. Accepts a Workday Employee ID or SFDC User ID to filter to a single person, or runs across the full specialist roster when no ID is supplied.
metadata:
  type: process-check
  domain: RevOps
  sources:
    - SNOW_CERTIFIED.SOLUTION_ENGINEERING.DD_SOLUTION_ENGINEERING_WORKDAY_HIERARCHY
    - IT.PIGMENT.PIGMENT_ROSTER
    - FIVETRAN.SALESFORCE.USER
    - FIVETRAN.SALESFORCE.USER_TERRITORY_2_ASSOCIATION
    - FIVETRAN.SALESFORCE.TERRITORY_2
---

# Skill: Territory Profile Match — Pigment vs SFDC

## Purpose
Checks whether the `TERRITORY_PROFILE` field for each specialist is consistent between **Pigment** (source of truth for planning) and **Salesforce** (`TERRITORY_PROFILE_C`). Flags mismatches so RevOps can correct the downstream system.

## Inputs

| Parameter | Type | Required | Description |
|---|---|---|---|
| `workday_employee_id` | integer | optional | Workday EEID — filters to one person |
| `sfdc_user_id` | string | optional | Salesforce User ID (18-char) — filters to one person |

If neither parameter is provided, the check runs across the **full specialist roster**.

## Output columns

| Column | Description |
|---|---|
| `EMPLOYEE_NAME` | Employee preferred name |
| `USER_ID` | Salesforce User ID |
| `SFDC_TERRITORY_ID` | Territory 2 ID(s) from SFDC ETM (comma-separated if multiple) |
| `SFDC_TERRITORY_NAME` | Territory name(s) from SFDC ETM (comma-separated if multiple) |
| `TERRITORY_PROFILE_MATCH` | TRUE if Pigment and SFDC agree (including both null), FALSE otherwise |
| `MISMATCH_REASON` | Short label explaining why the row is FALSE (see table below) |

## Mismatch reason labels

| Label | Meaning | Likely action |
|---|---|---|
| `PIGMENT_ONLY` | Pigment has a value, SFDC is blank | Update SFDC `TERRITORY_PROFILE_C` |
| `SFDC_ONLY` | SFDC has a value, Pigment is blank | Verify Pigment roster entry |
| `VALUE_CONFLICT` | Both have values but they disagree | Triage — determine which is correct |
| `NO_SFDC_USER` | No active SFDC user record found for this employee | Check SFDC user provisioning |

Rows where `MISMATCH_REASON` is `NULL` are matches — no action needed.

## SQL

```sql
-- QC CHECK: Specialist Roster — Pigment vs SFDC Territory Profile Match
-- Optional filters:
--   To run for one person by Workday ID: add  AND se.WORKDAY_EMPLOYEE_ID = :workday_employee_id
--   To run for one person by SFDC ID:    add  AND se.SALESFORCE_USER_ID  = ':sfdc_user_id'

WITH specialist_roster AS (
    SELECT
        se.WORKDAY_EMPLOYEE_ID,
        se.SALESFORCE_USER_ID,
        se.EMPLOYEE_NAME,
        se.EMPLOYEE_EMAIL,
        se.SE_GROUP,
        se.SE_SUB_GROUP,
        se.THEATER,
        se.TERRITORY_PROFILE    AS pig_territory_profile
    FROM SNOW_CERTIFIED.SOLUTION_ENGINEERING.DD_SOLUTION_ENGINEERING_WORKDAY_HIERARCHY se
    WHERE se.SE_GROUP IN ('Architect','AFE','PSE','Mgmt','PSE/AFE','Leadership')
      AND se.IS_EMPLOYEE_ACTIVE = TRUE
      -- OPTIONAL: uncomment one line below to filter to a single person
      -- AND se.WORKDAY_EMPLOYEE_ID = :workday_employee_id
      -- AND se.SALESFORCE_USER_ID  = ':sfdc_user_id'
),
sfdc AS (
    SELECT
        u.ID                    AS sfdc_user_id,
        u.TERRITORY_PROFILE_C   AS sfdc_territory_profile
    FROM FIVETRAN.SALESFORCE.USER u
    WHERE u._FIVETRAN_DELETED = FALSE
      AND u.IS_ACTIVE = TRUE
),
sfdc_territory AS (
    SELECT
        uta.USER_ID,
        LISTAGG(t2.ID,   ', ') WITHIN GROUP (ORDER BY t2.NAME) AS territory_ids,
        LISTAGG(t2.NAME, ', ') WITHIN GROUP (ORDER BY t2.NAME) AS territory_names
    FROM FIVETRAN.SALESFORCE.USER_TERRITORY_2_ASSOCIATION uta
    JOIN FIVETRAN.SALESFORCE.TERRITORY_2 t2
        ON uta.TERRITORY_2_ID = t2.ID
       AND t2._FIVETRAN_DELETED = FALSE
    WHERE uta._FIVETRAN_DELETED = FALSE
      AND uta.IS_ACTIVE = TRUE
    GROUP BY uta.USER_ID
)
SELECT
    s.EMPLOYEE_NAME,
    f.sfdc_user_id                  AS user_id,
    t.territory_ids                 AS sfdc_territory_id,
    t.territory_names               AS sfdc_territory_name,
    CASE
        WHEN s.pig_territory_profile IS NULL AND f.sfdc_territory_profile IS NULL THEN TRUE
        WHEN s.pig_territory_profile = f.sfdc_territory_profile                  THEN TRUE
        ELSE FALSE
    END AS territory_profile_match,
    CASE
        WHEN f.sfdc_user_id IS NULL
            THEN 'NO_SFDC_USER'
        WHEN s.pig_territory_profile IS NOT NULL AND f.sfdc_territory_profile IS NULL
            THEN 'PIGMENT_ONLY'
        WHEN s.pig_territory_profile IS NULL AND f.sfdc_territory_profile IS NOT NULL
            THEN 'SFDC_ONLY'
        WHEN s.pig_territory_profile != f.sfdc_territory_profile
            THEN 'VALUE_CONFLICT'
        ELSE NULL
    END AS mismatch_reason
FROM specialist_roster s
LEFT JOIN sfdc f           ON s.SALESFORCE_USER_ID = f.sfdc_user_id
LEFT JOIN sfdc_territory t ON s.SALESFORCE_USER_ID = t.USER_ID
ORDER BY territory_profile_match ASC, mismatch_reason, s.THEATER, s.EMPLOYEE_NAME
;
```

## Usage examples

**Full roster check:**
```
Run the territory profile match check across all specialists.
```

**Single person by Workday ID:**
```
Run the territory profile match check for workday_employee_id = 2825.
```

**Single person by SFDC ID:**
```
Run the territory profile match check for sfdc_user_id = 0050Z000009XpMpQAK.
```
