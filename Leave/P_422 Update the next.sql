-- Page 422: replace the old "Update the next" process with this block.
-- Install INSTALL_COMPANY_APPROVAL.sql and update Page 420 first.
-- P422_APPROVAL_STATUS: user action select list, APPROVE / REJECT return values.
-- Source = Null; no database column mapping/default. It is not stored status.
-- Submit buttons: SUBMIT_ACTION (selected approval action), RECORD (HRD only).
-- After Submit, server-side condition type PL/SQL Expression:
-- apex_application.g_request IN ('SUBMIT_ACTION', 'RECORD')
-- Exclude these requests from normal form DML.
-- USER_ID is the protected, server-established numeric EMPLOYEES.ID.
-- G_EMP_ID is a character employee/IPI code, not an approver/actor ID.
-- Add P422_COMMENTS (optional; maximum 300 bytes).
-- P422_APPROVER_ID/LEVEL/DID are display-only. The selected action grants no
-- authority: the package checks the actor and stored pending assignment.
-- RP recommendation activates all eligible final candidates and retains F/F.
-- ONE HOD/Plant Head/MD approval sets A/A and cancels alternatives.
-- Package posts consumption once at final approval and blocks insufficient balance.
-- HRD RECORD completes the audit step after the final decision.
DECLARE
    l_action VARCHAR2(20);
BEGIN
    IF apex_application.g_request = 'SUBMIT_ACTION' THEN
        IF UPPER(TRIM(:P422_APPROVAL_STATUS)) IS NULL
           OR UPPER(TRIM(:P422_APPROVAL_STATUS)) NOT IN ('APPROVE', 'REJECT') THEN
            RAISE_APPLICATION_ERROR(-20810, 'Select APPROVE or REJECT.');
        END IF;
        l_action := UPPER(TRIM(:P422_APPROVAL_STATUS));
    ELSIF apex_application.g_request = 'RECORD' THEN
        l_action := 'RECORD';
    ELSE
        RAISE_APPLICATION_ERROR(-20810, 'Use SUBMIT_ACTION or RECORD.');
    END IF;
    HRMS.pkg_leave_approval.take_action(
        p_leave_id   => :P422_LEAVE_ID,
        p_company_id => :G_COM_ID,
        p_actor_id   => :USER_ID,
        p_action     => l_action,
        p_comments   => :P422_COMMENTS
    );
END;
