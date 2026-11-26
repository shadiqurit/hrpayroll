-- ============================================================================
-- Page 487: Approval & Rejection Process
-- Processing -> Processes -> Add Process
-- Process Name: PROCESS_APPROVAL_ACTION
-- Type: Execute Code (PL/SQL)
-- Server-side Condition: Request IN ('APPROVE_REQ', 'REJECT_REQ')
-- ============================================================================
BEGIN
    IF :REQUEST = 'APPROVE_REQ' THEN
        HRMS.pkg_short_leave_approval.process_approval(
            p_history_id => :P487_ACTION_HIST_ID,
            p_action     => 'APPROVED',
            p_actor_id   => :USER_ID,
            p_comments   => :P487_ACTION_COMMENTS
        );
    ELSIF :REQUEST = 'REJECT_REQ' THEN
        IF TRIM(:P487_ACTION_COMMENTS) IS NULL THEN
            RAISE_APPLICATION_ERROR(-20870, 'বাতিলের কারণ (Rejection Comments) প্রদান করা বাধ্যতামূলক।');
        END IF;

        HRMS.pkg_short_leave_approval.process_approval(
            p_history_id => :P487_ACTION_HIST_ID,
            p_action     => 'REJECTED',
            p_actor_id   => :USER_ID,
            p_comments   => :P487_ACTION_COMMENTS
        );
    END IF;
END;
