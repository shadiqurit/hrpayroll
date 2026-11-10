-- Policy: optional RP recommendation, then ONE eligible higher-tier approval,
-- then HRD recording. Person identifiers are numeric EMPLOYEES.ID.
CREATE OR REPLACE PACKAGE HRMS.pkg_m_att_approval AUTHID DEFINER AS
    -- Use these APIs from APEX; they never commit the caller's transaction.
    FUNCTION workflow_write_allowed RETURN BOOLEAN;
    PROCEDURE save_draft(
        p_att_id IN OUT NUMBER, p_company_id NUMBER, p_actor_id NUMBER,
        p_att_date DATE, p_intime DATE, p_outtime DATE,
        p_reason VARCHAR2, p_comments VARCHAR2 DEFAULT NULL);
    PROCEDURE delete_draft(p_att_id NUMBER, p_company_id NUMBER, p_actor_id NUMBER);
    PROCEDURE submit_request(
        p_att_id NUMBER, p_company_id NUMBER, p_actor_id NUMBER);
    PROCEDURE take_action(
        p_att_id NUMBER, p_company_id NUMBER, p_actor_id NUMBER,
        p_action VARCHAR2, p_comments VARCHAR2 DEFAULT NULL);
END pkg_m_att_approval;
/

CREATE OR REPLACE PACKAGE BODY HRMS.pkg_m_att_approval AS
    g_workflow_write BOOLEAN := FALSE;
    FUNCTION workflow_write_allowed RETURN BOOLEAN IS
    BEGIN
        RETURN g_workflow_write;
    END;

    PROCEDURE validate_times(p_date DATE, p_in DATE, p_out DATE, p_reason VARCHAR2) IS
    BEGIN
        IF p_date IS NULL OR (p_in IS NULL AND p_out IS NULL)
           OR TRIM(p_reason) IS NULL THEN
            RAISE_APPLICATION_ERROR(-20826, 'Attendance date, reason and at least one punch are required.');
        END IF;
        IF (p_in IS NOT NULL AND (p_in < TRUNC(p_date) OR p_in >= TRUNC(p_date) + 2))
           OR (p_out IS NOT NULL AND (p_out < TRUNC(p_date) OR p_out >= TRUNC(p_date) + 2))
           OR (p_in IS NOT NULL AND p_out IS NOT NULL
               AND (p_out < p_in OR p_out - p_in > 1)) THEN
            RAISE_APPLICATION_ERROR(-20826, 'Use full punch dates; OUT must follow IN within 24 hours, including overnight shifts.');
        END IF;
        IF LENGTHB(p_reason) > 200 THEN
            RAISE_APPLICATION_ERROR(-20811, 'Reason must fit within 200 bytes.');
        END IF;
    END;
    TYPE t_step IS RECORD (role_code VARCHAR2(50), employee_id NUMBER);
    TYPE t_route IS TABLE OF t_step INDEX BY PLS_INTEGER;

    FUNCTION role_employee(p_company_id NUMBER, p_role VARCHAR2,
                           p_required BOOLEAN DEFAULT TRUE) RETURN NUMBER IS
        l_id NUMBER;
    BEGIN
        SELECT id INTO l_id FROM v_leave_roles
         WHERE company_id = p_company_id AND UPPER(TRIM(role_code)) = p_role
           AND UPPER(TRIM(active_yn)) = 'Y';
        IF l_id IS NULL THEN
            RAISE_APPLICATION_ERROR(-20801, 'Approval role has no employee: ' || p_role);
        END IF;
        RETURN l_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            IF NOT p_required THEN RETURN NULL; END IF;
            RAISE_APPLICATION_ERROR(-20802, 'Missing active company approval role: ' || p_role);
        WHEN TOO_MANY_ROWS THEN
            RAISE_APPLICATION_ERROR(-20803, 'Multiple active employees for company approval role: ' || p_role);
    END;

    FUNCTION reporting_person(p_empid NUMBER) RETURN NUMBER IS
        l_id NUMBER;
    BEGIN
        SELECT rep_person_id INTO l_id FROM emp_rp
         WHERE emp_id = p_empid AND UPPER(TRIM(status)) IN ('ACTIVE', '1', 'Y')
           AND rep_person_id IS NOT NULL;
        RETURN l_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;
        WHEN TOO_MANY_ROWS THEN
            RAISE_APPLICATION_ERROR(-20821, 'Multiple active reporting-person assignments for applicant.');
    END;

    FUNCTION department_head(p_empid NUMBER, p_company_id NUMBER) RETURN NUMBER IS
        l_id NUMBER;
    BEGIN
        SELECT h.hod_id INTO l_id FROM hod h
          JOIN employees head_emp ON head_emp.id = h.hod_id
         WHERE h.dept_id = (SELECT dept_id FROM employees WHERE id = p_empid)
           AND head_emp.com_id = p_company_id
           AND UPPER(TRIM(h.status)) = 'ACTIVE';
        RETURN l_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;
        WHEN TOO_MANY_ROWS THEN
            RAISE_APPLICATION_ERROR(-20822, 'Multiple department heads for applicant company/department.');
    END;

    FUNCTION is_department_head(p_empid NUMBER, p_company_id NUMBER) RETURN BOOLEAN IS
        l_count NUMBER;
    BEGIN
        -- HOD identity is not restricted to the applicant's own DEPT_ID.
        SELECT COUNT(*) INTO l_count FROM hod h
          JOIN employees e ON e.id = h.hod_id
         WHERE h.hod_id = p_empid AND e.com_id = p_company_id
           AND UPPER(TRIM(h.status)) = 'ACTIVE';
        RETURN l_count > 0;
    END;

    PROCEDURE check_actor(p_actor_id NUMBER) IS
        l_count NUMBER;
    BEGIN
        SELECT COUNT(*) INTO l_count FROM employees WHERE id = p_actor_id AND status = 1;
        IF l_count <> 1 THEN
            RAISE_APPLICATION_ERROR(-20804, 'An active authenticated employee is required.');
        END IF;
    END;

    PROCEDURE check_local_approver(p_empid NUMBER, p_company_id NUMBER) IS
        l_count NUMBER;
    BEGIN
        SELECT COUNT(*) INTO l_count FROM employees
         WHERE id = p_empid AND com_id = p_company_id AND status = 1;
        IF l_count <> 1 THEN
            RAISE_APPLICATION_ERROR(-20823, 'RP/HOD must be an active employee in the applicant company.');
        END IF;
    END;

    PROCEDURE build_route(p_empid NUMBER, p_company_id NUMBER, p_route OUT t_route) IS
        l_plant NUMBER;
        l_md NUMBER;
        l_finals NUMBER := 0;
    BEGIN
        p_route.DELETE;
        p_route(1).role_code := 'RP';
        p_route(2).role_code := 'HOD';
        p_route(3).role_code := 'PLANT_HEAD';
        p_route(4).role_code := 'MANAGING_DIRECTOR';
        p_route(5).role_code := 'LEAVE_RECORD';
        -- MD is not a required approval assignment for ordinary employees.
        l_plant := role_employee(p_company_id, 'PLANT_HEAD', FALSE);
        l_md := role_employee(p_company_id, 'MANAGING_DIRECTOR', FALSE);
        p_route(5).employee_id := role_employee(p_company_id, 'LEAVE_RECORD');
        IF p_empid = l_md THEN
            RAISE_APPLICATION_ERROR(-20809, 'MD manual attendance needs a separately configured higher approver; self-approval is not allowed.');
        ELSIF p_empid = l_plant THEN
            p_route(4).employee_id := l_md;
        ELSIF is_department_head(p_empid, p_company_id) THEN
            p_route(3).employee_id := l_plant;
            p_route(4).employee_id := l_md;
        ELSE
            p_route(1).employee_id := reporting_person(p_empid);
            p_route(2).employee_id := department_head(p_empid, p_company_id);
            p_route(3).employee_id := l_plant;
        END IF;
        -- One candidate per person, at their highest eligible final role.
        FOR i IN 2 .. 4 LOOP
            IF p_route(i).employee_id = p_empid THEN
                p_route(i).employee_id := NULL;
            END IF;
            FOR j IN i + 1 .. 4 LOOP
                IF p_route(i).employee_id = p_route(j).employee_id THEN
                    p_route(i).employee_id := NULL;
                END IF;
            END LOOP;
        END LOOP;
        -- An RP who also holds a final role acts once as a final approver.
        IF p_route(1).employee_id = p_empid THEN
            p_route(1).employee_id := NULL;
        END IF;
        FOR i IN 2 .. 4 LOOP
            IF p_route(i).employee_id IS NOT NULL THEN
                l_finals := l_finals + 1;
                IF p_route(1).employee_id = p_route(i).employee_id THEN
                    p_route(1).employee_id := NULL;
                END IF;
            END IF;
        END LOOP;
        IF l_finals = 0 THEN
            RAISE_APPLICATION_ERROR(-20830, 'At least one eligible higher-tier final approver must be configured.');
        END IF;
        FOR i IN 1 .. 5 LOOP
            IF p_route(i).employee_id IS NOT NULL THEN
                check_actor(p_route(i).employee_id);
                IF i IN (1, 2) THEN
                    check_local_approver(p_route(i).employee_id, p_company_id);
                END IF;
            END IF;
        END LOOP;
    END;

    PROCEDURE check_history(p_att_id NUMBER, p_company_id NUMBER) IS
        l_request manual_att%ROWTYPE;
        l_route t_route;
        l_expected NUMBER := 0;
        l_count NUMBER;
        l_rp NUMBER;
        l_rp_pending NUMBER;
        l_rp_approved NUMBER;
        l_rp_rejected NUMBER;
        l_finals NUMBER;
        l_final_waiting NUMBER;
        l_final_pending NUMBER;
        l_final_approved NUMBER;
        l_final_rejected NUMBER;
        l_final_cancelled NUMBER;
        l_record_waiting NUMBER;
        l_record_pending NUMBER;
        l_record_done NUMBER;
        l_record_cancelled NUMBER;
        l_valid BOOLEAN := FALSE;
    BEGIN
        SELECT * INTO l_request FROM manual_att WHERE id = p_att_id;
        IF NVL(l_request.workflow_version, 0) <> 1
           OR l_request.com_id IS NULL OR l_request.com_id <> p_company_id THEN
            RAISE_APPLICATION_ERROR(-20820, 'Legacy request or changed company requires administrator review.');
        END IF;
        build_route(l_request.empid, p_company_id, l_route);
        -- Match the full saved candidate set to the current authorized route.
        -- Old sequential histories and changed assignments are never rewritten.
        FOR i IN 1 .. 5 LOOP
            IF l_route(i).employee_id IS NOT NULL THEN
                l_expected := l_expected + 1;
                SELECT COUNT(*) INTO l_count FROM m_att_app_history
                 WHERE m_att_id = p_att_id AND com_id = p_company_id
                   AND approver_level = l_route(i).role_code
                   AND approver_id = l_route(i).employee_id
                   AND approval_status IN
                       ('WAITING', 'PENDING', 'APPROVED', 'REJECTED', 'CANCELLED', 'RECORDED');
                IF l_count <> 1 THEN
                    RAISE_APPLICATION_ERROR(-20820, 'Saved route is legacy, incomplete, duplicated, or assignment changed; administrator review required.');
                END IF;
            END IF;
        END LOOP;
        SELECT COUNT(*) INTO l_count FROM m_att_app_history WHERE m_att_id = p_att_id;
        IF l_count <> l_expected THEN
            RAISE_APPLICATION_ERROR(-20820, 'Saved route contains unexpected approval steps; administrator review required.');
        END IF;
        SELECT COUNT(CASE WHEN approver_level = 'RP' THEN 1 END),
               COUNT(CASE WHEN approver_level = 'RP' AND approval_status = 'PENDING' THEN 1 END),
               COUNT(CASE WHEN approver_level = 'RP' AND approval_status = 'APPROVED' THEN 1 END),
               COUNT(CASE WHEN approver_level = 'RP' AND approval_status = 'REJECTED' THEN 1 END),
               COUNT(CASE WHEN approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR') THEN 1 END),
               COUNT(CASE WHEN approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR') AND approval_status = 'WAITING' THEN 1 END),
               COUNT(CASE WHEN approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR') AND approval_status = 'PENDING' THEN 1 END),
               COUNT(CASE WHEN approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR') AND approval_status = 'APPROVED' THEN 1 END),
               COUNT(CASE WHEN approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR') AND approval_status = 'REJECTED' THEN 1 END),
               COUNT(CASE WHEN approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR') AND approval_status = 'CANCELLED' THEN 1 END),
               COUNT(CASE WHEN approver_level = 'LEAVE_RECORD' AND approval_status = 'WAITING' THEN 1 END),
               COUNT(CASE WHEN approver_level = 'LEAVE_RECORD' AND approval_status = 'PENDING' THEN 1 END),
               COUNT(CASE WHEN approver_level = 'LEAVE_RECORD' AND approval_status = 'RECORDED' THEN 1 END),
               COUNT(CASE WHEN approver_level = 'LEAVE_RECORD' AND approval_status = 'CANCELLED' THEN 1 END)
          INTO l_rp, l_rp_pending, l_rp_approved, l_rp_rejected,
               l_finals, l_final_waiting, l_final_pending, l_final_approved,
               l_final_rejected, l_final_cancelled,
               l_record_waiting, l_record_pending, l_record_done, l_record_cancelled
          FROM m_att_app_history WHERE m_att_id = p_att_id;
        IF l_request.status = 'F' AND l_request.request_status = 'F' THEN
            l_valid := l_record_waiting = 1 AND
                ((l_rp_pending = 1 AND l_final_waiting = l_finals)
                 OR (l_rp = l_rp_approved AND l_final_pending = l_finals));
        ELSIF l_request.status = 'A' AND l_request.request_status = 'A' THEN
            l_valid := l_rp = l_rp_approved AND l_final_approved = 1
                AND l_final_cancelled = l_finals - 1
                AND l_record_pending + l_record_done = 1;
        ELSIF l_request.status = 'R' AND l_request.request_status = 'F' THEN
            l_valid := l_record_cancelled = 1 AND
                ((l_rp_rejected = 1 AND l_final_cancelled = l_finals)
                 OR (l_rp = l_rp_approved AND l_final_rejected = 1
                     AND l_final_cancelled = l_finals - 1));
        END IF;
        IF NOT l_valid THEN
            RAISE_APPLICATION_ERROR(-20820, 'Approval groups or request statuses are inconsistent; administrator review required.');
        END IF;
    END;

    PROCEDURE save_draft(
        p_att_id IN OUT NUMBER, p_company_id NUMBER, p_actor_id NUMBER,
        p_att_date DATE, p_intime DATE, p_outtime DATE,
        p_reason VARCHAR2, p_comments VARCHAR2 DEFAULT NULL) IS
        l_request manual_att%ROWTYPE;
        l_company NUMBER;
        l_code employees.emp_id%TYPE;
        l_count NUMBER;
        l_original_id NUMBER := p_att_id;
    BEGIN
        SAVEPOINT m_att_save_start;
        check_actor(p_actor_id);
        validate_times(p_att_date, p_intime, p_outtime, p_reason);
        IF LENGTHB(p_comments) > 1000 THEN
            RAISE_APPLICATION_ERROR(-20811, 'Request comments must fit within 1000 bytes.');
        END IF;
        SELECT com_id, emp_id INTO l_company, l_code FROM employees WHERE id = p_actor_id;
        IF p_company_id IS NULL OR l_company IS NULL OR l_company <> p_company_id THEN
            RAISE_APPLICATION_ERROR(-20805, 'Applicant does not belong to the selected company.');
        END IF;
        IF p_att_id IS NULL THEN
            INSERT INTO manual_att
                (empid, empcode, com_id, att_date, m_intime, m_outtime, reason,
                 comments, status, request_status, workflow_version, ent_by)
            VALUES (p_actor_id, l_code, l_company, TRUNC(p_att_date), p_intime, p_outtime,
                    TRIM(p_reason), p_comments, 'D', 'D', 1, p_actor_id)
            RETURNING id INTO p_att_id;
        ELSE
            SELECT * INTO l_request FROM manual_att WHERE id = p_att_id FOR UPDATE;
            IF l_request.empid IS NULL OR l_request.empid <> p_actor_id
               OR l_request.com_id IS NULL OR l_request.com_id <> p_company_id THEN
                RAISE_APPLICATION_ERROR(-20806, 'Only the applicant can edit this company request.');
            END IF;
            SELECT COUNT(*) INTO l_count FROM m_att_app_history WHERE m_att_id = p_att_id;
            IF NVL(l_request.request_status, '#') <> 'D' OR NVL(l_request.status, '#') NOT IN ('P', 'D')
               OR l_count <> 0 OR NVL(l_request.workflow_version, 0) <> 1 THEN
                RAISE_APPLICATION_ERROR(-20807, 'Only a new-workflow draft without history can be edited.');
            END IF;
            UPDATE manual_att SET att_date = TRUNC(p_att_date), m_intime = p_intime,
                m_outtime = p_outtime, reason = TRIM(p_reason), comments = p_comments,
                upd_date = SYSDATE, upd_by = p_actor_id WHERE id = p_att_id;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        ROLLBACK TO m_att_save_start;
        p_att_id := l_original_id;
        RAISE;
    END;

    PROCEDURE delete_draft(p_att_id NUMBER, p_company_id NUMBER, p_actor_id NUMBER) IS
        l_request manual_att%ROWTYPE;
        l_company NUMBER;
        l_count NUMBER;
    BEGIN
        SAVEPOINT m_att_delete_start;
        check_actor(p_actor_id);
        SELECT * INTO l_request FROM manual_att WHERE id = p_att_id FOR UPDATE;
        SELECT com_id INTO l_company FROM employees WHERE id = l_request.empid;
        IF p_company_id IS NULL OR l_company IS NULL OR l_company <> p_company_id
           OR l_request.com_id IS NULL OR l_request.com_id <> p_company_id THEN
            RAISE_APPLICATION_ERROR(-20805, 'Request does not belong to the selected company.');
        END IF;
        IF l_request.empid IS NULL OR l_request.empid <> p_actor_id THEN
            RAISE_APPLICATION_ERROR(-20806, 'Only the applicant can delete this draft.');
        END IF;
        SELECT COUNT(*) INTO l_count FROM m_att_app_history WHERE m_att_id = p_att_id;
        IF NVL(l_request.request_status, '#') <> 'D'
           OR NVL(l_request.status, '#') NOT IN ('P', 'D') OR l_count <> 0 THEN
            RAISE_APPLICATION_ERROR(-20807, 'Only a draft without approval history can be deleted.');
        END IF;
        DELETE FROM manual_att WHERE id = p_att_id;
    EXCEPTION WHEN OTHERS THEN
        ROLLBACK TO m_att_delete_start;
        RAISE;
    END;

    PROCEDURE submit_request(
        p_att_id NUMBER, p_company_id NUMBER, p_actor_id NUMBER) IS
        l_route t_route;
        l_request manual_att%ROWTYPE;
        l_company NUMBER;
        l_count NUMBER;
        l_status VARCHAR2(50);
    BEGIN
        SAVEPOINT m_att_submit_start;
        check_actor(p_actor_id);
        SELECT * INTO l_request FROM manual_att WHERE id = p_att_id FOR UPDATE;
        SELECT com_id INTO l_company FROM employees WHERE id = l_request.empid;
        IF p_company_id IS NULL OR l_company IS NULL OR l_company <> p_company_id THEN
            RAISE_APPLICATION_ERROR(-20805, 'Request does not belong to the selected company.');
        END IF;
        IF l_request.empid IS NULL OR l_request.empid <> p_actor_id THEN
            RAISE_APPLICATION_ERROR(-20806, 'Only the applicant can submit this request.');
        END IF;
        IF NVL(l_request.request_status, '#') <> 'D'
           OR NVL(l_request.status, '#') NOT IN ('P', 'D') THEN
            RAISE_APPLICATION_ERROR(-20807, 'Only a draft request can be submitted.');
        END IF;
        IF NVL(l_request.workflow_version, 0) <> 1 THEN
            RAISE_APPLICATION_ERROR(-20808, 'Legacy request requires administrator review. Create a new draft.');
        END IF;
        validate_times(l_request.att_date, l_request.m_intime, l_request.m_outtime, l_request.reason);
        IF l_request.com_id IS NULL OR l_request.com_id <> l_company THEN
            RAISE_APPLICATION_ERROR(-20805, 'Request company does not match the applicant company.');
        END IF;
        SELECT COUNT(*) INTO l_count FROM m_att_app_history WHERE m_att_id = p_att_id;
        IF l_count <> 0 THEN
            RAISE_APPLICATION_ERROR(-20808, 'Existing approval history requires review before submission.');
        END IF;
        SELECT com_id INTO l_company FROM employees WHERE id = l_request.empid FOR UPDATE;
        SELECT COUNT(*) INTO l_count FROM manual_att
         WHERE empid = l_request.empid AND TRUNC(att_date) = TRUNC(l_request.att_date)
           AND id <> p_att_id
           AND (UPPER(TRIM(status)) IN ('F', 'A', 'APPROVED', 'PENDING')
                OR (UPPER(TRIM(status)) = 'P' AND request_status = 'F'));
        IF l_count <> 0 THEN
            RAISE_APPLICATION_ERROR(-20827, 'Another pending or approved correction exists for this employee/date.');
        END IF;
        build_route(l_request.empid, l_company, l_route);
        FOR i IN 1 .. 5 LOOP
            IF l_route(i).employee_id IS NOT NULL THEN
                IF i = 1 OR (i IN (2, 3, 4) AND l_route(1).employee_id IS NULL) THEN
                    l_status := 'PENDING';
                ELSE
                    l_status := 'WAITING';
                END IF;
                INSERT INTO m_att_app_history
                    (m_att_id, approver_level, approver_id, approval_status,
                     com_id, comments, ent_date, ent_by)
                VALUES (p_att_id, l_route(i).role_code, l_route(i).employee_id,
                        l_status, l_company, 'Assigned: ' || l_route(i).role_code,
                        SYSDATE, p_actor_id);
            END IF;
        END LOOP;
        g_workflow_write := TRUE;
        UPDATE manual_att
           SET status = 'F', request_status = 'F', upd_date = SYSDATE, upd_by = p_actor_id
         WHERE id = p_att_id;
        g_workflow_write := FALSE;
        check_history(p_att_id, l_company);
    EXCEPTION WHEN OTHERS THEN
        g_workflow_write := FALSE;
        ROLLBACK TO m_att_submit_start;
        RAISE;
    END;

    PROCEDURE take_action(
        p_att_id NUMBER, p_company_id NUMBER, p_actor_id NUMBER,
        p_action VARCHAR2, p_comments VARCHAR2 DEFAULT NULL) IS
        l_request manual_att%ROWTYPE;
        l_step m_att_app_history%ROWTYPE;
        l_company NUMBER;
        l_action VARCHAR2(20) := UPPER(TRIM(p_action));
    BEGIN
        SAVEPOINT m_att_action_start;
        check_actor(p_actor_id);
        IF l_action IS NULL OR l_action NOT IN ('APPROVE', 'REJECT', 'RECORD') THEN
            RAISE_APPLICATION_ERROR(-20810, 'Use APPROVE, REJECT, or RECORD.');
        END IF;
        IF LENGTHB(p_comments) > 300 THEN
            RAISE_APPLICATION_ERROR(-20811, 'Comments must fit within 300 bytes.');
        END IF;
        -- Serialize all candidates on their parent so only one decision wins.
        SELECT * INTO l_request FROM manual_att WHERE id = p_att_id FOR UPDATE;
        SELECT com_id INTO l_company FROM employees WHERE id = l_request.empid;
        IF p_company_id IS NULL OR l_company IS NULL OR l_company <> p_company_id THEN
            RAISE_APPLICATION_ERROR(-20805, 'Request does not belong to the selected company.');
        END IF;
        check_history(p_att_id, p_company_id);
        SELECT * INTO l_step FROM m_att_app_history
         WHERE m_att_id = p_att_id AND com_id = p_company_id
           AND approver_id = p_actor_id AND approval_status = 'PENDING' FOR UPDATE;
        IF l_action = 'RECORD' THEN
            IF l_step.approver_level <> 'LEAVE_RECORD'
               OR NVL(l_request.status, '#') <> 'A'
               OR NVL(l_request.request_status, '#') <> 'A' THEN
                RAISE_APPLICATION_ERROR(-20813, 'HRD can record only after a final HOD, Plant Head, or MD approval.');
            END IF;
        ELSE
            IF l_step.approver_level = 'LEAVE_RECORD'
               OR NVL(l_request.status, '#') <> 'F'
               OR NVL(l_request.request_status, '#') <> 'F'
               OR l_request.empid = p_actor_id THEN
                RAISE_APPLICATION_ERROR(-20814, 'This request is not available for your approval.');
            END IF;
        END IF;
        UPDATE m_att_app_history
           SET approval_status = CASE l_action WHEN 'APPROVE' THEN 'APPROVED'
                                  WHEN 'REJECT' THEN 'REJECTED' ELSE 'RECORDED' END,
               approval_date = SYSDATE, comments = p_comments,
               upd_date = SYSDATE, upd_by = p_actor_id
         WHERE id = l_step.id AND approval_status = 'PENDING';
        IF SQL%ROWCOUNT <> 1 THEN
            RAISE_APPLICATION_ERROR(-20815, 'Approval history is inconsistent; no action was saved.');
        END IF;
        IF l_action = 'REJECT' THEN
            UPDATE m_att_app_history
               SET approval_status = 'CANCELLED', upd_date = SYSDATE, upd_by = p_actor_id
             WHERE m_att_id = p_att_id AND approval_status IN ('PENDING', 'WAITING');
        ELSIF l_action = 'APPROVE' AND l_step.approver_level = 'RP' THEN
            UPDATE m_att_app_history
               SET approval_status = 'PENDING', upd_date = SYSDATE, upd_by = p_actor_id
             WHERE m_att_id = p_att_id AND approval_status = 'WAITING'
               AND approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR');
            IF SQL%ROWCOUNT < 1 THEN
                RAISE_APPLICATION_ERROR(-20816, 'An eligible final approver is required after RP recommendation.');
            END IF;
        ELSIF l_action = 'APPROVE' THEN
            UPDATE m_att_app_history
               SET approval_status = 'CANCELLED', upd_date = SYSDATE, upd_by = p_actor_id
             WHERE m_att_id = p_att_id AND approval_status = 'PENDING'
               AND approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR');
            UPDATE m_att_app_history
               SET approval_status = 'PENDING', upd_date = SYSDATE, upd_by = p_actor_id
             WHERE m_att_id = p_att_id AND approver_level = 'LEAVE_RECORD'
               AND approval_status = 'WAITING';
            IF SQL%ROWCOUNT <> 1 THEN
                RAISE_APPLICATION_ERROR(-20816, 'Exactly one HRD recording step is required.');
            END IF;
        END IF;
        g_workflow_write := TRUE;
        UPDATE manual_att
           SET status = CASE WHEN l_action = 'REJECT' THEN 'R'
                                   WHEN l_action = 'RECORD' OR l_step.approver_level <> 'RP'
                                   THEN 'A' ELSE 'F' END,
               request_status = CASE WHEN l_action = 'REJECT' THEN 'F'
                                     WHEN l_action = 'RECORD' OR l_step.approver_level <> 'RP'
                                     THEN 'A' ELSE 'F' END,
               upd_date = SYSDATE, upd_by = p_actor_id
         WHERE id = p_att_id;
        g_workflow_write := FALSE;
        check_history(p_att_id, l_company);
        IF l_action = 'APPROVE' AND l_step.approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR') THEN
            HRMS.post_manual_attendance(p_att_id, l_company, p_actor_id);
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            g_workflow_write := FALSE;
            ROLLBACK TO m_att_action_start;
            RAISE_APPLICATION_ERROR(-20817, 'No pending action is assigned to you for this request and company.');
        WHEN TOO_MANY_ROWS THEN
            g_workflow_write := FALSE;
            ROLLBACK TO m_att_action_start;
            RAISE_APPLICATION_ERROR(-20818, 'Duplicate pending assignments for one actor require administrator review.');
        WHEN OTHERS THEN
            g_workflow_write := FALSE;
            ROLLBACK TO m_att_action_start;
            RAISE;
    END;
END pkg_m_att_approval;
/
