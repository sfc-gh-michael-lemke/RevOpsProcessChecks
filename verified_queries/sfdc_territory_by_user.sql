-- SFDC: Territory for a given user
-- Input: replace :sfdc_user_id with the target Salesforce User ID
--        OR swap to u.EMAIL = ':user_email'

SELECT
    u.ID                    AS sfdc_user_id,
    u.NAME                  AS sfdc_user_name,
    u.EMAIL,
    u.USERNAME,
    u.TERRITORY_C           AS territory,
    u.TERRITORY_PROFILE_C   AS territory_profile,
    u.IS_ACTIVE
FROM FIVETRAN.SALESFORCE.USER u
WHERE u._FIVETRAN_DELETED = FALSE
  AND u.ID = ':sfdc_user_id'
;
