-- PIGMENT: Employees with MBO components in their comp plan
-- Covers TWO sources:
--   (1) IT.PIGMENT.SALES_ROSTER_QUOTA_SUMMARY_IN_YR     — AE / Field SE / Support roles
--   (2) IT.PIGMENT.RAW_PARTNER_ROSTER_QUOTA_SUMMARY_PLAN — PSE / PSM / PDM / Partner roles
--
-- MBO detection logic:
--   Sales roster  : CUSTOM_PLAN_CATEGORY = 'MBO' OR MBO_MIX > 0
--   Partner roster: MBO_TI_MIX > 0
--
-- Note: PSEs use "Quarterly Measures" terminology in Pigment UI which maps to MBO_TI_MIX in the data.

WITH latest_roster AS (
    SELECT
        p.EEID,
        p.EMAIL_PRIMARY_WORK,
        p.SFDC_USER_NAME        AS employee_name,
        p.SFDC_USER_ID,
        p.HC_FUNCTION           AS pig_hc_function,
        p.THEATER
    FROM IT.PIGMENT.PIGMENT_ROSTER p
    WHERE p.IS_ACTIVE = TRUE
      AND p.DS_DATE = (SELECT MAX(DS_DATE) FROM IT.PIGMENT.PIGMENT_ROSTER WHERE IS_ACTIVE = TRUE)
),
se_hierarchy AS (
    SELECT se.WORKDAY_EMPLOYEE_ID, se.SE_GROUP, se.SE_SUB_GROUP, se.EMPLOYEE_MANAGER_NAME
    FROM SNOW_CERTIFIED.SOLUTION_ENGINEERING.DD_SOLUTION_ENGINEERING_WORKDAY_HIERARCHY se
    WHERE se.IS_EMPLOYEE_ACTIVE = TRUE
),

-- Source 1: Sales roster (AE, Field SE, Support)
sales_mbo AS (
    SELECT
        q.EEID,
        q.EMPLOYEE_NAME,
        q.ETM_FUNCTION              AS function_label,
        q.HC_FUNCTION_SUBGROUP      AS sub_function,
        NULL                        AS territory_profile,
        q.TI_MBO_MIX                AS mbo_mix_description,
        CAST(q.MBO_MIX AS FLOAT)    AS mbo_ti_mix_pct,
        NULL                        AS mbo_measure,
        NULL                        AS q1_mbo_target,
        NULL                        AS q2_mbo_target,
        NULL                        AS q3_mbo_target,
        NULL                        AS q4_mbo_target,
        q.COMMISSION_ANNUAL_TARGET_USD,
        q.XACTLY_PLAN_STATUS,
        q.COMP_PLAN_ID,
        'Sales Roster'              AS source_table
    FROM IT.PIGMENT.SALES_ROSTER_QUOTA_SUMMARY_IN_YR q
    WHERE q.ACTIVE_RECORD = TRUE
      AND q.DS_DATE = (SELECT MAX(DS_DATE) FROM IT.PIGMENT.SALES_ROSTER_QUOTA_SUMMARY_IN_YR WHERE ACTIVE_RECORD = TRUE)
      AND (q.CUSTOM_PLAN_CATEGORY = 'MBO' OR COALESCE(q.MBO_MIX, 0) > 0)
),

-- Source 2: Partner roster (PSE, PSM, PDM)
partner_mbo AS (
    SELECT
        q.EEID,
        NULL                        AS employee_name,
        q.HC_FUNCTION               AS function_label,
        q.PRIMARY_ETM_FUNCTION      AS sub_function,
        q.TERRITORY_PROFILE,
        q.TI_MIX                    AS mbo_mix_description,
        q.MBO_TI_MIX                AS mbo_ti_mix_pct,
        q.MBO_MEASURE               AS mbo_measure,
        q.Q1_MBO_TARGET             AS q1_mbo_target,
        q.Q2_MBO_TARGET             AS q2_mbo_target,
        q.Q3_MBO_TARGET             AS q3_mbo_target,
        q.Q4_MBO_TARGET             AS q4_mbo_target,
        NULL                        AS commission_annual_target_usd,
        NULL                        AS xactly_plan_status,
        NULL                        AS comp_plan_id,
        'Partner Roster'            AS source_table
    FROM IT.PIGMENT.RAW_PARTNER_ROSTER_QUOTA_SUMMARY_PLAN q
    WHERE q.DS_DATE = (SELECT MAX(DS_DATE) FROM IT.PIGMENT.RAW_PARTNER_ROSTER_QUOTA_SUMMARY_PLAN)
      AND COALESCE(q.MBO_TI_MIX, 0) > 0
)

SELECT
    COALESCE(m.employee_name, r.employee_name)  AS employee_name,
    r.EMAIL_PRIMARY_WORK,
    r.SFDC_USER_ID,
    m.EEID                                      AS workday_employee_id,
    se.SE_GROUP,
    se.SE_SUB_GROUP,
    COALESCE(r.THEATER, '')                     AS theater,
    m.function_label,
    m.sub_function,
    m.territory_profile,
    se.EMPLOYEE_MANAGER_NAME                    AS manager_name,
    m.source_table,
    m.mbo_mix_description,
    m.mbo_ti_mix_pct,
    m.mbo_measure,
    m.q1_mbo_target,
    m.q2_mbo_target,
    m.q3_mbo_target,
    m.q4_mbo_target,
    m.commission_annual_target_usd,
    m.xactly_plan_status,
    m.comp_plan_id
FROM (SELECT * FROM sales_mbo UNION ALL SELECT * FROM partner_mbo) m
LEFT JOIN latest_roster  r  ON m.EEID = r.EEID
LEFT JOIN se_hierarchy   se ON m.EEID = se.WORKDAY_EMPLOYEE_ID
ORDER BY m.source_table, r.THEATER, m.function_label, employee_name
;
