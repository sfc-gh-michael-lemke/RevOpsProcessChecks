---
name: industry-specialists-revops-checks
description: "Run RevOps configuration checks for Industry Specialist employees against Pigment tables — verifying quota, territory, ETM, baselines, targets, and specialist metadata. Use when: running RevOps checks for an industry specialist, checking if an industry specialist is onboarded correctly, validating industry roster configuration, running a readiness check before ICM sync, checking Pigment setup for a new hire, auditing the whole industry specialist org. Triggers: industry specialist revops checks, revops check, industry specialist check, industry specialist onboarding check, check industry specialist config, is my industry specialist set up, pigment check for industry, industry roster check, onboarding check industry, new hire revops check, industry specialist audit, check baselines territory ETM for industry, run the checks, industry ops check, who is not configured, who is missing baselines, who is missing targets, who is missing territory, who is missing metadata."
---

# Industry Specialists RevOps Checks

**Scope: Industry Specialists only.** These checks run against `IT.PIGMENT.RAW_INDUSTRY_ROSTER_QUOTA_SUMMARY_INYR` and `IT.PIGMENT.RAW_SPECIALIST_ATTRIBUTES_INYR` — tables that only contain Industry GTM employees (Industry Architect, Industry GTM, Industry GTM Mgmt, etc.). Do not use for AFE, PSS, SDR, AE, or other non-Industry roles.

Each check returns **PASS** or **FAIL** with detail rows on failure, including an **action needed** description for every FAIL.

---

## Onboarding Context

