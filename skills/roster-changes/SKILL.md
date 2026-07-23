---
name: roster-changes
description: Shows new hires, transfers in, and transfers out from Workday within a configurable lookback window (default 14 days). Accepts an optional number of days to adjust the window. Returns one row per person per event with a roster_status label.
metadata:
  type: process-check
  domain: RevOps
  sources:
    - SNOW_CERTIFIED.EMPLOYEE.D_EMPLOYEE_WORKDAY
    - SNOW_CERTIFIED.EMPLOYEE.SNP_EMPLOYEE_WORKDAY
---

# Skill: Roster Changes — New Hires and Transfers

## Purpose
Surfaces all Workday employee changes within a rolling lookback window so RevOps can identify:
- **New Hires** who need Pigment roster entries, SFDC users, and comp plans created
- **Transfers In** who may need territory or quota updates
- **Transfers Out** whose records may need to be deactivated or reassigned

## Inputs

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `lookback_days` | integer | optional | 14 | Number of days back from today to check for changes |

## Output columns

| Column | Description |
|---|---|
| `WORKDAY_EMPLOYEE_ID` | Workday EEID |
| `EMPLOYEE_NAME` | Preferred name |
| `EMPLOYEE_EMAIL` | Work email |
| `EMPLOYEE_BUSINESS_TITLE` | Current business title |
| `EVENT_DATE` | Hire date (new hires) or SCD2 effective date (transfers) |
| `EMPLOYEE_MANAGER_NAME` | Current manager |
| `EMPLOYEE_COUNTRY` | Work country |
| `EMPLOYEE_LOCATION` | Work location code |
| `ROSTER_STATUS` | `New Hire`, `Transfer In`, or `Transfer Out` |
| `TRANSFER_FROM` | Department / cost center they left (transfers only) |
| `TRANSFER_TO` | Department / cost center they joined (transfers only) |

## Roster status logic

| Status | Source | Condition |
|---|---|---|
| `New Hire` | `D_EMPLOYEE_WORKDAY` (current state) | `EMPLOYEE_HIRE_DATE_AT >= CURRENT_DATE - :lookback_days` |
| `Transfer In` | `SNP_EMPLOYEE_WORKDAY` (SCD2 history) | New row with `VALID_FROM >= CURRENT_DATE - :lookback_days` AND `IS_EMPLOYEE_TRANSFERRED = TRUE` AND `EMPLOYEE_TRANSFER_IN_DEPARTMENT` is populated |
| `Transfer Out` | `SNP_EMPLOYEE_WORKDAY` (SCD2 history) | New row with `VALID_FROM >= CURRENT_DATE - :lookback_days` AND `IS_EMPLOYEE_TRANSFERRED = TRUE` AND only `EMPLOYEE_TRANSFER_OUT_DEPARTMENT` is populated |

## SQL

```sql
-- ROSTER CHANGES: New hires and transfers from Workday
-- Default window: last 14 days. Change the number below to adjust.
-- Swap :lookback_days for any integer (e.g. 7 for weekly, 30 for monthly)

WITH new_hires AS (
    SELECT
        w.WORKDAY_EMPLOYEE_ID,
        w.EMPLOYEE_PREFERRED_NAME               AS employee_name,
        w.EMPLOYEE_EMAIL,
        w.EMPLOYEE_BUSINESS_TITLE,
        w.EMPLOYEE_HIRE_DATE_AT                 AS event_date,
        w.EMPLOYEE_MANAGER_NAME,
        w.EMPLOYEE_COUNTRY,
        w.EMPLOYEE_LOCATION,
        'New Hire'                              AS roster_status,
        NULL                                    AS transfer_from,
        NULL                                    AS transfer_to
    FROM SNOW_CERTIFIED.EMPLOYEE.D_EMPLOYEE_WORKDAY w
    WHERE w.EMPLOYEE_HIRE_DATE_AT >= CURRENT_DATE - 14   -- replace 14 with :lookback_days
      AND w.IS_EMPLOYEE_ACTIVE = TRUE
),
transfers AS (
    SELECT
        s.WORKDAY_EMPLOYEE_ID,
        s.EMPLOYEE_PREFERRED_NAME               AS employee_name,
        s.EMPLOYEE_EMAIL,
        s.EMPLOYEE_BUSINESS_TITLE,
        s.VALID_FROM                            AS event_date,
        s.EMPLOYEE_MANAGER_NAME,
        s.EMPLOYEE_COUNTRY,
        s.EMPLOYEE_LOCATION,
        CASE
            WHEN s.EMPLOYEE_TRANSFER_OUT_DEPARTMENT IS NOT NULL
             AND s.EMPLOYEE_TRANSFER_IN_DEPARTMENT  IS NOT NULL THEN 'Transfer In'
            WHEN s.EMPLOYEE_TRANSFER_OUT_DEPARTMENT IS NOT NULL THEN 'Transfer Out'
            ELSE 'Transfer In'
        END                                     AS roster_status,
        COALESCE(s.EMPLOYEE_TRANSFER_OUT_DEPARTMENT,
                 s.EMPLOYEE_TRANSFER_OUT_COST_CENTER)   AS transfer_from,
        COALESCE(s.EMPLOYEE_TRANSFER_IN_DEPARTMENT,
                 s.EMPLOYEE_TRANSFER_IN_COST_CENTER)    AS transfer_to
    FROM SNOW_CERTIFIED.EMPLOYEE.SNP_EMPLOYEE_WORKDAY s
    WHERE s.IS_EMPLOYEE_TRANSFERRED = TRUE
      AND s.VALID_FROM >= CURRENT_DATE - 14     -- replace 14 with :lookback_days
)
SELECT
    WORKDAY_EMPLOYEE_ID,
    employee_name,
    EMPLOYEE_EMAIL,
    EMPLOYEE_BUSINESS_TITLE,
    event_date,
    EMPLOYEE_MANAGER_NAME,
    EMPLOYEE_COUNTRY,
    EMPLOYEE_LOCATION,
    roster_status,
    transfer_from,
    transfer_to
FROM new_hires
UNION ALL
SELECT
    WORKDAY_EMPLOYEE_ID,
    employee_name,
    EMPLOYEE_EMAIL,
    EMPLOYEE_BUSINESS_TITLE,
    event_date,
    EMPLOYEE_MANAGER_NAME,
    EMPLOYEE_COUNTRY,
    EMPLOYEE_LOCATION,
    roster_status,
    transfer_from,
    transfer_to
FROM transfers
ORDER BY event_date DESC, roster_status, employee_name
;
```

## Usage examples

**Default 14-day window:**
```
Show me all new hires and transfers from the last 2 weeks.
```

**Custom window:**
```
Show me all roster changes from the last 7 days.
```
```
Show me all roster changes from the last 30 days.
```

**Filter to a specific status:**
```
Show me only new hires from the last 14 days.
```
```
Show me only transfers in from the last 14 days.
```
