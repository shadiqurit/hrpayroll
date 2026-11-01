-- Page 420: replace the old RP/HOD approval-history INSERT process with this.
-- Install INSTALL_COMPANY_APPROVAL.sql first (removes the old INSERT trigger).
-- After Submit, AFTER form DML, When Button Pressed = FORWARD.
-- Run form DML for CREATE/SAVE/FORWARD, but only permit edits to draft requests.
-- G_EMP_ID = authenticated EMPLOYEES.ID, set server-side after authentication.
-- G_COM_ID = selected authorized company. Protect both application items from
-- browser assignment; do not obtain the actor from P420_EMPID.
-- A new draft has no history. FORWARD creates the ordered company route:
-- RP (if assigned), HOD (if assigned), PLANT_HEAD, MANAGING_DIRECTOR, LEAVE_RECORD.
-- Heads skip their own and lower approval levels; see APEX_COMPANY_APPROVAL.md.
BEGIN
    HRMS.pkg_leave_approval.submit_request(
        p_leave_id   => :P420_LEAVE_ID,
        p_company_id => :G_COM_ID,
        p_actor_id   => :G_EMP_ID
    );
END;
