# RevOpsProcessChecks

Snowflake SQL QC checks for RevOps data integrity. Compares Pigment, Workday, and Salesforce to surface mismatches, missing classifications, and roster changes before they cause downstream issues in territory planning, comp, and reporting.

## Structure

```
RevOpsProcessChecks/
├── verified_queries/          # Single-purpose SQL lookups (one query per file)
└── skills/                    # CoCo skills — multi-source QC checks and orchestrators
```

---

## Skills

### `daily-revops-digest`
Orchestrates all active QC checks in sequence and outputs a prioritized next-steps list. Run every morning.
```
Run the daily RevOps digest.
```
→ [`skills/daily-revops-digest/SKILL.md`](skills/daily-revops-digest/SKILL.md)

---

### `territory-profile-match`
Compares `TERRITORY_PROFILE` between Pigment and SFDC for the full specialist roster. Flags mismatches with short reason codes.

| Label | Meaning |
|---|---|
| `PIGMENT_ONLY` | Pigment has a value, SFDC is blank |
| `SFDC_ONLY` | SFDC has a value, Pigment is blank |
| `VALUE_CONFLICT` | Both populated but disagree |
| `NO_SFDC_USER` | No active SFDC user found |

**Input:** `workday_employee_id` or `sfdc_user_id` (optional — omit for full roster)
→ [`skills/territory-profile-match/SKILL.md`](skills/territory-profile-match/SKILL.md)

---

### `se-group-populated`
Checks whether `SE_GROUP` and `SE_SUB_GROUP` are both set for each active specialist. Missing values break downstream reporting and territory assignment.

| Label | Meaning |
|---|---|
| `SE_SUB_GROUP_MISSING` | SE_GROUP set but sub-group blank |
| `SE_GROUP_MISSING` | SE_GROUP not set |
| `BOTH_MISSING` | Full classification needed |

**Input:** `workday_employee_id` (optional — omit for full roster)
→ [`skills/se-group-populated/SKILL.md`](skills/se-group-populated/SKILL.md)

---

### `roster-changes`
Shows new hires, transfers in, and transfers out from Workday within a rolling lookback window (default 14 days).

| Status | Trigger |
|---|---|
| `New Hire` | `EMPLOYEE_HIRE_DATE_AT` within window |
| `Transfer In` | New SCD2 row with `EMPLOYEE_TRANSFER_IN_DEPARTMENT` populated |
| `Transfer Out` | New SCD2 row with only `EMPLOYEE_TRANSFER_OUT_DEPARTMENT` populated |

**Input:** `lookback_days` (optional, default 14)
→ [`skills/roster-changes/SKILL.md`](skills/roster-changes/SKILL.md)

---

### `bonus-commission-match` ⚠️ Temporarily excluded
Compares bonus and commission eligibility between Workday (`BONUS_TARGET_PERCENT`) and Pigment (`BONUS_MULTI_YEAR`, `COMMISSION_ANNUAL_TARGET_USD`). Blocked pending `SNOW_CERTIFIED_SENSITIVE` access.

→ [`skills/bonus-commission-match/SKILL.md`](skills/bonus-commission-match/SKILL.md)

---

### `account-industry-check`
Returns `INDUSTRY_C` status for SFDC accounts. Surfaces missing classifications and shows all available fallback industry fields to assist backfill. Default returns all ~36,852 accounts missing `INDUSTRY_C`, sorted by revenue.

**Input:** `account_id`, `account_name`, `territory`, `sfdc_owner_id`, or `account_type` (all optional)
→ [`skills/account-industry-check/SKILL.md`](skills/account-industry-check/SKILL.md)

---

## Verified Queries

Single-purpose SQL lookups. Parameterize by replacing the placeholder values.

| File | Description | Key filter |
|---|---|---|
| [`pigment_territory_by_user.sql`](verified_queries/pigment_territory_by_user.sql) | Full territory hierarchy from Pigment roster | `EEID`, email, or SFDC User ID |
| [`sfdc_territory_by_user.sql`](verified_queries/sfdc_territory_by_user.sql) | Territory profile from SFDC User object | SFDC User ID or email |
| [`workday_bonus_eligibility_by_employee.sql`](verified_queries/workday_bonus_eligibility_by_employee.sql) | Bonus eligibility from Workday compensation | `workday_employee_id` |
| [`pigment_bonus_commission_eligibility_by_employee.sql`](verified_queries/pigment_bonus_commission_eligibility_by_employee.sql) | Bonus and commission eligibility from Pigment | `workday_employee_id` |
| [`workday_new_hires_and_transfers_last_14_days.sql`](verified_queries/workday_new_hires_and_transfers_last_14_days.sql) | New hires and transfers from Workday (last 14 days) | Adjust lookback window |
| [`se_group_populated_check.sql`](verified_queries/se_group_populated_check.sql) | SE group and sub-group population per specialist | `workday_employee_id` (optional) |
| [`pigment_specialists_with_mbo_comp_plan.sql`](verified_queries/pigment_specialists_with_mbo_comp_plan.sql) | Employees with MBO / Quarterly Measures in comp plan | Covers both Sales and Partner rosters |
| [`sfdc_accounts_missing_industry.sql`](verified_queries/sfdc_accounts_missing_industry.sql) | SFDC accounts missing `INDUSTRY_C` | `territory`, `owner_id`, `account_type` (optional) |

---

## Mismatch reason labels (all skills)

| Label | Meaning |
|---|---|
| `PIGMENT_ONLY` | Pigment has a value, SFDC is blank |
| `SFDC_ONLY` | SFDC has a value, Pigment is blank |
| `VALUE_CONFLICT` | Both systems have values but they disagree |
| `NO_SFDC_USER` | No active SFDC user record found |
| `SE_SUB_GROUP_MISSING` | SE_GROUP set, sub-group blank |
| `BOTH_MISSING` | Neither field populated |
| `BONUS_CONFLICT` | Workday and Pigment disagree on bonus status |
| `PIGMENT_NO_PLAN` | Employee active in Workday but not in Pigment quota plan |
| `WORKDAY_NO_COMP` | Employee in Pigment plan but not in Workday comp table |

---

## Quick reference

| Resource | Link |
|---|---|
| GitHub repo | https://github.com/sfc-gh-michael-lemke/RevOpsProcessChecks |
| SFDC User Management | https://snowflake.lightning.force.com/lightning/setup/ManageUsers/home |
| Pigment | https://app.pigment.com |
| Xactly Connect | https://connect.xactlycorp.com |
