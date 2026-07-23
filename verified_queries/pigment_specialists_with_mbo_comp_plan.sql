-- PIGMENT: Employees with MBO components in their comp plan
-- Sources: IT.PIGMENT.SALES_ROSTER_QUOTA_SUMMARY_IN_YR (comp plan details)
--          IT.PIGMENT.PIGMENT_ROSTER (identity / role fields)
--          SNOW_CERTIFIED.SOLUTION_ENGINEERING.DD_SOLUTION_ENGINEERING_WORKDAY_HIERARCHY (SE group, where applicable)
--
-- MBO detection logic:
--   CUSTOM_PLAN_CATEGORY = 'MBO'  → plan is fully or partially MBO-based
--   MBO_MIX > 0                   → explicit MBO mix percentage set on the plan
--
-- Note: as of the latest snapshot, MBO plans appear on Field SE and AE roles.
--       SE_GROUP / SE_SUB_GROUP will be NULL for non-specialist employees.
--
-- Input: add AND p.EEID = :workday_employee_id to filter to a single person

WITH latest_quota AS (
    SELECT
        q.EEID,
        q.EMPLOYEE_NAME,
        q.ETM_FUNCTION,
        q.HC_FUNCTION_SUBGROUP,
        q.COMP_PLAN_ID,
        q.XACTLY_PLAN_STATUS,
        q.CUSTOM_PLAN_CATEGORY,
        q.TI_MBO_MIX,
        q.MBO_MIX,
        q.COMMISSION_ANNUAL_TARGET_USD,
        q.COMP_PLAN_START_DATE,
        q.COMP_PLAN_END_DATE
    FROM IT.PIGMENT.SALES_ROSTER_QUOTA_SUMMARY_IN_YR q
    WHERE q.ACTIVE_RECORD = TRUE
      AND q.DS_DATE = (SELECT MAX(DS_DATE) FROM IT.PIGMENT.SALES_ROSTER_QUOTA_SUMMARY_IN_YR WHERE ACTIVE_RECORD = TRUE)
      AND (
          q.CUSTOM_PLAN_CATEGORY = 'MBO'
          OR COALESCE(q.MBO_MIX, 0) > 0
      )
),
latest_roster AS (
    SELECT
        p.EEID,
        p.EMAIL_PRIMARY_WORK,
        p.SFDC_USER_ID,
        p.HC_FUNCTION,
        p.IC_MGR_ADMIN,
        p.THEATER,
        p.SEGMENT,
        p.TERRITORY_PROFILE
    FROM IT.PIGMENT.PIGMENT_ROSTER p
    WHERE p.IS_ACTIVE = TRUE
      AND p.DS_DATE = (SELECT MAX(DS_DATE) FROM IT.PIGMENT.PIGMENT_ROSTER WHERE IS_ACTIVE = TRUE)
),
se_hierarchy AS (
    SELECT
        se.WORKDAY_EMPLOYEE_ID,
        se.SE_GROUP,
        se.SE_SUB_GROUP,
        se.EMPLOYEE_MANAGER_NAME
    FROM SNOW_CERTIFIED.SOLUTION_ENGINEERING.DD_SOLUTION_ENGINEERING_WORKDAY_HIERARCHY se
    WHERE se.IS_EMPLOYEE_ACTIVE = TRUE
)
SELECT
    q.EMPLOYEE_NAME,
    r.EMAIL_PRIMARY_WORK,
    r.SFDC_USER_ID,
    q.EEID                              AS workday_employee_id,
    q.ETM_FUNCTION,
    q.HC_FUNCTION_SUBGROUP,
    se.SE_GROUP,
    se.SE_SUB_GROUP,
    r.THEATER,
    se.EMPLOYEE_MANAGER_NAME            AS manager_name,
    q.COMP_PLAN_ID,
    q.CUSTOM_PLAN_CATEGORY              AS plan_category,
    q.TI_MBO_MIX                        AS mbo_mix_description,
    q.MBO_MIX                           AS mbo_mix_pct,
    q.COMMISSION_ANNUAL_TARGET_USD,
    q.XACTLY_PLAN_STATUS,
    q.COMP_PLAN_START_DATE,
    q.COMP_PLAN_END_DATE
FROM latest_quota q
LEFT JOIN latest_roster  r  ON q.EEID = r.EEID
LEFT JOIN se_hierarchy   se ON q.EEID = se.WORKDAY_EMPLOYEE_ID
ORDER BY r.THEATER, q.ETM_FUNCTION, q.EMPLOYEE_NAME
;
