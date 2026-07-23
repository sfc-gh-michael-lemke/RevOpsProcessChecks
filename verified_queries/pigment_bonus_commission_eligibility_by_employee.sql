-- PIGMENT: Bonus and commission eligibility for a given employee
-- Source: IT.PIGMENT.SALES_ROSTER_QUOTA_SUMMARY_IN_YR (active record, latest snapshot)
--         joined to IT.PIGMENT.PIGMENT_ROSTER for identity fields
--
-- Eligibility logic:
--   is_commission_eligible : COMMISSION_ANNUAL_TARGET_USD > 0
--   is_bonus_eligible       : BONUS_MULTI_YEAR = TRUE OR BONUS_PS_T = TRUE
--   comp_type               : Commission | Bonus | Commission + Bonus | Neither
--
-- Input: replace :workday_employee_id with the target EEID (numeric)
--        OR remove the EEID filter to run across all active employees

WITH latest_roster AS (
    SELECT
        p.EEID,
        p.EMAIL_PRIMARY_WORK,
        p.SFDC_USER_ID,
        p.HC_FUNCTION,
        p.IC_MGR_ADMIN,
        p.IN_PLAN_OUT_OF_PLAN,
        p.THEATER,
        p.SEGMENT
    FROM IT.PIGMENT.PIGMENT_ROSTER p
    WHERE p.IS_ACTIVE = TRUE
      AND p.DS_DATE = (SELECT MAX(DS_DATE) FROM IT.PIGMENT.PIGMENT_ROSTER WHERE IS_ACTIVE = TRUE)
),
latest_quota AS (
    SELECT
        q.EEID,
        q.EMPLOYEE_NAME,
        q.ETM_FUNCTION,
        q.COMP_PLAN_ID,
        q.COMP_PLAN_START_DATE,
        q.COMP_PLAN_END_DATE,
        q.XACTLY_PLAN_STATUS,
        q.CUSTOM_PLAN_CATEGORY,
        q.COMMISSION_ANNUAL_TARGET_USD,
        q.PRORATED_COMMISSION_ANNUAL_TARGET_USD,
        q.BONUS_MULTI_YEAR,
        q.BONUS_PS_T
    FROM IT.PIGMENT.SALES_ROSTER_QUOTA_SUMMARY_IN_YR q
    WHERE q.ACTIVE_RECORD = TRUE
      AND q.DS_DATE = (SELECT MAX(DS_DATE) FROM IT.PIGMENT.SALES_ROSTER_QUOTA_SUMMARY_IN_YR WHERE ACTIVE_RECORD = TRUE)
)
SELECT
    q.EMPLOYEE_NAME,
    r.EMAIL_PRIMARY_WORK,
    r.SFDC_USER_ID,
    r.EEID                                          AS workday_employee_id,
    r.HC_FUNCTION,
    r.IC_MGR_ADMIN,
    r.THEATER,
    r.SEGMENT,
    r.IN_PLAN_OUT_OF_PLAN,
    q.COMP_PLAN_ID,
    q.XACTLY_PLAN_STATUS,
    q.CUSTOM_PLAN_CATEGORY,
    q.COMMISSION_ANNUAL_TARGET_USD,
    q.PRORATED_COMMISSION_ANNUAL_TARGET_USD,
    q.BONUS_MULTI_YEAR,
    q.BONUS_PS_T,
    -- eligibility flags
    CASE WHEN COALESCE(q.COMMISSION_ANNUAL_TARGET_USD, 0) > 0
         THEN TRUE ELSE FALSE END                   AS is_commission_eligible,
    CASE WHEN COALESCE(q.BONUS_MULTI_YEAR, FALSE) = TRUE
           OR COALESCE(q.BONUS_PS_T, FALSE) = TRUE
         THEN TRUE ELSE FALSE END                   AS is_bonus_eligible,
    -- single comp_type label for easy filtering/reporting
    CASE
        WHEN COALESCE(q.COMMISSION_ANNUAL_TARGET_USD, 0) > 0
         AND (COALESCE(q.BONUS_MULTI_YEAR, FALSE) = TRUE OR COALESCE(q.BONUS_PS_T, FALSE) = TRUE)
            THEN 'Commission + Bonus'
        WHEN COALESCE(q.COMMISSION_ANNUAL_TARGET_USD, 0) > 0
            THEN 'Commission'
        WHEN COALESCE(q.BONUS_MULTI_YEAR, FALSE) = TRUE OR COALESCE(q.BONUS_PS_T, FALSE) = TRUE
            THEN 'Bonus'
        ELSE 'Neither'
    END                                             AS comp_type,
    q.COMP_PLAN_START_DATE,
    q.COMP_PLAN_END_DATE
FROM latest_quota q
LEFT JOIN latest_roster r ON q.EEID = r.EEID
-- OPTIONAL: filter to a single person
WHERE r.EEID = :workday_employee_id
ORDER BY comp_type, r.THEATER, q.EMPLOYEE_NAME
;
