-- V_LEAVE_ROLES.ID, EMP_RP identifiers and HOD.HOD_ID are EMPLOYEES.ID.
CREATE OR REPLACE PACKAGE HRMS.pkg_leave_approval AUTHID DEFINER AS
    PROCEDURE submit_request(
        p_leave_id NUMBER, p_company_id NUMBER, p_actor_id NUMBER);
    PROCEDURE take_action(
        p_leave_id NUMBER, p_company_id NUMBER, p_actor_id NUMBER,
        p_action VARCHAR2, p_comments VARCHAR2 DEFAULT NULL);
END pkg_leave_approval;
/

CREATE OR REPLACE PACKAGE BODY HRMS.pkg_leave_approval AS
    FUNCTION role_employee(p_company_id NUMBER, p_role VARCHAR2) RETURN NUMBER IS
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
            RAISE_APPLICATION_ERROR(-20802, 'Missing active company leave role: ' || p_role);
        WHEN TOO_MANY_ROWS THEN
            RAISE_APPLICATION_ERROR(-20803, 'Multiple active employees for company leave role: ' || p_role);
    END;

    FUNCTION reporting_person(p_empid NUMBER) RETURN NUMBER IS
        l_id NUMBER;
    BEGIN
        -- The export defaults to ACTIVE; legacy leave code used 1.
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
        -- Only current ACTIVE assignments participate. HOD has no company
        -- column; scope through its assigned employee's company.
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

    PROCEDURE check_history(p_leave_id NUMBER, p_company_id NUMBER) IS
        l_rows NUMBER;
        l_roles NUMBER;
        l_md NUMBER;
        l_hrd NUMBER;
        l_bad NUMBER;
        l_approval_rows NUMBER;
        l_approval_people NUMBER;
    BEGIN
        SELECT COUNT(*), COUNT(DISTINCT approver_level),
               COUNT(CASE WHEN approver_level = 'MANAGING_DIRECTOR' THEN 1 END),
               COUNT(CASE WHEN approver_level = 'LEAVE_RECORD' THEN 1 END),
               COUNT(CASE WHEN step_no IS NULL OR com_id IS NULL OR com_id <> p_company_id
                           OR approver_id IS NULL OR approval_status IS NULL
                           OR approval_status NOT IN
                              ('WAITING', 'PENDING', 'APPROVED', 'REJECTED', 'CANCELLED', 'RECORDED')
                          THEN 1 END),
               COUNT(CASE WHEN approver_level <> 'LEAVE_RECORD' THEN 1 END),
               COUNT(DISTINCT CASE WHEN approver_level <> 'LEAVE_RECORD' THEN approver_id END)
          INTO l_rows, l_roles, l_md, l_hrd, l_bad, l_approval_rows, l_approval_people
          FROM v_leave_approval_steps
         WHERE leave_id = p_leave_id;
        IF l_rows <> l_roles OR l_md <> 1 OR l_hrd <> 1 OR l_bad <> 0
           OR l_approval_rows <> l_approval_people THEN
            RAISE_APPLICATION_ERROR(-20820, 'Incomplete, duplicate, or legacy route requires administrator review.');
        END IF;
    END;

    PROCEDURE submit_request(
        p_leave_id NUMBER, p_company_id NUMBER, p_actor_id NUMBER) IS
        TYPE t_step IS RECORD (role_code VARCHAR2(50), employee_id NUMBER);
        TYPE t_route IS TABLE OF t_step INDEX BY PLS_INTEGER;
        l_route t_route;
        l_request leave_request%ROWTYPE;
        l_company NUMBER;
        l_count NUMBER;
        l_status VARCHAR2(50) := 'PENDING';
    BEGIN
        SAVEPOINT leave_submit_start;
        check_actor(p_actor_id);
        SELECT * INTO l_request FROM leave_request WHERE leave_id = p_leave_id FOR UPDATE;
        SELECT com_id INTO l_company FROM employees WHERE id = l_request.empid;
        IF p_company_id IS NULL OR l_company IS NULL OR l_company <> p_company_id THEN
            RAISE_APPLICATION_ERROR(-20805, 'Request does not belong to the selected company.');
        END IF;
        IF l_request.empid <> p_actor_id THEN
            RAISE_APPLICATION_ERROR(-20806, 'Only the applicant can forward this request.');
        END IF;
        IF NVL(l_request.request_status, '#') <> 'D'
           OR NVL(l_request.leave_status, '#') NOT IN ('P', 'D') THEN
            RAISE_APPLICATION_ERROR(-20807, 'Only a draft request can be forwarded.');
        END IF;
        IF l_request.l_start_date IS NULL OR l_request.l_end_date IS NULL
           OR TRUNC(l_request.l_end_date) < TRUNC(l_request.l_start_date)
           OR l_request.proposed_days IS NULL OR l_request.proposed_days <= 0 THEN
            RAISE_APPLICATION_ERROR(-20826, 'Valid leave dates and positive proposed days are required.');
        END IF;
        SELECT COUNT(*) INTO l_count FROM leave_app_history WHERE leave_id = p_leave_id;
        IF l_count <> 0 THEN
            RAISE_APPLICATION_ERROR(-20808, 'Existing approval history requires review before forwarding.');
        END IF;
        l_route(1).role_code := 'RP';
        l_route(2).role_code := 'HOD';
        l_route(3).role_code := 'PLANT_HEAD';
        l_route(4).role_code := 'MANAGING_DIRECTOR';
        l_route(5).role_code := 'LEAVE_RECORD';
        FOR i IN 3 .. 5 LOOP
            l_route(i).employee_id := role_employee(l_company, l_route(i).role_code);
            check_actor(l_route(i).employee_id);
        END LOOP;
        IF l_request.empid = l_route(4).employee_id THEN
            RAISE_APPLICATION_ERROR(-20809, 'MD leave needs a separately configured higher approver; self-approval is not allowed.');
        END IF;
        -- Heads begin above their own role, never with their subordinates.
        IF l_request.empid <> l_route(3).employee_id THEN
            l_route(2).employee_id := department_head(l_request.empid, l_company);
            IF l_route(2).employee_id IS NOT NULL THEN
                check_local_approver(l_route(2).employee_id, l_company);
            END IF;
            IF l_route(2).employee_id IS NULL OR l_route(2).employee_id <> l_request.empid THEN
                l_route(1).employee_id := reporting_person(l_request.empid);
                IF l_route(1).employee_id IS NOT NULL THEN
                    check_local_approver(l_route(1).employee_id, l_company);
                END IF;
            END IF;
        END IF;
        -- Omit self-approval and retain one approval at the highest assigned
        -- role when a person holds several roles. HRD recording stays separate.
        -- RP=HOD keeps HOD; HOD=PLANT_HEAD or RP=PLANT_HEAD keeps PLANT_HEAD.
        -- If all three are the same person, that person approves once as
        -- PLANT_HEAD, then the next pending approval belongs to MD.
        FOR i IN 1 .. 4 LOOP
            IF l_route(i).employee_id = l_request.empid THEN
                l_route(i).employee_id := NULL;
            END IF;
            FOR j IN i + 1 .. 4 LOOP
                IF l_route(i).employee_id = l_route(j).employee_id THEN
                    l_route(i).employee_id := NULL;
                END IF;
            END LOOP;
        END LOOP;
        FOR i IN 1 .. 5 LOOP
            IF l_route(i).employee_id IS NOT NULL THEN
                INSERT INTO leave_app_history
                    (leave_id, approver_level, approver_id, approval_status,
                     com_id, comments, ent_date, ent_by)
                VALUES
                    (p_leave_id, l_route(i).role_code, l_route(i).employee_id,
                     l_status,
                     l_company, 'Waiting for ' || l_route(i).role_code, SYSDATE, p_actor_id);
                l_status := 'WAITING';
            END IF;
        END LOOP;
        check_history(p_leave_id, l_company);
        UPDATE leave_request
           SET leave_status = 'F', request_status = 'F', upd_date = SYSDATE, upd_by = p_actor_id
         WHERE leave_id = p_leave_id;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO leave_submit_start;
            RAISE;
    END;

    PROCEDURE take_action(
        p_leave_id NUMBER, p_company_id NUMBER, p_actor_id NUMBER,
        p_action VARCHAR2, p_comments VARCHAR2 DEFAULT NULL) IS
        l_request leave_request%ROWTYPE;
        l_step leave_app_history%ROWTYPE;
        l_company NUMBER;
        l_current NUMBER;
        l_order NUMBER;
        l_next NUMBER;
        l_count NUMBER;
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
        -- The parent lock serializes all transitions, including repeated submits.
        SELECT * INTO l_request FROM leave_request WHERE leave_id = p_leave_id FOR UPDATE;
        SELECT com_id INTO l_company FROM employees WHERE id = l_request.empid;
        IF p_company_id IS NULL OR l_company IS NULL OR l_company <> p_company_id THEN
            RAISE_APPLICATION_ERROR(-20805, 'Request does not belong to the selected company.');
        END IF;
        check_history(p_leave_id, p_company_id);
        SELECT * INTO l_step FROM leave_app_history
         WHERE leave_id = p_leave_id AND com_id = p_company_id
           AND approval_status = 'PENDING' FOR UPDATE;
        IF l_step.approver_id <> p_actor_id THEN
            RAISE_APPLICATION_ERROR(-20817, 'The current step is assigned to another employee.');
        END IF;
        SELECT step_no INTO l_order FROM v_leave_approval_steps WHERE id = l_step.id;
        SELECT COUNT(*) INTO l_count FROM v_leave_approval_steps
         WHERE leave_id = p_leave_id
           AND ((step_no < l_order AND approval_status <> 'APPROVED')
             OR (step_no > l_order AND approval_status <> 'WAITING'));
        IF l_count <> 0 THEN
            RAISE_APPLICATION_ERROR(-20814, 'Approval steps must be completed in order.');
        END IF;
        IF l_step.approver_level = 'RP' THEN
            l_current := reporting_person(l_request.empid);
            check_local_approver(p_actor_id, p_company_id);
        ELSIF l_step.approver_level = 'HOD' THEN
            l_current := department_head(l_request.empid, p_company_id);
            check_local_approver(p_actor_id, p_company_id);
        ELSE
            l_current := role_employee(p_company_id, l_step.approver_level);
        END IF;
        IF l_current IS NULL OR l_current <> p_actor_id THEN
            RAISE_APPLICATION_ERROR(-20812, 'Assignment changed; administrator review is required.');
        END IF;
        IF l_action = 'RECORD' THEN
            IF l_step.approver_level <> 'LEAVE_RECORD'
               OR NVL(l_request.leave_status, '#') <> 'A'
               OR NVL(l_request.request_status, '#') <> 'A' THEN
                RAISE_APPLICATION_ERROR(-20813, 'HRD can record only after all approvals, including MD.');
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
         WHERE id = l_step.id AND leave_id = p_leave_id AND approval_status = 'PENDING';
        IF SQL%ROWCOUNT <> 1 THEN
            RAISE_APPLICATION_ERROR(-20815, 'Approval history is inconsistent; no action was saved.');
        END IF;
        IF l_action = 'REJECT' THEN
            UPDATE leave_app_history
               SET approval_status = 'CANCELLED', upd_date = SYSDATE, upd_by = p_actor_id
             WHERE leave_id = p_leave_id AND approval_status = 'WAITING';
        ELSIF l_action = 'APPROVE' THEN
            SELECT MIN(step_no) INTO l_next FROM v_leave_approval_steps
             WHERE leave_id = p_leave_id AND approval_status = 'WAITING';
            IF l_next IS NULL OR l_next <= l_order
               OR (l_step.approver_level = 'MANAGING_DIRECTOR' AND l_next <> 50)
               OR (l_step.approver_level <> 'MANAGING_DIRECTOR' AND l_next >= 50) THEN
                RAISE_APPLICATION_ERROR(-20816, 'Next approval or HRD step is missing or out of order.');
            END IF;
            UPDATE leave_app_history
               SET approval_status = 'PENDING', upd_date = SYSDATE, upd_by = p_actor_id
             WHERE leave_id = p_leave_id AND approval_status = 'WAITING'
               AND approver_level = CASE l_next WHEN 10 THEN 'RP' WHEN 20 THEN 'HOD'
                   WHEN 30 THEN 'PLANT_HEAD' WHEN 40 THEN 'MANAGING_DIRECTOR'
                   WHEN 50 THEN 'LEAVE_RECORD' END;
            IF SQL%ROWCOUNT <> 1 THEN
                RAISE_APPLICATION_ERROR(-20816, 'Exactly one next step is required.');
            END IF;
        END IF;
        UPDATE leave_request
           SET leave_status = CASE WHEN l_action = 'REJECT' THEN 'R'
                                   WHEN l_action = 'RECORD' OR l_step.approver_level = 'MANAGING_DIRECTOR'
                                   THEN 'A' ELSE 'F' END,
               request_status = CASE WHEN l_action = 'REJECT' THEN 'F'
                                     WHEN l_action = 'RECORD' OR l_step.approver_level = 'MANAGING_DIRECTOR'
                                     THEN 'A' ELSE 'F' END,
               upd_date = SYSDATE, upd_by = p_actor_id
         WHERE leave_id = p_leave_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK TO leave_action_start;
            RAISE_APPLICATION_ERROR(-20817, 'No current action exists for this request and company.');
        WHEN TOO_MANY_ROWS THEN
            ROLLBACK TO leave_action_start;
            RAISE_APPLICATION_ERROR(-20818, 'Duplicate pending steps require administrator review.');
        WHEN OTHERS THEN
            ROLLBACK TO leave_action_start;
            RAISE;
    END;
END pkg_leave_approval;
/
