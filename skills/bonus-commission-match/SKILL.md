---
name: bonus-commission-match
description: QC check comparing bonus and commission eligibility between Workday and Pigment. Flags employees where the two systems disagree on comp type. Accepts a Workday Employee ID to filter to a single person, or runs across all active employees in plan when no ID is supplied.
metadata:
  type: process-check
  domain: RevOps
  sources:
    - SNOW_CERTIFIED_SENSITIVE.EMPLOYEE.D_EMPLOYEE_COMPENSATION
    - IT.PIGMENT.SALES_ROSTER_QUOTA_SUMMARY_IN_YR
    - IT.PIGMENT.PIGMENT_ROSTER
---

# Skill: Bonus / Commission Match — Workday vs Pigment

## Purpose
Checks whether Workday and Pigment agree on whether an employee is **on bonus** or **on commission**. Surfaces discrepancies so RevOps can correct the downstream system before comp plans are finalized or pushed to Xactly.

## Eligibility logic

| System | On Bonus | On Commission |
|---|---|---|
| **Workday** | `BONUS_TARGET_PERCENT > 0` OR `BONUS_TARGET_AMOUNT > 0` | Workday does not track commission directly — IC with `BONUS_TARGET_PERCENT = 0` is implicitly on commission |
| **Pigment** | `BONUS_MULTI_YEAR = TRUE` OR `BONUS_PS_T = TRUE` | `COMMISSION_ANNUAL_TARGET_USD > 0` |

## Inputs

| Parameter | Type | Required | Description |
|---|---|---|---|
| `workday_employee_id` | integer | optional | Filters to one person; omit to run full roster |

## Output columns

| Column | Description |
|---|---|
| `EMPLOYEE_NAME` | Employee preferred name |
| `EMAIL_PRIMARY_WORK` | Work email |
| `WORKDAY_EMPLOYEE_ID` | Workday EEID |
| `SFDC_USER_ID` | Salesforce User ID |
| `HC_FUNCTION` | Pigment role function (AE, SE, AFE, PSE, etc.) |
| `IC_MGR_ADMIN` | IC / Manager / Admin |
| `WD_IS_ON_BONUS` | Workday says the employee is on bonus |
| `WD_BONUS_TARGET_PCT` | Workday bonus target percent |
| `PIG_IS_BONUS_ELIGIBLE` | Pigment says bonus eligible |
| `PIG_IS_COMMISSION_ELIGIBLE` | Pigment says commission eligible |
| `PIG_COMP_TYPE` | Derived comp type from Pigment (Commission, Bonus, Commission + Bonus, Neither) |
| `BONUS_MATCH` | TRUE if Workday and Pigment agree on bonus status |
| `MISMATCH_REASON` | Short label explaining the discrepancy (NULL = match) |

## Mismatch reason labels

| Label | Meaning | Likely action |
|---|---|---|
| `BONUS_CONFLICT` | Workday says on bonus, Pigment says not; or vice versa | Reconcile bonus flag between systems |
| `PIGMENT_NO_PLAN` | Employee is in Workday but not found in Pigment quota plan | Check if Pigment roster is missing this person |
| `WORKDAY_NO_COMP` | Employee is in Pigment plan but not found in Workday compensation table | Check SNOW_CERTIFIED_SENSITIVE access or Workday record |
| `NULL` | Match — no action needed | — |

## SQL

