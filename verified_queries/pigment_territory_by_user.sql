-- PIGMENT: Territory for a given user
-- Latest snapshot only (IS_ACTIVE = TRUE, max DS_DATE)
-- Input: replace :workday_employee_id with the target EEID (numeric)
--        OR swap to p.EMAIL_PRIMARY_WORK = ':user_email'
--        OR swap to p.SFDC_USER_ID       = ':sfdc_user_id'

SELECT
    p.EMAIL_PRIMARY_WORK,
    p.SFDC_USER_ID,
    p.SFDC_USER_NAME,
    p.EEID,
    p.TERRITORY_PROFILE,
    p.PATCH,
    p.DISTRICT,
    p.SUBREGION,
    p.REGION,
    p.AREA,
    p.THEATER,
    p.MARKET,
    p.SEGMENT,
    p.HC_FUNCTION,
    p.IS_ACTIVE,
    p.DS_DATE       AS pigment_snapshot_date
FROM IT.PIGMENT.PIGMENT_ROSTER p
WHERE p.IS_ACTIVE = TRUE
  AND p.DS_DATE = (SELECT MAX(DS_DATE) FROM IT.PIGMENT.PIGMENT_ROSTER WHERE IS_ACTIVE = TRUE)
  AND p.EEID = :workday_employee_id
;
