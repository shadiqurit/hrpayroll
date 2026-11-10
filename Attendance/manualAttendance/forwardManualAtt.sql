-- Legacy signature retained as a fail-safe for stale APEX processes.
-- Migrate pages to PKG_M_ATT_APPROVAL with the authenticated company/actor.
CREATE OR REPLACE PROCEDURE HRMS.forward_attendance_approval(
    p_att_id NUMBER, p_approver_id NUMBER, p_approval_status VARCHAR2,
    p_approver_level VARCHAR2, p_action VARCHAR2) AUTHID DEFINER IS
BEGIN
    -- Old F/A/P values ambiguously meant submit, recommend or final approval.
    RAISE_APPLICATION_ERROR(-20810,
        'Replace the legacy process with PKG_M_ATT_APPROVAL.SUBMIT_REQUEST or TAKE_ACTION; see manualAttendance/README.md.');
END;
/
