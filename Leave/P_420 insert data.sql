-- Page 420: replace the old RP/HOD approval-history INSERT process with this.
-- Install INSTALL_COMPANY_APPROVAL.sql first (removes the old INSERT trigger).
-- After Submit, AFTER form DML and BEFORE any success branch.
-- When Button Pressed = none; server-side condition type PL/SQL Expression:
-- apex_application.g_request IN ('CREATE', 'SAVE', 'APPLY', 'FORWARD')
-- Default APEX form: CREATE inserts and submits; SAVE updates and submits.
-- Use these button Names (not just Labels). SAVE submits a saved draft too.
-- Run form DML for CREATE/APPLY/SAVE/FORWARD and return P420_LEAVE_ID.
-- Run P_420 validate draft.sql BEFORE form DML for the same four requests.
-- USER_ID = authenticated numeric EMPLOYEES.ID, set server-side at login.
-- G_EMP_ID = character employee/IPI code; do not pass it as an actor ID.
-- G_COM_ID = selected authorized company. Protect both application items from
-- browser assignment; do not obtain the actor from P420_EMPID.
-- DML: Return Primary Key(s) after Insert = Yes; LEAVE_ID -> P420_LEAVE_ID.
-- CREATE/SAVE/APPLY/FORWARD create the ordered company route after saving:
-- Employee: optional RP, then HOD OR PLANT_HEAD; HOD: PLANT_HEAD OR MD;
-- Plant Head: MD. One final decision activates HRD LEAVE_RECORD.
-- Shared-role people act once; see APEX_COMPANY_APPROVAL.md.
BEGIN
    IF apex_application.g_request IN ('CREATE', 'SAVE', 'APPLY', 'FORWARD') THEN
        IF :P420_LEAVE_ID IS NULL THEN
            RAISE_APPLICATION_ERROR(-20829,
                'LEAVE_ID is missing. Run form DML first and enable Return Primary Key(s) after Insert.');
        END IF;
        HRMS.pkg_leave_approval.submit_request(
            p_leave_id   => :P420_LEAVE_ID,
            p_company_id => :G_COM_ID,
            p_actor_id   => :USER_ID
        );
    END IF;
END;
