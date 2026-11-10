-- Machine + approved manual corrections. Leave/short-leave replay is separate.
-- Use this in place of the machine-only wrapper for dates with manual requests.
CREATE OR REPLACE PROCEDURE HRMS.p_att_rebuild_manual(
    p_from_date DATE, p_to_date DATE, p_commit NUMBER DEFAULT 1) AUTHID DEFINER IS
    l_from DATE;
    l_to DATE;
    l_count NUMBER;
BEGIN
    IF p_from_date IS NULL OR p_to_date IS NULL OR TRUNC(p_to_date) < TRUNC(p_from_date) THEN
        RAISE_APPLICATION_ERROR(-20901, 'Supply a valid attendance date range.');
    END IF;
    IF p_commit IS NULL OR p_commit NOT IN (0, 1) THEN
        RAISE_APPLICATION_ERROR(-20902, 'p_commit must be 0 or 1.');
    END IF;
    l_from := TRUNC(p_from_date) - 1;
    l_to := TRUNC(p_to_date) + 1;
    SAVEPOINT manual_rebuild_start;
    BEGIN
        SELECT COUNT(*) INTO l_count FROM manual_att
         WHERE att_date >= l_from AND att_date < l_to + 1
           AND workflow_version = 0 AND UPPER(TRIM(status)) IN ('A', 'APPROVED');
        IF l_count > 0 THEN
            RAISE_APPLICATION_ERROR(-20820, 'Legacy approved corrections in this range require review before rebuilding.');
        END IF;
        -- Lock request rows before attendance rows, matching final approval.
        -- Include forwarded requests so a concurrent approval cannot be lost.
        FOR r IN (SELECT id FROM manual_att
                   WHERE att_date >= l_from AND att_date < l_to + 1
                     AND workflow_version = 1 AND status IN ('F', 'A')
                   ORDER BY id FOR UPDATE) LOOP
            NULL;
        END LOOP;
        HRMS.p_att_schedule(l_from, l_to, p_commit => 0);
        HRMS.p_att_cont_shift_fast(l_from, l_to, p_commit => 0);
        -- Explicit approved times win over machine/continuous derivation.
        -- Reusing posting also checks missing/duplicate target rows.
        FOR r IN (
            SELECT ma.id, ma.com_id, h.approver_id
              FROM manual_att ma JOIN m_att_app_history h ON h.m_att_id = ma.id
             WHERE ma.att_date >= l_from AND ma.att_date < l_to + 1
               AND ma.workflow_version = 1 AND ma.status = 'A' AND ma.request_status = 'A'
               AND h.approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR')
               AND h.approval_status = 'APPROVED'
             ORDER BY ma.id
        ) LOOP
            HRMS.post_manual_attendance(r.id, r.com_id, r.approver_id);
        END LOOP;
        HRMS.p_att_update_details(l_from, l_to, p_commit => 0);
        IF p_commit = 1 THEN COMMIT; END IF;
    EXCEPTION WHEN OTHERS THEN
        ROLLBACK TO manual_rebuild_start;
        RAISE;
    END;
END;
/
