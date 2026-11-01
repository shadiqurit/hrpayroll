-- Page 422: replace the old "Update the next" process with this block.
-- Install INSTALL_COMPANY_APPROVAL.sql and update Page 420 first.
-- Submit buttons: APPROVE, REJECT, RECORD.
-- After Submit, server-side condition type PL/SQL Expression:
-- apex_application.g_request IN ('APPROVE', 'REJECT', 'RECORD')
-- Exclude these requests from normal form DML.
-- G_EMP_ID is the protected, server-established authenticated EMPLOYEES.ID.
-- Add P422_COMMENTS (optional; maximum 300 bytes).
-- P422_APPROVER_ID/LEVEL/DID/APPROVAL_STATUS are display-only; never trust them
-- to decide who may act. The package checks the stored pending assignment.
-- RP/HOD/PLANT_HEAD approvals activate the next step and retain F/F.
-- MD approval sets A/A and activates HRD; RECORD completes HRD's audit step.
DECLARE
    l_action VARCHAR2(20) := UPPER(apex_application.g_request);
BEGIN
    IF l_action IS NULL OR l_action NOT IN ('APPROVE', 'REJECT', 'RECORD') THEN
        RAISE_APPLICATION_ERROR(-20810, 'Use APPROVE, REJECT, or RECORD.');
    END IF;
    HRMS.pkg_leave_approval.take_action(
        p_leave_id   => :P422_LEAVE_ID,
        p_company_id => :G_COM_ID,
        p_actor_id   => :G_EMP_ID,
        p_action     => l_action,
        p_comments   => :P422_COMMENTS
    );
END;
