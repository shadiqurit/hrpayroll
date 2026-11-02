-- Policy: optional RP recommendation, then ONE eligible higher-tier approval,
-- then HRD recording. Person identifiers are numeric EMPLOYEES.ID.
CREATE OR REPLACE PACKAGE HRMS.pkg_leave_approval AUTHID DEFINER AS
    PROCEDURE submit_request(
        p_leave_id NUMBER, p_company_id NUMBER, p_actor_id NUMBER);
    PROCEDURE take_action(
        p_leave_id NUMBER, p_company_id NUMBER, p_actor_id NUMBER,
        p_action VARCHAR2, p_comments VARCHAR2 DEFAULT NULL);
END pkg_leave_approval;
/

CREATE OR REPLACE PACKAGE BODY HRMS.pkg_leave_approval AS
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
            RAISE_APPLICATION_ERROR(-20801, 'Leave role has no employee: ' || p_role);
        END IF;
        RETURN l_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            IF NOT p_required THEN RETURN NULL; END IF;
            RAISE_APPLICATION_ERROR(-20802, 'Missing active company leave role: ' || p_role);
        WHEN TOO_MANY_ROWS THEN
            RAISE_APPLICATION_ERROR(-20803, 'Multiple active employees for company leave role: ' || p_role);
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
            RAISE_APPLICATION_ERROR(-20809, 'MD leave needs a separately configured higher approver; self-approval is not allowed.');
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

    PROCEDURE check_history(p_leave_id NUMBER, p_company_id NUMBER) IS
        l_request leave_request%ROWTYPE;
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
        SELECT * INTO l_request FROM leave_request WHERE leave_id = p_leave_id;
        build_route(l_request.empid, p_company_id, l_route);
        -- Match the full saved candidate set to the current authorized route.
        -- Old sequential histories and changed assignments are never rewritten.
        FOR i IN 1 .. 5 LOOP
            IF l_route(i).employee_id IS NOT NULL THEN
                l_expected := l_expected + 1;
                SELECT COUNT(*) INTO l_count FROM leave_app_history
                 WHERE leave_id = p_leave_id AND com_id = p_company_id
                   AND approver_level = l_route(i).role_code
                   AND approver_id = l_route(i).employee_id
                   AND approval_status IN
                       ('WAITING', 'PENDING', 'APPROVED', 'REJECTED', 'CANCELLED', 'RECORDED');
                IF l_count <> 1 THEN
                    RAISE_APPLICATION_ERROR(-20820, 'Saved route is legacy, incomplete, duplicated, or assignment changed; administrator review required.');
                END IF;
            END IF;
        END LOOP;
        SELECT COUNT(*) INTO l_count FROM leave_app_history WHERE leave_id = p_leave_id;
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
          FROM leave_app_history WHERE leave_id = p_leave_id;
        IF l_request.leave_status = 'F' AND l_request.request_status = 'F' THEN
            l_valid := l_record_waiting = 1 AND
                ((l_rp_pending = 1 AND l_final_waiting = l_finals)
                 OR (l_rp = l_rp_approved AND l_final_pending = l_finals));
        ELSIF l_request.leave_status = 'A' AND l_request.request_status = 'A' THEN
            l_valid := l_rp = l_rp_approved AND l_final_approved = 1
                AND l_final_cancelled = l_finals - 1
                AND l_record_pending + l_record_done = 1;
        ELSIF l_request.leave_status = 'R' AND l_request.request_status = 'F' THEN
            l_valid := l_record_cancelled = 1 AND
                ((l_rp_rejected = 1 AND l_final_cancelled = l_finals)
                 OR (l_rp = l_rp_approved AND l_final_rejected = 1
                     AND l_final_cancelled = l_finals - 1));
        END IF;
        IF NOT l_valid THEN
            RAISE_APPLICATION_ERROR(-20820, 'Approval groups or request statuses are inconsistent; administrator review required.');
        END IF;
    END;

    PROCEDURE submit_request(
        p_leave_id NUMBER, p_company_id NUMBER, p_actor_id NUMBER) IS
        l_route t_route;
        l_request leave_request%ROWTYPE;
        l_company NUMBER;
        l_count NUMBER;
        l_status VARCHAR2(50);
    BEGIN
        SAVEPOINT leave_submit_start;
        check_actor(p_actor_id);
        SELECT * INTO l_request FROM leave_request WHERE leave_id = p_leave_id FOR UPDATE;
        SELECT com_id INTO l_company FROM employees WHERE id = l_request.empid;
        IF p_company_id IS NULL OR l_company IS NULL OR l_company <> p_company_id THEN
            RAISE_APPLICATION_ERROR(-20805, 'Request does not belong to the selected company.');
        END IF;
        IF l_request.empid <> p_actor_id THEN
            RAISE_APPLICATION_ERROR(-20806, 'Only the applicant can submit this request.');
        END IF;
        IF NVL(l_request.request_status, '#') <> 'D'
           OR NVL(l_request.leave_status, '#') NOT IN ('P', 'D') THEN
            RAISE_APPLICATION_ERROR(-20807, 'Only a draft request can be submitted.');
        END IF;
        IF l_request.l_start_date IS NULL OR l_request.l_end_date IS NULL
           OR TRUNC(l_request.l_end_date) < TRUNC(l_request.l_start_date)
           OR l_request.proposed_days IS NULL OR l_request.proposed_days <= 0 THEN
            RAISE_APPLICATION_ERROR(-20826, 'Valid leave dates and positive proposed days are required.');
        END IF;
        SELECT COUNT(*) INTO l_count FROM leave_app_history WHERE leave_id = p_leave_id;
        IF l_count <> 0 THEN
            RAISE_APPLICATION_ERROR(-20808, 'Existing approval history requires review before submission.');
        END IF;
        build_route(l_request.empid, l_company, l_route);
        FOR i IN 1 .. 5 LOOP
            IF l_route(i).employee_id IS NOT NULL THEN
                IF i = 1 OR (i IN (2, 3, 4) AND l_route(1).employee_id IS NULL) THEN
                    l_status := 'PENDING';
                ELSE
                    l_status := 'WAITING';
                END IF;
                INSERT INTO leave_app_history
                    (leave_id, approver_level, approver_id, approval_status,
                     com_id, comments, ent_date, ent_by)
                VALUES (p_leave_id, l_route(i).role_code, l_route(i).employee_id,
                        l_status, l_company, 'Assigned: ' || l_route(i).role_code,
                        SYSDATE, p_actor_id);
            END IF;
        END LOOP;
        UPDATE leave_request
           SET leave_status = 'F', request_status = 'F', upd_date = SYSDATE, upd_by = p_actor_id
         WHERE leave_id = p_leave_id;
        check_history(p_leave_id, l_company);
    EXCEPTION WHEN OTHERS THEN
        ROLLBACK TO leave_submit_start;
        RAISE;
    END;

    PROCEDURE take_action(
        p_leave_id NUMBER, p_company_id NUMBER, p_actor_id NUMBER,
        p_action VARCHAR2, p_comments VARCHAR2 DEFAULT NULL) IS
        l_request leave_request%ROWTYPE;
        l_step leave_app_history%ROWTYPE;
        l_company NUMBER;
        l_action VARCHAR2(20) := UPPER(TRIM(p_action));
    BEGIN
        SAVEPOINT leave_action_start;
        check_actor(p_actor_id);
        IF l_action IS NULL OR l_action NOT IN ('APPROVE', 'REJECT', 'RECORD') THEN
            RAISE_APPLICATION_ERROR(-20810, 'Use APPROVE, REJECT, or RECORD.');
        END IF;
        IF LENGTHB(p_comments) > 300 THEN
            RAISE_APPLICATION_ERROR(-20811, 'Comments must fit within 300 bytes.');
        END IF;
        -- Serialize all candidates on their parent so only one decision wins.
        SELECT * INTO l_request FROM leave_request WHERE leave_id = p_leave_id FOR UPDATE;
        SELECT com_id INTO l_company FROM employees WHERE id = l_request.empid;
        IF p_company_id IS NULL OR l_company IS NULL OR l_company <> p_company_id THEN
            RAISE_APPLICATION_ERROR(-20805, 'Request does not belong to the selected company.');
        END IF;
        check_history(p_leave_id, p_company_id);
        SELECT * INTO l_step FROM leave_app_history
         WHERE leave_id = p_leave_id AND com_id = p_company_id
           AND approver_id = p_actor_id AND approval_status = 'PENDING' FOR UPDATE;
        IF l_action = 'RECORD' THEN
            IF l_step.approver_level <> 'LEAVE_RECORD'
               OR NVL(l_request.leave_status, '#') <> 'A'
               OR NVL(l_request.request_status, '#') <> 'A' THEN
                RAISE_APPLICATION_ERROR(-20813, 'HRD can record only after a final HOD, Plant Head, or MD approval.');
            END IF;
        ELSE
            IF l_step.approver_level = 'LEAVE_RECORD'
               OR NVL(l_request.leave_status, '#') <> 'F'
               OR NVL(l_request.request_status, '#') <> 'F'
               OR l_request.empid = p_actor_id THEN
                RAISE_APPLICATION_ERROR(-20814, 'This request is not available for your approval.');
            END IF;
        END IF;
        UPDATE leave_app_history
           SET approval_status = CASE l_action WHEN 'APPROVE' THEN 'APPROVED'
                                  WHEN 'REJECT' THEN 'REJECTED' ELSE 'RECORDED' END,
               approval_date = SYSDATE, comments = p_comments,
               upd_date = SYSDATE, upd_by = p_actor_id
         WHERE id = l_step.id AND approval_status = 'PENDING';
        IF SQL%ROWCOUNT <> 1 THEN
            RAISE_APPLICATION_ERROR(-20815, 'Approval history is inconsistent; no action was saved.');
        END IF;
        IF l_action = 'REJECT' THEN
            UPDATE leave_app_history
               SET approval_status = 'CANCELLED', upd_date = SYSDATE, upd_by = p_actor_id
             WHERE leave_id = p_leave_id AND approval_status IN ('PENDING', 'WAITING');
        ELSIF l_action = 'APPROVE' AND l_step.approver_level = 'RP' THEN
            UPDATE leave_app_history
               SET approval_status = 'PENDING', upd_date = SYSDATE, upd_by = p_actor_id
             WHERE leave_id = p_leave_id AND approval_status = 'WAITING'
               AND approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR');
            IF SQL%ROWCOUNT < 1 THEN
                RAISE_APPLICATION_ERROR(-20816, 'An eligible final approver is required after RP recommendation.');
            END IF;
        ELSIF l_action = 'APPROVE' THEN
            UPDATE leave_app_history
               SET approval_status = 'CANCELLED', upd_date = SYSDATE, upd_by = p_actor_id
             WHERE leave_id = p_leave_id AND approval_status = 'PENDING'
               AND approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR');
            UPDATE leave_app_history
               SET approval_status = 'PENDING', upd_date = SYSDATE, upd_by = p_actor_id
             WHERE leave_id = p_leave_id AND approver_level = 'LEAVE_RECORD'
               AND approval_status = 'WAITING';
            IF SQL%ROWCOUNT <> 1 THEN
                RAISE_APPLICATION_ERROR(-20816, 'Exactly one HRD recording step is required.');
            END IF;
        END IF;
        UPDATE leave_request
           SET leave_status = CASE WHEN l_action = 'REJECT' THEN 'R'
                                   WHEN l_action = 'RECORD' OR l_step.approver_level <> 'RP'
                                   THEN 'A' ELSE 'F' END,
               request_status = CASE WHEN l_action = 'REJECT' THEN 'F'
                                     WHEN l_action = 'RECORD' OR l_step.approver_level <> 'RP'
                                     THEN 'A' ELSE 'F' END,
               upd_date = SYSDATE, upd_by = p_actor_id
         WHERE leave_id = p_leave_id;
        check_history(p_leave_id, l_company);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK TO leave_action_start;
            RAISE_APPLICATION_ERROR(-20817, 'No pending action is assigned to you for this request and company.');
        WHEN TOO_MANY_ROWS THEN
            ROLLBACK TO leave_action_start;
            RAISE_APPLICATION_ERROR(-20818, 'Duplicate pending assignments for one actor require administrator review.');
        WHEN OTHERS THEN
            ROLLBACK TO leave_action_start;
            RAISE;
    END;
END pkg_leave_approval;
/
