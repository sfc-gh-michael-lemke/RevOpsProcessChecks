-- WORKDAY: Bonus eligibility for a given employee
-- Source: SNOW_CERTIFIED_SENSITIVE.EMPLOYEE.D_EMPLOYEE_COMPENSATION (current-state view, IS_LATEST = TRUE)
-- An employee is considered on bonus when BONUS_TARGET_PERCENT > 0 OR BONUS_TARGET_AMOUNT > 0
--
-- Input: replace :workday_employee_id with the target Workday EEID (numeric)
--        OR remove the filter to run across all active employees

SELECT
    c.WORKDAY_EMPLOYEE_ID,
    c.EMPLOYEE_PREFERRED_NAME,
    c.EMPLOYEE_MANAGER_NAME,
    c.JOB_PROFILE_NAME,
    c.PAY_RATE_TYPE,
    c.BASE_PAY_CURRENCY,
    c.BONUS_TARGET_PERCENT,
    c.BONUS_TARGET_AMOUNT,
    c.TOTAL_TARGET_COMPENSATION,
    CASE
        WHEN COALESCE(c.BONUS_TARGET_PERCENT, 0) > 0
          OR COALESCE(c.BONUS_TARGET_AMOUNT, 0)  > 0
        THEN TRUE
        ELSE FALSE
    END                         AS is_on_bonus,
    c.VALID_FROM                AS compensation_effective_date,
    c.IS_EMPLOYEE_ACTIVE
FROM SNOW_CERTIFIED_SENSITIVE.EMPLOYEE.D_EMPLOYEE_COMPENSATION c
WHERE c.IS_EMPLOYEE_ACTIVE = TRUE
  AND c.IS_LATEST = TRUE
  -- OPTIONAL: filter to a single person
  AND c.WORKDAY_EMPLOYEE_ID = :workday_employee_id
ORDER BY c.EMPLOYEE_PREFERRED_NAME
;
