-- SNOW_CERTIFIED: SE group and sub-group population check for specialist roster
-- Checks whether SE_GROUP and SE_SUB_GROUP are both populated for each active specialist
-- Source: SNOW_CERTIFIED.SOLUTION_ENGINEERING.DD_SOLUTION_ENGINEERING_WORKDAY_HIERARCHY
--
-- se_group_populated:
--   TRUE  = both SE_GROUP and SE_SUB_GROUP are non-null
--   FALSE = one or both fields are missing
--
-- Input: remove the WORKDAY_EMPLOYEE_ID filter to run across all specialists

SELECT
    se.WORKDAY_EMPLOYEE_ID,
    se.SALESFORCE_USER_ID,
    se.EMPLOYEE_NAME,
    se.EMPLOYEE_EMAIL,
    se.SE_GROUP,
    se.SE_SUB_GROUP,
    se.THEATER,
    CASE
        WHEN se.SE_GROUP    IS NOT NULL
         AND se.SE_SUB_GROUP IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS se_group_populated,
    CASE
        WHEN se.SE_GROUP     IS NULL AND se.SE_SUB_GROUP IS NULL THEN 'BOTH_MISSING'
        WHEN se.SE_GROUP     IS NULL                             THEN 'SE_GROUP_MISSING'
        WHEN se.SE_SUB_GROUP IS NULL                             THEN 'SE_SUB_GROUP_MISSING'
        ELSE NULL
    END AS missing_reason
FROM SNOW_CERTIFIED.SOLUTION_ENGINEERING.DD_SOLUTION_ENGINEERING_WORKDAY_HIERARCHY se
WHERE se.SE_GROUP IN ('Architect','AFE','PSE','Mgmt','PSE/AFE','Leadership')
  AND se.IS_EMPLOYEE_ACTIVE = TRUE
  -- OPTIONAL: filter to a single person
  -- AND se.WORKDAY_EMPLOYEE_ID = :workday_employee_id
ORDER BY se_group_populated ASC, se.THEATER, se.EMPLOYEE_NAME
;
