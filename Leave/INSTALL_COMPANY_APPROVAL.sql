-- SQL*Plus / SQLcl connected as HRMS. REQUEST_STATUS already exists in the
-- supplied tables. Pause leave-page writes during installation/page wiring.
-- Oracle DDL commits; do not run base table DROP/CREATE exports on existing data.
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

DECLARE
    l_count NUMBER;
BEGIN
    IF USER <> 'HRMS' THEN
        RAISE_APPLICATION_ERROR(-20824, 'Connect as HRMS before installing leave approval.');
    END IF;
    -- Verify source columns before replacing objects. No role data is seeded.
    SELECT COUNT(*) INTO l_count FROM v_leave_roles
     WHERE company_id IS NOT NULL AND role_code IN
           ('PLANT_HEAD', 'MANAGING_DIRECTOR', 'LEAVE_RECORD')
       AND active_yn = 'Y' AND id IS NOT NULL;
    SELECT COUNT(request_status) INTO l_count FROM leave_request WHERE 1 = 0;
    SELECT COUNT(rep_person_id) INTO l_count FROM emp_rp
     WHERE emp_id IS NOT NULL AND status IS NOT NULL AND 1 = 0;
    SELECT COUNT(hod_id) INTO l_count FROM hod
     WHERE dept_id IS NOT NULL AND status IS NOT NULL AND 1 = 0;
    SELECT COUNT(*) INTO l_count FROM
        (SELECT id FROM leave_app_history GROUP BY id HAVING COUNT(*) > 1);
    IF l_count <> 0 THEN
        RAISE_APPLICATION_ERROR(-20825, 'Duplicate history IDs require review before adding a primary key.');
    END IF;
END;
/

@@TRG_LEAVE_REQUEST_PK.sql
@@TRG_LEAVE_APP_HISTORY_PK.sql

DECLARE
    l_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM user_constraints
     WHERE table_name = 'LEAVE_APP_HISTORY' AND constraint_type = 'P';
    IF l_count = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE HRMS.leave_app_history ADD '
            || 'CONSTRAINT pk_leave_app_history PRIMARY KEY (id)';
    END IF;
END;
/

@@TRG_LEAVE_REQUEST_STATUS.sql
@@UPGRADE_LEAVE_CONSUMPTION.sql
@@FN_LEAVE_TYPE_ID.sql
@@V_LEAVE_YEAR_BALANCE.sql
@@F_LEAVE_BA.sql
@@POST_LEAVE_CONSUMPTION.sql
@@V_LEAVE_APPROVAL_STEPS.sql
@@PKG_LEAVE_APPROVAL.sql
@@V_LEAVE_APPROVAL.sql
@@V_EMP_LEAVE_TOTAL.sql

DECLARE
    l_errors NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_errors FROM user_errors
     WHERE name IN ('PKG_LEAVE_APPROVAL', 'TRG_LEAVE_APP_HISTORY_PK',
                   'TRG_LEAVE_REQUEST_PK', 'TRG_LEAVE_REQUEST_STATUS',
                   'V_LEAVE_APPROVAL_STEPS', 'V_LEAVE_APPROVAL', 'V_EMP_LEAVE_TOTAL',
                   'TRG_LEAVE_CONSUMPTION_PK', 'FN_LEAVE_TYPE_ID',
                   'V_LEAVE_YEAR_BALANCE', 'F_LEAVE_BA', 'POST_LEAVE_CONSUMPTION')
       AND attribute = 'ERROR';
    IF l_errors > 0 THEN
        RAISE_APPLICATION_ERROR(-20819, 'Leave approval objects have compilation errors. Check USER_ERRORS.');
    END IF;
END;
/

-- Company routing runs in the Page 420 submit process (Apply/Forward),
-- not in a database INSERT trigger when saving a draft.
BEGIN
    EXECUTE IMMEDIATE 'DROP TRIGGER HRMS.trg_leave_request_insert';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -4080 THEN RAISE; END IF;
END;
/

PROMPT Leave approval installed: optional RP / one eligible higher-tier approver / HRD.
PROMPT Final approval posts consumption once and checks the start-year balance.
PROMPT Existing pending histories are preserved and require review before migration.
PROMPT Wire Page 420 and Page 422 using APEX_COMPANY_APPROVAL.md.
WHENEVER SQLERROR CONTINUE NONE
