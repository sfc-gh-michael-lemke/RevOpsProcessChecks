---
name: daily-revops-digest
description: Daily RevOps process health digest. Runs all active QC checks in sequence, summarizes findings, and outputs a prioritized next-steps list with links and fix instructions. Run every morning before standup or planning work. Note: bonus-commission-match is temporarily excluded pending SNOW_CERTIFIED_SENSITIVE access.
metadata:
  type: orchestrator
  domain: RevOps
  cadence: daily
  skills:
    - territory-profile-match
    - se-group-populated
    - roster-changes
    # - bonus-commission-match  (excluded: SNOW_CERTIFIED_SENSITIVE access pending)
---

# Skill: Daily RevOps Process Health Digest

## Purpose
One command to run all RevOps QC checks and get a consolidated status report. Each check returns a pass/fail summary. Failures bubble up to a prioritized next-steps list so you know exactly what to fix and where.

## Inputs
None required. All checks run with defaults (last 14 days for roster changes).

## How to run
```
Run the daily RevOps digest.
```

---

## Step 1 — Territory Profile Match

Run this SQL and capture the summary:

```sql
-- SUMMARY: Pigment vs SFDC Territory Profile Match
WITH specialist_roster AS (
    SELECT se.WORKDAY_EMPLOYEE_ID, se.SALESFORCE_USER_ID, se.EMPLOYEE_NAME,
           se.SE_GROUP, se.THEATER,
           se.TERRITORY_PROFILE AS pig_territory_profile
    FROM SNOW_CERTIFIED.SOLUTION_ENGINEERING.DD_SOLUTION_ENGINEERING_WORKDAY_HIERARCHY se
    WHERE se.SE_GROUP IN ('Architect','AFE','PSE','Mgmt','PSE/AFE','Leadership')
      AND se.IS_EMPLOYEE_ACTIVE = TRUE
),
sfdc AS (
    SELECT u.ID AS sfdc_user_id, u.TERRITORY_PROFILE_C AS sfdc_territory_profile
    FROM FIVETRAN.SALESFORCE.USER u
    WHERE u._FIVETRAN_DELETED = FALSE AND u.IS_ACTIVE = TRUE
)
SELECT
    CASE
        WHEN f.sfdc_user_id IS NULL                                                       THEN 'NO_SFDC_USER'
        WHEN s.pig_territory_profile IS NOT NULL AND f.sfdc_territory_profile IS NULL     THEN 'PIGMENT_ONLY'
        WHEN s.pig_territory_profile IS NULL     AND f.sfdc_territory_profile IS NOT NULL THEN 'SFDC_ONLY'
        WHEN s.pig_territory_profile != f.sfdc_territory_profile                          THEN 'VALUE_CONFLICT'
        ELSE 'MATCH'
    END AS mismatch_reason,
    COUNT(*) AS specialist_count
FROM specialist_roster s
LEFT JOIN sfdc f ON s.SALESFORCE_USER_ID = f.sfdc_user_id
GROUP BY 1
ORDER BY specialist_count DESC;
```

**Pass condition:** All rows show `MATCH`.

**If failures exist — next steps:**