```sql
-- QC CHECK: Bonus / Commission Match — Workday vs Pigment
-- IMPORTANT: Requires access to SNOW_CERTIFIED_SENSITIVE for Workday compensation data
-- Optional filter: uncomment AND wd.WORKDAY_EMPLOYEE_ID = :workday_employee_id

WITH workday_comp AS (
    SELECT
        c.WORKDAY_EMPLOYEE_ID,
        c.EMPLOYEE_PREFERRED_NAME,
        c.JOB_PROFILE_NAME,
        c.PAY_RATE_TYPE,
        c.BONUS_TARGET_PERCENT,
        c.BONUS_TARGET_AMOUNT,
        c.BASE_PAY_CURRENCY,
        CASE
            WHEN COALESCE(c.BONUS_TARGET_PERCENT, 0) > 0
              OR COALESCE(c.BONUS_TARGET_AMOUNT, 0)  > 0
            THEN TRUE
            ELSE FALSE
        END AS wd_is_on_bonus
    FROM SNOW_CERTIFIED_SENSITIVE.EMPLOYEE.D_EMPLOYEE_COMPENSATION c
    WHERE c.IS_EMPLOYEE_ACTIVE = TRUE
      AND c.IS_LATEST = TRUE
),
pigment_roster AS (
    SELECT
        p.EEID,
        p.EMAIL_PRIMARY_WORK,
        p.SFDC_USER_ID,
        p.HC_FUNCTION,
        p.IC_MGR_ADMIN,
        p.IN_PLAN_OUT_OF_PLAN,
        p.THEATER
    FROM IT.PIGMENT.PIGMENT_ROSTER p
    WHERE p.IS_ACTIVE = TRUE
      AND p.DS_DATE = (SELECT MAX(DS_DATE) FROM IT.PIGMENT.PIGMENT_ROSTER WHERE IS_ACTIVE = TRUE)
),
pigment_quota AS (
    SELECT
        q.EEID,
        q.EMPLOYEE_NAME,
        q.COMP_PLAN_ID,
        q.XACTLY_PLAN_STATUS,
        q.COMMISSION_ANNUAL_TARGET_USD,
        q.BONUS_MULTI_YEAR,
        q.BONUS_PS_T,
        CASE WHEN COALESCE(q.COMMISSION_ANNUAL_TARGET_USD, 0) > 0
             THEN TRUE ELSE FALSE END                        AS pig_is_commission_eligible,
        CASE WHEN COALESCE(q.BONUS_MULTI_YEAR, FALSE) = TRUE
               OR COALESCE(q.BONUS_PS_T, FALSE) = TRUE
             THEN TRUE ELSE FALSE END                        AS pig_is_bonus_eligible,
        CASE
            WHEN COALESCE(q.COMMISSION_ANNUAL_TARGET_USD, 0) > 0
             AND (COALESCE(q.BONUS_MULTI_YEAR, FALSE) = TRUE OR COALESCE(q.BONUS_PS_T, FALSE) = TRUE)
                THEN 'Commission + Bonus'
            WHEN COALESCE(q.COMMISSION_ANNUAL_TARGET_USD, 0) > 0
                THEN 'Commission'
            WHEN COALESCE(q.BONUS_MULTI_YEAR, FALSE) = TRUE OR COALESCE(q.BONUS_PS_T, FALSE) = TRUE
                THEN 'Bonus'
            ELSE 'Neither'
        END                                                  AS pig_comp_type
    FROM IT.PIGMENT.SALES_ROSTER_QUOTA_SUMMARY_IN_YR q
    WHERE q.ACTIVE_RECORD = TRUE
      AND q.DS_DATE = (SELECT MAX(DS_DATE) FROM IT.PIGMENT.SALES_ROSTER_QUOTA_SUMMARY_IN_YR WHERE ACTIVE_RECORD = TRUE)
)
SELECT
    COALESCE(pq.EMPLOYEE_NAME, wd.EMPLOYEE_PREFERRED_NAME)  AS employee_name,
    pr.EMAIL_PRIMARY_WORK,
    COALESCE(pr.EEID, wd.WORKDAY_EMPLOYEE_ID)               AS workday_employee_id,
    pr.SFDC_USER_ID,
    pr.HC_FUNCTION,
    pr.IC_MGR_ADMIN,
    pr.THEATER,
    pr.IN_PLAN_OUT_OF_PLAN,
    -- workday fields
    wd.wd_is_on_bonus,
    wd.BONUS_TARGET_PERCENT                                  AS wd_bonus_target_pct,
    wd.JOB_PROFILE_NAME                                      AS wd_job_profile,
    -- pigment fields
    pq.pig_is_bonus_eligible,
    pq.pig_is_commission_eligible,
    pq.pig_comp_type,
    pq.XACTLY_PLAN_STATUS,
    pq.COMP_PLAN_ID,
    -- match flag
    CASE
        WHEN wd.wd_is_on_bonus = pq.pig_is_bonus_eligible THEN TRUE
        ELSE FALSE
    END                                                      AS bonus_match,
    -- mismatch reason
    CASE
        WHEN pq.EEID IS NULL
            THEN 'PIGMENT_NO_PLAN'
        WHEN wd.WORKDAY_EMPLOYEE_ID IS NULL
            THEN 'WORKDAY_NO_COMP'
        WHEN wd.wd_is_on_bonus != pq.pig_is_bonus_eligible
            THEN 'BONUS_CONFLICT'
        ELSE NULL
    END                                                      AS mismatch_reason
FROM pigment_quota pq
LEFT JOIN pigment_roster pr ON pq.EEID        = pr.EEID
LEFT JOIN workday_comp   wd ON pr.EEID        = wd.WORKDAY_EMPLOYEE_ID
-- OPTIONAL: filter to a single person
-- WHERE wd.WORKDAY_EMPLOYEE_ID = :workday_employee_id
ORDER BY bonus_match ASC, mismatch_reason, pr.THEATER, pq.EMPLOYEE_NAME
;
```

## Usage examples

**Full roster check:**
```
Run the bonus commission match check across all employees.
```

**Single person by Workday ID:**
```
Run the bonus commission match check for workday_employee_id = 2825.
```

## Notes
- `SNOW_CERTIFIED_SENSITIVE` requires elevated access (sensitive data viewer role). If you receive an access error, the Workday side will be null and all rows will show `WORKDAY_NO_COMP`.
- Commission eligibility has no direct Workday counterpart. Workday tracks **bonus** only; commission plans live in Xactly. A `BONUS_CONFLICT` on an IC likely means their bonus flag in Pigment needs to be cleared, or Workday has been updated to add a bonus component.
- `XACTLY_PLAN_STATUS = 'APPROVED'` confirms the Pigment comp plan has been pushed and approved in Xactly.
