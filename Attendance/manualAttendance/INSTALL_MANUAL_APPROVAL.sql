-- SQL*Plus/SQLcl, connected as HRMS. Pause manual attendance writes first.
-- Existing tables must exist. Never run their base CREATE TABLE exports here.
-- Oracle DDL commits. This installer preserves all existing requests/history.
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON

DECLARE
    l_count NUMBER;
BEGIN
    IF USER <> 'HRMS' THEN
        RAISE_APPLICATION_ERROR(-20824, 'Connect as HRMS before installing manual attendance approval.');
    END IF;
    SELECT COUNT(id) INTO l_count FROM manual_att WHERE 1 = 0;
    SELECT COUNT(id) INTO l_count FROM m_att_app_history WHERE 1 = 0;
    SELECT COUNT(id) INTO l_count FROM v_leave_roles
     WHERE company_id IS NOT NULL AND role_code IS NOT NULL AND active_yn IS NOT NULL AND 1 = 0;
    SELECT COUNT(rep_person_id) INTO l_count FROM emp_rp WHERE status IS NOT NULL AND 1 = 0;
    SELECT COUNT(hod_id) INTO l_count FROM hod WHERE status IS NOT NULL AND 1 = 0;
    SELECT COUNT(*) INTO l_count FROM user_objects
     WHERE object_name IN ('P_ATT_SCHEDULE', 'P_ATT_CONT_SHIFT_FAST')
       AND object_type = 'PROCEDURE' AND status = 'VALID';
    IF l_count <> 2 THEN
        RAISE_APPLICATION_ERROR(-20824, 'Install Attendance/00_install_machine.sql first.');
    END IF;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TRIGGER HRMS.trg_manual_att_insert';
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE <> -4080 THEN RAISE; END IF;
END;
/

@@TRG_MANUAL_ATT_DATE.sql

DECLARE
    l_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM user_tab_columns
     WHERE table_name = 'MANUAL_ATT' AND column_name = 'REQUEST_STATUS';
    IF l_count = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE HRMS.manual_att ADD (request_status VARCHAR2(1))';
        EXECUTE IMMEDIATE q'[
            UPDATE HRMS.manual_att ma SET request_status = CASE
                WHEN UPPER(TRIM(status)) IN ('A', 'APPROVED') THEN 'A'
                WHEN UPPER(TRIM(status)) IN ('D', 'P', 'DRAFT')
                     AND NOT EXISTS (SELECT 1 FROM HRMS.m_att_app_history h WHERE h.m_att_id = ma.id)
                    THEN 'D'
                ELSE 'F' END]';
        EXECUTE IMMEDIATE 'ALTER TABLE HRMS.manual_att MODIFY (request_status DEFAULT ''D'' NOT NULL)';
    END IF;
    SELECT COUNT(*) INTO l_count FROM user_tab_columns
     WHERE table_name = 'MANUAL_ATT' AND column_name = 'WORKFLOW_VERSION';
    IF l_count = 0 THEN
        -- Existing rows stay version 0; their routes are never guessed/replaced.
        EXECUTE IMMEDIATE 'ALTER TABLE HRMS.manual_att ADD (workflow_version NUMBER DEFAULT 0 NOT NULL)';
    END IF;
    EXECUTE IMMEDIATE 'ALTER TABLE HRMS.manual_att MODIFY (workflow_version DEFAULT 1, status DEFAULT ''D'')';
    SELECT COUNT(*) INTO l_count FROM user_constraints WHERE constraint_name = 'CK_M_ATT_REQUEST_STAGE';
    IF l_count = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE HRMS.manual_att ADD CONSTRAINT ck_m_att_request_stage '
                       || 'CHECK (request_status IN (''D'', ''F'', ''A''))';
    END IF;
    SELECT COUNT(*) INTO l_count FROM user_constraints WHERE constraint_name = 'CK_M_ATT_WORKFLOW_VERSION';
    IF l_count = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE HRMS.manual_att ADD CONSTRAINT ck_m_att_workflow_version '
                       || 'CHECK (workflow_version IN (0, 1))';
    END IF;
END;
/

@@TRG_MANUAL_ATT_PK.sql
@@TRG_M_ATT_APP_HISTORY_PK.sql
@@../P_ATT_UPDATE_DETAILS.sql
@@POST_MANUAL_ATTENDANCE.sql
@@PKG_M_ATT_APPROVAL.sql
@@TRG_MANUAL_ATT_WORKFLOW.sql
@@V_M_ATT_APPROVAL_STEPS.sql
@@V_M_ATT_REPORT.sql
@@V_M_ATT_APPROVAL.sql
@@forwardManualAtt.sql
@@P_ATT_REBUILD_MANUAL.sql

SELECT name, type, line, position, text FROM user_errors
 WHERE name IN ('PKG_M_ATT_APPROVAL', 'POST_MANUAL_ATTENDANCE', 'P_ATT_REBUILD_MANUAL',
                'P_ATT_UPDATE_DETAILS', 'TRG_MANUAL_ATT_PK', 'TRG_M_ATT_APP_HISTORY_PK',
                'TRG_MANUAL_ATT_DATE', 'TRG_MANUAL_ATT_GUARD', 'FORWARD_ATTENDANCE_APPROVAL',
                'V_M_ATT_APPROVAL_STEPS', 'V_M_ATT_APPROVAL', 'V_M_ATT_REPORT')
   AND attribute = 'ERROR' ORDER BY name, sequence;

DECLARE
    l_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM user_objects
     WHERE object_name IN ('PKG_M_ATT_APPROVAL', 'POST_MANUAL_ATTENDANCE', 'P_ATT_REBUILD_MANUAL',
                'P_ATT_UPDATE_DETAILS', 'TRG_MANUAL_ATT_PK', 'TRG_M_ATT_APP_HISTORY_PK',
                'TRG_MANUAL_ATT_DATE', 'TRG_MANUAL_ATT_GUARD', 'FORWARD_ATTENDANCE_APPROVAL',
                'V_M_ATT_APPROVAL_STEPS', 'V_M_ATT_APPROVAL', 'V_M_ATT_REPORT')
       AND status <> 'VALID';
    IF l_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20819, 'Manual attendance objects have compilation errors; check USER_ERRORS.');
    END IF;
END;
/
PROMPT Manual attendance approval installed. Existing routes are preserved for review.
PROMPT Wire the APEX processes/reports and scheduler using manualAttendance/README.md.
WHENEVER SQLERROR CONTINUE NONE
