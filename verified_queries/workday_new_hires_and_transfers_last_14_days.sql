-- WORKDAY: New hires and transfers within the last 14 days
-- Source: SNOW_CERTIFIED.EMPLOYEE.D_EMPLOYEE_WORKDAY  (new hires — current state)
--         SNOW_CERTIFIED.EMPLOYEE.SNP_EMPLOYEE_WORKDAY (transfers — SCD2 change history)
--
-- roster_status values:
--   New Hire     : EMPLOYEE_HIRE_DATE_AT within last 14 days
--   Transfer In  : Employee received a new SCD2 record (VALID_FROM within 14 days)
--                  where EMPLOYEE_TRANSFER_IN_DEPARTMENT is populated
--   Transfer Out : Employee received a new SCD2 record (VALID_FROM within 14 days)
--                  where EMPLOYEE_TRANSFER_OUT_DEPARTMENT is populated but no Transfer In
--
-- Adjust the 14-day window by changing CURRENT_DATE - 14 below

WITH new_hires AS (
    SELECT
        w.WORKDAY_EMPLOYEE_ID,
        w.EMPLOYEE_PREFERRED_NAME           AS employee_name,
        w.EMPLOYEE_EMAIL,
        w.EMPLOYEE_BUSINESS_TITLE,
        w.EMPLOYEE_HIRE_DATE_AT             AS event_date,
        w.EMPLOYEE_MANAGER_NAME,
        w.EMPLOYEE_COUNTRY,
        w.EMPLOYEE_LOCATION,
        'New Hire'                          AS roster_status,
        NULL                                AS transfer_from,
        NULL                                AS transfer_to
    FROM SNOW_CERTIFIED.EMPLOYEE.D_EMPLOYEE_WORKDAY w
    WHERE w.EMPLOYEE_HIRE_DATE_AT >= CURRENT_DATE - 14
      AND w.IS_EMPLOYEE_ACTIVE = TRUE
),
transfers AS (
    SELECT
        s.WORKDAY_EMPLOYEE_ID,
        s.EMPLOYEE_PREFERRED_NAME           AS employee_name,
        s.EMPLOYEE_EMAIL,
        s.EMPLOYEE_BUSINESS_TITLE,
        s.VALID_FROM                        AS event_date,
        s.EMPLOYEE_MANAGER_NAME,
        s.EMPLOYEE_COUNTRY,
        s.EMPLOYEE_LOCATION,
        CASE
            WHEN s.EMPLOYEE_TRANSFER_OUT_DEPARTMENT IS NOT NULL
             AND s.EMPLOYEE_TRANSFER_IN_DEPARTMENT  IS NOT NULL THEN 'Transfer In'
            WHEN s.EMPLOYEE_TRANSFER_OUT_DEPARTMENT IS NOT NULL THEN 'Transfer Out'
            ELSE 'Transfer In'
        END                                 AS roster_status,
        COALESCE(s.EMPLOYEE_TRANSFER_OUT_DEPARTMENT,
                 s.EMPLOYEE_TRANSFER_OUT_COST_CENTER)   AS transfer_from,
        COALESCE(s.EMPLOYEE_TRANSFER_IN_DEPARTMENT,
                 s.EMPLOYEE_TRANSFER_IN_COST_CENTER)    AS transfer_to
    FROM SNOW_CERTIFIED.EMPLOYEE.SNP_EMPLOYEE_WORKDAY s
    WHERE s.IS_EMPLOYEE_TRANSFERRED = TRUE
      AND s.VALID_FROM >= CURRENT_DATE - 14
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