| Reason | Fix | Where |
|---|---|---|
| `PIGMENT_ONLY` | Update `TERRITORY_PROFILE_C` on the SFDC User record to match Pigment | [SFDC User Edit](https://snowflake.lightning.force.com/lightning/setup/ManageUsers/home) |
| `SFDC_ONLY` | Verify the Pigment roster entry has the correct Territory Profile | [Pigment Roster](https://app.pigment.com) |
| `VALUE_CONFLICT` | Compare both values and align to the planning source of truth (Pigment) | Both systems |
| `NO_SFDC_USER` | Provision a Salesforce user for the employee | [SFDC User Create](https://snowflake.lightning.force.com/lightning/setup/ManageUsers/home) |

Full detail query: [`territory-profile-match`](../territory-profile-match/SKILL.md)
Verified lookups: [`pigment_territory_by_user.sql`](../../verified_queries/pigment_territory_by_user.sql) · [`sfdc_territory_by_user.sql`](../../verified_queries/sfdc_territory_by_user.sql)

---

## Step 2 — SE Group Populated

Run this SQL and capture the summary:

```sql
-- SUMMARY: SE Group and Sub-group Population
SELECT
    CASE
        WHEN se.SE_GROUP    IS NULL AND se.SE_SUB_GROUP IS NULL THEN 'BOTH_MISSING'
        WHEN se.SE_GROUP    IS NULL                             THEN 'SE_GROUP_MISSING'
        WHEN se.SE_SUB_GROUP IS NULL                            THEN 'SE_SUB_GROUP_MISSING'
        ELSE 'POPULATED'
    END AS status,
    COUNT(*) AS specialist_count
FROM SNOW_CERTIFIED.SOLUTION_ENGINEERING.DD_SOLUTION_ENGINEERING_WORKDAY_HIERARCHY se
WHERE se.SE_GROUP IN ('Architect','AFE','PSE','Mgmt','PSE/AFE','Leadership')
  AND se.IS_EMPLOYEE_ACTIVE = TRUE
GROUP BY 1
ORDER BY specialist_count DESC;
```

**Pass condition:** All rows show `POPULATED`.

**If failures exist — next steps:**

| Reason | Fix | Where |
|---|---|---|
| `SE_SUB_GROUP_MISSING` | Set the specialist sub-group in Pigment specialist attributes | [Pigment Specialist Attributes](https://app.pigment.com) |
| `SE_GROUP_MISSING` / `BOTH_MISSING` | Set SE_GROUP classification for the employee | [Pigment Roster](https://app.pigment.com) |

Full detail query: [`se-group-populated`](../se-group-populated/SKILL.md)
Verified lookup: [`se_group_populated_check.sql`](../../verified_queries/se_group_populated_check.sql)

---

## Step 3 — Roster Changes (Last 14 Days)

Run this SQL and review new entries:

```sql
-- SUMMARY: New hires and transfers in the last 14 days
WITH new_hires AS (
    SELECT 'New Hire' AS roster_status, EMPLOYEE_PREFERRED_NAME AS employee_name,
           EMPLOYEE_EMAIL, EMPLOYEE_HIRE_DATE_AT AS event_date
    FROM SNOW_CERTIFIED.EMPLOYEE.D_EMPLOYEE_WORKDAY
    WHERE EMPLOYEE_HIRE_DATE_AT >= CURRENT_DATE - 14
      AND IS_EMPLOYEE_ACTIVE = TRUE
),
transfers AS (
    SELECT
        CASE
            WHEN EMPLOYEE_TRANSFER_OUT_DEPARTMENT IS NOT NULL
             AND EMPLOYEE_TRANSFER_IN_DEPARTMENT  IS NOT NULL THEN 'Transfer In'
            WHEN EMPLOYEE_TRANSFER_OUT_DEPARTMENT IS NOT NULL THEN 'Transfer Out'
            ELSE 'Transfer In'
        END AS roster_status,
        EMPLOYEE_PREFERRED_NAME AS employee_name,
        EMPLOYEE_EMAIL,
        VALID_FROM AS event_date
    FROM SNOW_CERTIFIED.EMPLOYEE.SNP_EMPLOYEE_WORKDAY
    WHERE IS_EMPLOYEE_TRANSFERRED = TRUE
      AND VALID_FROM >= CURRENT_DATE - 14
)
SELECT roster_status, COUNT(*) AS count
FROM (SELECT roster_status FROM new_hires UNION ALL SELECT roster_status FROM transfers)
GROUP BY 1 ORDER BY count DESC;
```

**Pass condition:** No new hires or transfers (quiet week). Any results require action.

**If results exist — next steps per status:**

| Status | Action checklist |
|---|---|
| `New Hire` | 1. Add to Pigment roster · 2. Create SFDC user · 3. Assign territory profile · 4. Set SE_GROUP / SE_SUB_GROUP · 5. Create comp plan in Pigment |
| `Transfer In` | 1. Update Pigment territory profile · 2. Update SFDC Territory_Profile_C · 3. Confirm SE_GROUP/SE_SUB_GROUP is correct for new role |
| `Transfer Out` | 1. Deactivate or reassign in Pigment · 2. Deactivate SFDC user if needed · 3. Reassign open use cases |

Full detail query: [`roster-changes`](../roster-changes/SKILL.md)
Verified lookup: [`workday_new_hires_and_transfers_last_14_days.sql`](../../verified_queries/workday_new_hires_and_transfers_last_14_days.sql)

---

## Step 4 — Bonus / Commission Match ⚠️ TEMPORARILY EXCLUDED

> **Access blocked:** This check requires `SNOW_CERTIFIED_SENSITIVE` role access which is not yet provisioned.
> Re-enable once access is confirmed by uncommenting `bonus-commission-match` in the metadata and restoring this step.
>
> Skill is ready: [`bonus-commission-match`](../bonus-commission-match/SKILL.md)
> Verified queries: [`pigment_bonus_commission_eligibility_by_employee.sql`](../../verified_queries/pigment_bonus_commission_eligibility_by_employee.sql) · [`workday_bonus_eligibility_by_employee.sql`](../../verified_queries/workday_bonus_eligibility_by_employee.sql)

---

## Consolidated next-steps template

After running all three active checks, copy this template into your standup notes or Jira:

```
## RevOps Daily QC — [DATE]

### Territory Profile Match
- [ ] PIGMENT_ONLY: X specialists — update SFDC TERRITORY_PROFILE_C
- [ ] SFDC_ONLY: X specialists — verify Pigment roster
- [ ] VALUE_CONFLICT: X specialists — manual triage
- [ ] NO_SFDC_USER: X specialists — provision SFDC user

### SE Group Population
- [ ] SE_SUB_GROUP_MISSING: X specialists — set sub-group in Pigment
- [ ] SE_GROUP_MISSING: X specialists — set classification in Pigment

### Roster Changes (last 14 days)
- [ ] New Hires: X — run onboarding checklist for each
- [ ] Transfers In: X — update territory + SE_GROUP
- [ ] Transfers Out: X — deactivate / reassign records

### Bonus / Commission (Pigment)
- [ ] SKIPPED — pending SNOW_CERTIFIED_SENSITIVE access (re-enable Step 4 when resolved)
```

---

## Quick reference — repo links

| Resource | Link |
|---|---|
| GitHub repo | https://github.com/sfc-gh-michael-lemke/RevOpsProcessChecks |
| Territory Profile Match skill | https://github.com/sfc-gh-michael-lemke/RevOpsProcessChecks/blob/main/skills/territory-profile-match/SKILL.md |
| SE Group Populated skill | https://github.com/sfc-gh-michael-lemke/RevOpsProcessChecks/blob/main/skills/se-group-populated/SKILL.md |
| Roster Changes skill | https://github.com/sfc-gh-michael-lemke/RevOpsProcessChecks/blob/main/skills/roster-changes/SKILL.md |
| Bonus Commission Match skill | https://github.com/sfc-gh-michael-lemke/RevOpsProcessChecks/blob/main/skills/bonus-commission-match/SKILL.md |
| All verified queries | https://github.com/sfc-gh-michael-lemke/RevOpsProcessChecks/tree/main/verified_queries |
| SFDC User Management | https://snowflake.lightning.force.com/lightning/setup/ManageUsers/home |
| Pigment | https://app.pigment.com |
| Xactly Connect | https://connect.xactlycorp.com |
