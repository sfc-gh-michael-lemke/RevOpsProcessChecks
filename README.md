# RevOpsProcessChecks

Snowflake SQL QC checks for RevOps data integrity. Each check compares source-of-truth systems (Pigment, Workday, SFDC) and flags discrepancies for cleanup.

## Structure

```
RevOpsProcessChecks/
├── verified_queries/          # Single-purpose SQL lookups (one query per file)
│   ├── pigment_territory_by_user.sql
│   └── sfdc_territory_by_user.sql
│
└── skills/                    # CoCo skills — multi-source QC checks
    └── territory-profile-match/
        └── SKILL.md
```

## Verified Queries

Point-lookup queries for a single user. Parameterize by replacing the placeholder value.

| File | Description | Filter by |
|---|---|---|
| `pigment_territory_by_user.sql` | Full territory hierarchy from Pigment roster | `EEID`, email, or SFDC User ID |
| `sfdc_territory_by_user.sql` | Territory profile from SFDC User object | SFDC User ID or email |

## Skills

End-to-end QC checks that join multiple sources and return a pass/fail result per row.

| Skill | Description | Input |
|---|---|---|
| `territory-profile-match` | Compares `TERRITORY_PROFILE` between Pigment and SFDC for the full specialist roster | `workday_employee_id` or `sfdc_user_id` (optional — omit to run full roster) |

## Mismatch reason labels (all skills)

| Label | Meaning |
|---|---|
| `PIGMENT_ONLY` | Pigment has a value, SFDC is blank |
| `SFDC_ONLY` | SFDC has a value, Pigment is blank |
| `VALUE_CONFLICT` | Both have values but they disagree |
| `NO_SFDC_USER` | No active SFDC user record found |
