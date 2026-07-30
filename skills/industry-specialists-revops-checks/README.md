# Industry Specialists RevOps Checks

## Business Context

When a new Industry Specialist joins Snowflake, they must be configured across several systems before they are operational. This configuration happens primarily in **Pigment** (Snowflake's comp planning tool) and flows downstream into Salesforce, CaptivateIQ (CiQ), and reporting dashboards.

If any step is missing, the consequences are real:

- **Wrong territory** → employee cannot see the correct accounts in Salesforce and their consumption isn't attributed properly
- **Missing ETM alignment** → org hierarchy is broken, routing is wrong
- **No baselines** → monthly quota attainment calculations are incorrect
- **No targets** → employee has no INCR consumption quota to attain against
- **Missing metadata** → employee doesn't appear correctly in Sigma dashboards and may lack SFDC/Sigma access
- **Not ops-ready** → comp plan has not been pushed to ICM; compensation will not be processed

Historically, these gaps were caught manually or discovered when an employee complained about a system access issue or a missed payout. This skill automates the detection.

## What This Skill Does

Runs a **6-test configuration audit** against the Industry Specialist roster in Pigment's Snowhouse tables. Each test checks one onboarding step and returns **PASS** or **FAIL**, with an **action needed** description on every failing record.

| Test | What It Checks | Risk Type |
|------|---------------|-----------|
| 1. Onboarding Status | Employee is active with `Ops Ready` filter status | Comp plan not pushed to ICM |
| 2. Territory Configuration | Industry district or patch is populated | Accounts inaccessible, consumption unattributed |
| 3. ETM Alignment | Primary and secondary ETM functions are set | Org hierarchy broken |
| 4. Baseline Configuration | Monthly consumption baselines present for all months ≥ quota start date | Attainment calc incorrect |
| 5. Targets | Primary and secondary INCR consumption targets are set | No quota to attain against |
| 6. Specialist Metadata | `SPECIALIST_GROUP` and `SPECIALIST_SUB_GROUP` are populated | Missing from dashboards, wrong system access |

## Key Design Decisions

- **Corp bonus plan employees are automatically excluded from Tests 4 and 5** — they have no baselines or INCR targets by design. This prevents false positives for GTM Mgmt roles.
- **Fiscal year dates are derived dynamically** — the skill detects the active FY from comp plan start dates in the data, so it works across FY27, FY28, and beyond without manual updates.
- **Whole-org runs require confirmation** — before running across all specialists, the skill shows a count and asks the user to confirm, preventing accidental large query runs.
- **Action needed is specified** — every FAIL includes a plain-language description of the exact step required to resolve it in Pigment, so results are immediately actionable without needing to interpret raw field names.
- **Audit results are saved locally** — after each run, results are written to `~/.snowflake/cortex/skills/industry-specialists-revops-checks/audits/audit_<timestamp>.csv`. All historical runs are preserved in the `audits/` folder for trend tracking and sharing.

## Who Uses It

**RevOps** — to validate new hires are fully configured before their first payroll cycle.

**Ops Managers** — to run a quick health check on their team's Pigment setup at any point during the year.

## Modes

| Mode | Behavior |
|------|---------|
| One person | Runs all 6 checks for a single EEID, shows per-test detail |
| Whole org | Runs all 6 checks across all active specialists, shows PASS/FAIL counts, lists every failing EEID with action needed per test |

## Data Sources

| Table | Purpose |
|-------|---------|
| `IT.PIGMENT.RAW_INDUSTRY_ROSTER_QUOTA_SUMMARY_INYR` | In-year comp plan records — territories, ETM, baselines, targets, quota amounts |
| `IT.PIGMENT.RAW_SPECIALIST_ATTRIBUTES_INYR` | Specialist group, sub-group, theater, and metadata |

## Scope

**Industry Specialists only** — Industry GTM, Industry Architect, Industry GTM Mgmt, Industry Principal roles. Not applicable to AFE, PSS, SDR, or AE functions.

## Known Gaps

- **Manager Sign Off** is tracked in Pigment's UI only — not synced to Snowhouse. Must be verified directly in Pigment.
- **Specialist Sub-Group** (`SPECIALIST_SUB_GROUP`) was NULL for nearly the entire org as of July 2026 — this is a systemic data gap in `RAW_SPECIALIST_ATTRIBUTES_INYR`, not an individual issue.

## Reference

- [New Hire Onboarding Doc](https://docs.google.com/document/d/1b3Kz2ZmWCXH6BjafI55vVsoI8r7TztYIov3lWwWkQIA/edit?tab=t.0) — full onboarding checklist and risk definitions