Based on the [New Hire Onboarding doc](https://docs.google.com/document/d/1b3Kz2ZmWCXH6BjafI55vVsoI8r7TztYIov3lWwWkQIA/edit?tab=t.0), a new Industry Specialist must complete the following steps before they are fully operational. Each maps to a test below.

| Step | What It Enables | Risk if Missing |
|------|----------------|-----------------|
| **Territories** | Account access in SFDC, consumption attribution | Reporting, Compensation, System Access |
| **ETM Alignments** | Correct org hierarchy and territory routing | Reporting, Compensation, System Access |
| **Setup Targets** | Determines target attainment | Compensation |
| **Setup Baselines** | Monthly quota basis for attainment calc | Compensation |
| **Manager Sign Off** | Approves comp plan (tracked in Pigment UI, not Snowhouse) | Compensation |
| **Field Ops Ready** | Ops team processes the plan into ICM | Compensation |
| **Metadata Updated** | Role type for Sigma access, SFDC access, reporting | Reporting, SFDC Access, Sigma Access |
| **Other** | CiQ, Attainment Dashboard, Slack (CX-Specialists) | Downstream tooling |

---

## Workflow

### Step 1: Scope — One Person or Whole Org?

⚠️ **Always ask this first** using `ask_user_question`:

```
Question: "Do you want to check one person or the whole Industry Specialist org?"
Options:
  - "One person" → ask for EEID (text input, defaultValue: "20331")
  - "Whole org"  → proceed to Step 1b before running any queries
```

**If one person:** substitute `WHERE EEID = <EEID>` in every query below.

**If whole org:** substitute `WHERE EEID IS NOT NULL AND ACTIVE_RECORD = 'TRUE'` and aggregate — show PASS/FAIL counts per test, then list every EEID that FAILs any test.

---

### Step 1b: Whole-Org Confirmation ⚠️

Before running whole-org queries, first run this count:

```sql
SELECT COUNT(DISTINCT EEID) AS total_specialists
FROM IT.PIGMENT.RAW_INDUSTRY_ROSTER_QUOTA_SUMMARY_INYR
WHERE EEID IS NOT NULL AND ACTIVE_RECORD = 'TRUE'
```

Then ask the user via `ask_user_question`:
> "Found **{total_specialists}** active Industry Specialists. This will run 6 checks across all of them. Proceed?"
> Options: "Yes, run all checks" / "Cancel"

Only continue if the user confirms.

---

### Step 2: Detect Fiscal Year Dynamically

Before running Tests 4 and 5, run this query to detect the active FY and derive all 12 month-end dates. Store these as context for the baseline checks:

```sql
SELECT
    TO_DATE(LEFT(MIN(COMP_PLAN_START_DATE), 10), 'MM/DD/YYYY')                    AS fy_start,
    LAST_DAY(DATEADD(month,  0, TO_DATE(LEFT(MIN(COMP_PLAN_START_DATE),10),'MM/DD/YYYY'))) AS m1_end,  -- FEB
    LAST_DAY(DATEADD(month,  1, TO_DATE(LEFT(MIN(COMP_PLAN_START_DATE),10),'MM/DD/YYYY'))) AS m2_end,  -- MAR
    LAST_DAY(DATEADD(month,  2, TO_DATE(LEFT(MIN(COMP_PLAN_START_DATE),10),'MM/DD/YYYY'))) AS m3_end,  -- APR
    LAST_DAY(DATEADD(month,  3, TO_DATE(LEFT(MIN(COMP_PLAN_START_DATE),10),'MM/DD/YYYY'))) AS m4_end,  -- MAY
    LAST_DAY(DATEADD(month,  4, TO_DATE(LEFT(MIN(COMP_PLAN_START_DATE),10),'MM/DD/YYYY'))) AS m5_end,  -- JUN
    LAST_DAY(DATEADD(month,  5, TO_DATE(LEFT(MIN(COMP_PLAN_START_DATE),10),'MM/DD/YYYY'))) AS m6_end,  -- JUL
    LAST_DAY(DATEADD(month,  6, TO_DATE(LEFT(MIN(COMP_PLAN_START_DATE),10),'MM/DD/YYYY'))) AS m7_end,  -- AUG
    LAST_DAY(DATEADD(month,  7, TO_DATE(LEFT(MIN(COMP_PLAN_START_DATE),10),'MM/DD/YYYY'))) AS m8_end,  -- SEP
    LAST_DAY(DATEADD(month,  8, TO_DATE(LEFT(MIN(COMP_PLAN_START_DATE),10),'MM/DD/YYYY'))) AS m9_end,  -- OCT
    LAST_DAY(DATEADD(month,  9, TO_DATE(LEFT(MIN(COMP_PLAN_START_DATE),10),'MM/DD/YYYY'))) AS m10_end, -- NOV
    LAST_DAY(DATEADD(month, 10, TO_DATE(LEFT(MIN(COMP_PLAN_START_DATE),10),'MM/DD/YYYY'))) AS m11_end, -- DEC
    LAST_DAY(DATEADD(month, 11, TO_DATE(LEFT(MIN(COMP_PLAN_START_DATE),10),'MM/DD/YYYY'))) AS m12_end  -- JAN
FROM IT.PIGMENT.RAW_INDUSTRY_ROSTER_QUOTA_SUMMARY_INYR
WHERE ACTIVE_RECORD = 'TRUE' AND EEID IS NOT NULL
```

Use the returned `m1_end` through `m12_end` values in Tests 4 in place of the hardcoded dates. This makes the skill automatically adapt to FY28, FY29, etc.

---

### Step 3: Run All Tests

Run each test below using `snowflake_sql_execute`. Present a summary table at the end.

---

#### Test 1 — Onboarding Status
> Checks the employee has an active record, filter status, and ops ready date.
> **Risk if FAIL:** Employee is not ops-ready — comp plan has not been processed.

```sql
SELECT
    EEID,
    D_EXISTING_EMPLOYEES            AS name,
    INSEAT_MANAGER_COMP_START       AS manager,
    QUOTA_ROLE,
    FILTER_STATUS,
    ACTIVE_RECORD,
    OPS_READY_DATE_PLANNING_ONLY,
    IFF(ACTIVE_RECORD = 'TRUE' AND FILTER_STATUS = 'Ops Ready', 'PASS', 'FAIL') AS test_result,
    IFF(ACTIVE_RECORD = 'TRUE' AND FILTER_STATUS = 'Ops Ready', NULL,
        'Contact Field Ops to mark record as Ops Ready in Pigment') AS action_needed
FROM IT.PIGMENT.RAW_INDUSTRY_ROSTER_QUOTA_SUMMARY_INYR
WHERE EEID = <EEID>
```

---

#### Test 2 — Territory Configuration
> PASS = district or patch is populated. FAIL = both are NULL.
> **Risk if FAIL:** Reporting, Compensation, System Access — employee cannot access correct accounts in SFDC and consumption won't be attributed correctly.

```sql
SELECT
    r.EEID,
    r.D_EXISTING_EMPLOYEES                                  AS name,
    r.INDUSTRY_DISTRICT,
    r.INDUSTRY_PATCH,
    IFF(r.INDUSTRY_DISTRICT IS NOT NULL OR r.INDUSTRY_PATCH IS NOT NULL, 'PASS', 'FAIL') AS result,
    IFF(r.INDUSTRY_DISTRICT IS NOT NULL OR r.INDUSTRY_PATCH IS NOT NULL, NULL,
        'Configure INDUSTRY_DISTRICT or INDUSTRY_PATCH in Pigment territory assignment') AS action_needed
FROM IT.PIGMENT.RAW_INDUSTRY_ROSTER_QUOTA_SUMMARY_INYR r
WHERE EEID = <EEID>
  AND ACTIVE_RECORD = 'TRUE'
```

---

#### Test 3 — ETM Alignment Configuration
> PASS = both primary and secondary ETM functions are populated.
> **Risk if FAIL:** Reporting, Compensation, System Access — org hierarchy and territory routing will be incorrect.

```sql
SELECT
    EEID,
    D_EXISTING_EMPLOYEES                                    AS name,
    PRIMARY_ETM_FUNCTION_COMP_START,
    SECONDARY_ETM_FUNCTION_COMP_START,
    IFF(PRIMARY_ETM_FUNCTION_COMP_START IS NOT NULL
        AND SECONDARY_ETM_FUNCTION_COMP_START IS NOT NULL, 'PASS', 'FAIL') AS result,
    IFF(PRIMARY_ETM_FUNCTION_COMP_START IS NOT NULL
        AND SECONDARY_ETM_FUNCTION_COMP_START IS NOT NULL, NULL,
        'Set Primary and Secondary ETM functions in Pigment comp plan') AS action_needed
FROM IT.PIGMENT.RAW_INDUSTRY_ROSTER_QUOTA_SUMMARY_INYR
WHERE EEID = <EEID>
  AND ACTIVE_RECORD = 'TRUE'
```

---

#### Test 4 — Baseline Configuration
> Checks each monthly baseline is populated for months on/after quota start date.
> **Corp bonus plan employees are automatically excluded** — they have no baselines by design.
> Replace `<M1_END>` through `<M12_END>` with the values from Step 2.
> **Risk if FAIL:** Compensation — monthly quota basis for attainment calculation will be wrong.

```sql
WITH quota_start AS (
    SELECT EEID, TO_DATE(LEFT(QUOTA_START_DATE, 10), 'MM/DD/YYYY') AS qstart
    FROM IT.PIGMENT.RAW_INDUSTRY_ROSTER_QUOTA_SUMMARY_INYR
    WHERE EEID = <EEID> AND ACTIVE_RECORD = 'TRUE' AND CORPORATE_BONUS_PLAN IS NULL
)
SELECT
    r.EEID,
    r.D_EXISTING_EMPLOYEES  AS name,
    r.QUOTA_START_DATE,
    CASE WHEN r.CALC_FEB_PRIMARY_CONSUMPTION_BASELINE IS NULL OR r.CALC_FEB_SECONDARY_CONSUMPTION_BASELINE IS NULL
         THEN IFF(qs.qstart > '<M1_END>', 'OK - Expected NULL', 'Issue Found') ELSE 'OK' END AS feb_status,
    CASE WHEN r.CALC_MAR_PRIMARY_CONSUMPTION_BASELINE IS NULL OR r.CALC_MAR_SECONDARY_CONSUMPTION_BASELINE IS NULL
         THEN IFF(qs.qstart > '<M2_END>', 'OK - Expected NULL', 'Issue Found') ELSE 'OK' END AS mar_status,
    CASE WHEN r.CALC_APR_PRIMARY_CONSUMPTION_BASELINE IS NULL OR r.CALC_APR_SECONDARY_CONSUMPTION_BASELINE IS NULL
         THEN IFF(qs.qstart > '<M3_END>', 'OK - Expected NULL', 'Issue Found') ELSE 'OK' END AS apr_status,
    CASE WHEN r.CALC_MAY_PRIMARY_CONSUMPTION_BASELINE IS NULL OR r.CALC_MAY_SECONDARY_CONSUMPTION_BASELINE IS NULL
         THEN IFF(qs.qstart > '<M4_END>', 'OK - Expected NULL', 'Issue Found') ELSE 'OK' END AS may_status,
    CASE WHEN r.CALC_JUN_PRIMARY_CONSUMPTION_BASELINE IS NULL OR r.CALC_JUN_SECONDARY_CONSUMPTION_BASELINE IS NULL
         THEN IFF(qs.qstart > '<M5_END>', 'OK - Expected NULL', 'Issue Found') ELSE 'OK' END AS jun_status,
    CASE WHEN r.CALC_JUL_PRIMARY_CONSUMPTION_BASELINE IS NULL OR r.CALC_JUL_SECONDARY_CONSUMPTION_BASELINE IS NULL
         THEN IFF(qs.qstart > '<M6_END>', 'OK - Expected NULL', 'Issue Found') ELSE 'OK' END AS jul_status,
    CASE WHEN r.CALC_AUG_PRIMARY_CONSUMPTION_BASELINE IS NULL OR r.CALC_AUG_SECONDARY_CONSUMPTION_BASELINE IS NULL
         THEN IFF(qs.qstart > '<M7_END>', 'OK - Expected NULL', 'Issue Found') ELSE 'OK' END AS aug_status,
    CASE WHEN r.CALC_SEP_PRIMARY_CONSUMPTION_BASELINE IS NULL OR r.CALC_SEP_SECONDARY_CONSUMPTION_BASELINE IS NULL
         THEN IFF(qs.qstart > '<M8_END>', 'OK - Expected NULL', 'Issue Found') ELSE 'OK' END AS sep_status,
    CASE WHEN r.CALC_OCT_PRIMARY_CONSUMPTION_BASELINE IS NULL OR r.CALC_OCT_SECONDARY_CONSUMPTION_BASELINE IS NULL
         THEN IFF(qs.qstart > '<M9_END>', 'OK - Expected NULL', 'Issue Found') ELSE 'OK' END AS oct_status,
    CASE WHEN r.CALC_NOV_PRIMARY_CONSUMPTION_BASELINE IS NULL OR r.CALC_NOV_SECONDARY_CONSUMPTION_BASELINE IS NULL
         THEN IFF(qs.qstart > '<M10_END>', 'OK - Expected NULL', 'Issue Found') ELSE 'OK' END AS nov_status,
    CASE WHEN r.CALC_DEC_PRIMARY_CONSUMPTION_BASELINE IS NULL OR r.CALC_DEC_SECONDARY_CONSUMPTION_BASELINE IS NULL
         THEN IFF(qs.qstart > '<M11_END>', 'OK - Expected NULL', 'Issue Found') ELSE 'OK' END AS dec_status,
    CASE WHEN r.CALC_JAN_PRIMARY_CONSUMPTION_BASELINE IS NULL OR r.CALC_JAN_SECONDARY_CONSUMPTION_BASELINE IS NULL
         THEN IFF(qs.qstart > '<M12_END>', 'OK - Expected NULL', 'Issue Found') ELSE 'OK' END AS jan_status

FROM IT.PIGMENT.RAW_INDUSTRY_ROSTER_QUOTA_SUMMARY_INYR r
JOIN quota_start qs ON r.EEID = qs.EEID
WHERE r.EEID = <EEID>
  AND r.ACTIVE_RECORD = 'TRUE'
  AND r.CORPORATE_BONUS_PLAN IS NULL
```

After the month-by-month columns, append:

```sql
    CASE WHEN <any month> = 'Issue Found'
         THEN 'Enter missing monthly baselines in Pigment (check flagged months above)'
         ELSE NULL END AS action_needed
```

Summarize: PASS if all months are `OK` or `OK - Expected NULL`. FAIL if any show `Issue Found`.

---

#### Test 5 — Targets (INCR Consumption) Configuration
> PASS = both primary and secondary INCR consumption targets are populated.
> **Corp bonus plan employees are automatically excluded.**
> **Risk if FAIL:** Compensation — employee has no attainment target set.

```sql
SELECT
    EEID,
    D_EXISTING_EMPLOYEES                                    AS name,
    INSEAT_MANAGER_COMP_START                               AS manager,
    IFF(CALC_PRIMARY_INCR_CONSUMPTION IS NOT NULL
        AND CALC_SECONDARY_INCR_CONSUMPTION IS NOT NULL, 'PASS', 'FAIL') AS result,
    CASE
        WHEN CALC_PRIMARY_INCR_CONSUMPTION IS NULL AND CALC_SECONDARY_INCR_CONSUMPTION IS NULL
             THEN 'Enter both Primary and Secondary INCR consumption targets in Pigment'
        WHEN CALC_PRIMARY_INCR_CONSUMPTION IS NULL
             THEN 'Enter Primary INCR consumption target in Pigment'
        WHEN CALC_SECONDARY_INCR_CONSUMPTION IS NULL
             THEN 'Enter Secondary INCR consumption target in Pigment'
        ELSE NULL
    END AS action_needed
FROM IT.PIGMENT.RAW_INDUSTRY_ROSTER_QUOTA_SUMMARY_INYR
WHERE EEID = <EEID>
  AND ACTIVE_RECORD = 'TRUE'
  AND CORPORATE_BONUS_PLAN IS NULL
```

---

#### Test 6 — Specialist Metadata Configuration
> PASS = both SPECIALIST_GROUP and SPECIALIST_SUB_GROUP are populated.
> **Risk if FAIL:** Reporting, SFDC Access, Sigma Access — role type is unidentified.

```sql
SELECT
    s.EMPLOYEE_ID                   AS eeid,
    s.EMPLOYEE                      AS name,
    s.SPECIALIST_GROUP,
    s.SPECIALIST_SUB_GROUP,
    s.SPECIALIST_THEATER_MARKET,
    s.METRICS_CATEGORY,
    IFF(s.SPECIALIST_GROUP IS NOT NULL
        AND s.SPECIALIST_SUB_GROUP IS NOT NULL, 'PASS', 'FAIL') AS result,
    CASE
        WHEN s.SPECIALIST_GROUP IS NULL AND s.SPECIALIST_SUB_GROUP IS NULL
             THEN 'Add employee to RAW_SPECIALIST_ATTRIBUTES_INYR with SPECIALIST_GROUP and SPECIALIST_SUB_GROUP'
        WHEN s.SPECIALIST_GROUP IS NULL
             THEN 'Set SPECIALIST_GROUP in Pigment specialist metadata'
        WHEN s.SPECIALIST_SUB_GROUP IS NULL
             THEN 'Set SPECIALIST_SUB_GROUP in Pigment specialist metadata (known org-wide gap — confirm with Ops if expected)'
        ELSE NULL
    END AS action_needed
FROM IT.PIGMENT.RAW_SPECIALIST_ATTRIBUTES_INYR s
WHERE s.EMPLOYEE_ID = <EEID>
```

---

### Step 4: Present Summary

After running all 6 tests, present a clean summary table. For any FAIL, show the action needed.

| Test | Result | Risk Type | Action Needed |
|------|--------|-----------|---------------|
| Onboarding Status | PASS/FAIL | Comp plan not processed | Contact Field Ops to mark as Ops Ready |
| Territory Configuration | PASS/FAIL | Reporting, Comp, System Access | Configure District/Patch in Pigment |
| ETM Alignment | PASS/FAIL | Reporting, Comp, System Access | Set Primary + Secondary ETM in Pigment |
| Baseline Configuration | PASS/FAIL | Compensation | Enter missing monthly baselines in Pigment |
| Targets (INCR Consumption) | PASS/FAIL | Compensation | Enter INCR targets in Pigment |
| Specialist Metadata | PASS/FAIL | Reporting, SFDC/Sigma Access | Update Group + Sub-group in Pigment metadata |

For whole-org runs, also show a **headline**: total number of failing employees and number of unique FAILs per test.

---

### Step 5: Write Audit to Local File

After presenting the summary, write the full results to a timestamped CSV in the skill's `audits/` folder using Python. All historical runs are preserved here for trend tracking and sharing.

```python
import csv, os
from datetime import datetime

SKILL_DIR = os.path.expanduser('~/.snowflake/cortex/skills/industry-specialists-revops-checks')
AUDITS_DIR = os.path.join(SKILL_DIR, 'audits')
os.makedirs(AUDITS_DIR, exist_ok=True)

timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
filename = os.path.join(AUDITS_DIR, f'audit_{timestamp}.csv')

# Build rows from query results above
rows = [
    {
        'run_at': timestamp,
        'eeid': <eeid>,
        'name': <name>,
        'manager': <manager>,
        'test_1_onboarding': <result>,
        'test_2_territory': <result>,
        'test_3_etm': <result>,
        'test_4_baselines': <result>,
        'test_5_targets': <result>,
        'test_6_metadata': <result>,
        'overall': 'PASS' if all tests pass else 'FAIL',
        'action_needed': <comma-joined list of action_needed strings for any FAIL>
    }
    # one row per EEID
]

with open(filename, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)

print(f'Audit saved to: {filename}')
```

Tell the user: "Audit saved to `~/.snowflake/cortex/skills/industry-specialists-revops-checks/audits/audit_{timestamp}.csv`"

To list all previous audits, run: `ls ~/.snowflake/cortex/skills/industry-specialists-revops-checks/audits/`

---

## Notes

- **Industry Specialists only** — these tables are scoped to Industry GTM roles. Do not run for AFE, PSS, SDR, AE, or other functions.
- **Corp bonus plan employees are excluded from Tests 4 and 5** — they have no baselines or INCR consumption targets by design.
- **FY dates are dynamic** — Step 2 derives month-end dates from the active comp plan data. No hardcoded dates.
- `QUOTA_START_DATE` is stored as VARCHAR (`MM/DD/YYYY HH:MM:SS TZ`). Use `TO_DATE(LEFT(..., 10), 'MM/DD/YYYY')` for date comparisons.
- `ACTIVE_RECORD = 'TRUE'` filters to the current active comp plan row only.
- **Manager Sign Off** is tracked in Pigment's UI only — not available in Snowhouse. Must be verified directly in Pigment.
- Reference: [New Hire Onboarding Doc](https://docs.google.com/document/d/1b3Kz2ZmWCXH6BjafI55vVsoI8r7TztYIov3lWwWkQIA/edit?tab=t.0)
