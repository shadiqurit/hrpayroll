-- Page 420: After Submit, BEFORE form DML, with normal validations enabled.
-- When Button Pressed = none; server-side condition type PL/SQL Expression:
-- apex_application.g_request IN ('CREATE', 'APPLY', 'SAVE', 'FORWARD')
-- Protect USER_ID/G_COM_ID; see APEX_COMPANY_APPROVAL.md.
-- USER_ID is numeric EMPLOYEES.ID; G_EMP_ID is a character employee/IPI code.
DECLARE
    l_count NUMBER;
    l_empid NUMBER;
    l_stage VARCHAR2(1);
    l_status VARCHAR2(10);
BEGIN
    SELECT COUNT(*) INTO l_count FROM employees
     WHERE id = :USER_ID AND status = 1 AND com_id = :G_COM_ID
       AND id = :P420_EMPID;
    IF l_count <> 1 THEN
        RAISE_APPLICATION_ERROR(-20827, 'Applicant must be the logged-in employee in this company.');
    END IF;
    IF :P420_LEAVE_ID IS NOT NULL THEN
        SELECT empid, request_status, leave_status
          INTO l_empid, l_stage, l_status FROM leave_request
         WHERE leave_id = :P420_LEAVE_ID FOR UPDATE;
        IF l_empid <> TO_NUMBER(:USER_ID) OR NVL(l_stage, '#') <> 'D'
           OR NVL(l_status, '#') NOT IN ('P', 'D') THEN
            RAISE_APPLICATION_ERROR(-20828, 'Only your own draft request can be edited.');
        END IF;
    END IF;
END;
