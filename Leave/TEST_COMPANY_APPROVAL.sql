-- Run only in a TEST HRMS database after INSTALL_COMPANY_APPROVAL.sql.
-- Uses existing role/RP/HOD assignments and creates temporary leave requests.
-- Temporary RP/HOD assignment changes and all request/history DML roll back.
-- Employee records and company role assignments are not changed.
-- Sequence numbers are consumed. Use a clean session, with no unsaved work.
SET SERVEROUTPUT ON
SET VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
ACCEPT test_company_id NUMBER PROMPT 'Test company ID: '
ACCEPT both_employee_id NUMBER PROMPT 'Employee with distinct RP and HOD (0 to skip): '
ACCEPT no_rp_employee_id NUMBER PROMPT 'Employee with HOD but no RP (0 to skip): '
ACCEPT no_hod_employee_id NUMBER PROMPT 'Employee with RP but no HOD (0 to skip): '
ACCEPT neither_employee_id NUMBER PROMPT 'Employee with neither RP nor HOD (0 to skip): '

DECLARE
    l_company NUMBER := &test_company_id;
    l_plant NUMBER;
    l_md NUMBER;
    l_hrd NUMBER;
    l_type NUMBER;
    l_hod_fixture NUMBER;
    l_cases NUMBER := 0;
    l_skipped NUMBER := 0;

    PROCEDURE assert_true(p_ok BOOLEAN, p_message VARCHAR2) IS
    BEGIN
        IF p_ok IS NULL OR NOT p_ok THEN
            RAISE_APPLICATION_ERROR(-20990, 'FAIL: ' || p_message);
        END IF;
    END;

    PROCEDURE assert_request(p_id NUMBER, p_status VARCHAR2, p_stage VARCHAR2) IS
        l_status VARCHAR2(10);
        l_stage VARCHAR2(1);
    BEGIN
        SELECT leave_status, request_status INTO l_status, l_stage
          FROM leave_request WHERE leave_id = p_id;
        assert_true(l_status = p_status AND l_stage = p_stage, 'Request stage ' || p_status);
    END;

    PROCEDURE expect_submit_error(p_id NUMBER, p_company NUMBER, p_actor NUMBER, p_code NUMBER) IS
    BEGIN
        pkg_leave_approval.submit_request(p_id, p_company, p_actor);
        RAISE_APPLICATION_ERROR(-20991, 'Forward unexpectedly succeeded.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE <> p_code THEN RAISE; END IF;
    END;

    PROCEDURE expect_action_error(p_id NUMBER, p_company NUMBER, p_actor NUMBER,
                                  p_action VARCHAR2, p_code NUMBER, p_other NUMBER DEFAULT NULL) IS
    BEGIN
        pkg_leave_approval.take_action(p_id, p_company, p_actor, p_action, 'Test');
        RAISE_APPLICATION_ERROR(-20992, 'Action unexpectedly succeeded: ' || p_action);
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE <> p_code AND (p_other IS NULL OR SQLCODE <> p_other) THEN RAISE; END IF;
    END;

    PROCEDURE run_case(p_empid NUMBER, p_kind VARCHAR2) IS
        l_leave NUMBER;
        l_rp NUMBER;
        l_hod NUMBER;
        l_count NUMBER;
        l_expected NUMBER := 3; -- Plant Head, MD, HRD
        l_first_role VARCHAR2(50);
        l_first_actor NUMBER;
    BEGIN
        SAVEPOINT route_case_start;
        IF NVL(p_empid, 0) = 0 THEN
            DBMS_OUTPUT.PUT_LINE('SKIP ' || p_kind || ': no fixture supplied.');
            l_skipped := l_skipped + 1;
            RETURN;
        END IF;
        SELECT COUNT(*) INTO l_count FROM employees
         WHERE id = p_empid AND status = 1 AND com_id = l_company;
        assert_true(l_count = 1 AND p_empid <> l_md, p_kind || ': active applicant in company, other than MD');
        IF p_kind = 'PLANT' THEN
            l_expected := 2;
        ELSE
            SELECT MIN(rep_person_id), COUNT(*) INTO l_rp, l_count FROM emp_rp
             WHERE emp_id = p_empid AND UPPER(TRIM(status)) IN ('ACTIVE', '1', 'Y')
               AND rep_person_id IS NOT NULL;
            assert_true(l_count <= 1, 'RP fixture has at most one active mapping');
            SELECT MIN(h.hod_id), COUNT(*) INTO l_hod, l_count FROM hod h
              JOIN employees e ON e.id = h.hod_id
             WHERE h.dept_id = (SELECT dept_id FROM employees WHERE id = p_empid)
               AND e.com_id = l_company AND UPPER(TRIM(h.status)) = 'ACTIVE';
            assert_true(l_count <= 1, 'HOD fixture has at most one mapping in company');
            IF p_kind = 'HOD' THEN
                assert_true(l_hod = p_empid AND p_empid <> l_plant, 'Distinct HOD applies for own leave');
                l_rp := NULL;
                l_hod := NULL;
            ELSE
                assert_true(p_empid <> l_plant, 'Ordinary fixture is not Plant Head');
                assert_true((p_kind IN ('FULL', 'NO_HOD') AND l_rp IS NOT NULL)
                         OR (p_kind IN ('NO_RP', 'NEITHER') AND l_rp IS NULL), p_kind || ': expected RP setup');
                assert_true((p_kind IN ('FULL', 'NO_RP') AND l_hod IS NOT NULL)
                         OR (p_kind IN ('NO_HOD', 'NEITHER') AND l_hod IS NULL), p_kind || ': expected HOD setup');
                -- Distinct fixtures ensure each requested approval stage is exercised.
                IF l_rp IS NOT NULL THEN
                    assert_true(l_rp NOT IN (p_empid, l_plant, l_md)
                                AND (l_hod IS NULL OR l_rp <> l_hod), 'Use a distinct RP fixture');
                    l_expected := l_expected + 1;
                END IF;
                IF l_hod IS NOT NULL THEN
                    assert_true(l_hod NOT IN (p_empid, l_plant, l_md), 'Use a distinct HOD fixture');
                    l_expected := l_expected + 1;
                END IF;
            END IF;
        END IF;
        INSERT INTO leave_request
            (empid, leave_type, l_start_date, l_end_date, proposed_days,
             leave_purpose, leave_address, ent_by)
        VALUES (p_empid, TO_CHAR(l_type), DATE '2099-01-01', DATE '2099-01-01', 1,
                'ROLLBACK TEST ' || p_kind, 'Test address', p_empid)
        RETURNING leave_id INTO l_leave;
        SELECT COUNT(*) INTO l_count FROM leave_app_history WHERE leave_id = l_leave;
        assert_true(l_count = 0, 'Saving a draft creates no approval history');
        expect_submit_error(l_leave, NULL, p_empid, -20805);
        expect_submit_error(l_leave, l_company + 1, p_empid, -20805);
        pkg_leave_approval.submit_request(l_leave, l_company, p_empid);
        assert_request(l_leave, 'F', 'F');
        expect_submit_error(l_leave, l_company, p_empid, -20807);
        SELECT COUNT(*) INTO l_count FROM leave_app_history WHERE leave_id = l_leave;
        assert_true(l_count = l_expected, p_kind || ': exact route size, no duplicate submit rows');
        SELECT COUNT(*) INTO l_count FROM leave_app_history
         WHERE leave_id = l_leave AND approver_level = 'RP' AND approver_id = l_rp;
        assert_true(l_count = CASE WHEN l_rp IS NULL THEN 0 ELSE 1 END, 'Expected RP step');
        SELECT COUNT(*) INTO l_count FROM leave_app_history
         WHERE leave_id = l_leave AND approver_level = 'HOD' AND approver_id = l_hod;
        assert_true(l_count = CASE WHEN l_hod IS NULL THEN 0 ELSE 1 END, 'Expected HOD step');
        SELECT approver_level, approver_id INTO l_first_role, l_first_actor
          FROM leave_app_history WHERE leave_id = l_leave AND approval_status = 'PENDING';
        expect_action_error(l_leave, l_company, l_hrd, 'RECORD', -20817, -20813);
        expect_action_error(l_leave, l_company + 1, l_first_actor, 'APPROVE', -20805);
        expect_action_error(l_leave, l_company, p_empid, 'APPROVE', -20817);
        expect_action_error(l_leave, l_company, l_first_actor, NULL, -20810);
        IF l_first_role <> 'MANAGING_DIRECTOR' THEN
            expect_action_error(l_leave, l_company, l_md, 'APPROVE', -20817);
        END IF;
        SAVEPOINT route_ready;
        FOR s IN (SELECT * FROM v_leave_approval_steps
                   WHERE leave_id = l_leave AND step_no < 50 ORDER BY step_no) LOOP
            SELECT COUNT(*) INTO l_count FROM leave_app_history
             WHERE id = s.id AND approval_status = 'PENDING';
            assert_true(l_count = 1, 'Only the next stage is actionable: ' || s.approver_level);
            IF s.approver_level = 'HOD' THEN
                SAVEPOINT before_hod_status_test;
                UPDATE hod SET status = 'INACTIVE'
                 WHERE hod_id = s.approver_id
                   AND dept_id = (SELECT dept_id FROM employees WHERE id = p_empid)
                   AND UPPER(TRIM(status)) = 'ACTIVE';
                assert_true(SQL%ROWCOUNT = 1, 'Temporarily deactivate the assigned HOD');
                expect_action_error(l_leave, l_company, s.approver_id, 'APPROVE', -20812);
                SELECT COUNT(*) INTO l_count FROM leave_app_history
                 WHERE id = s.id AND approval_status = 'PENDING';
                assert_true(l_count = 1, 'Inactive HOD cannot advance the saved pending step');
                assert_request(l_leave, 'F', 'F');
                ROLLBACK TO before_hod_status_test;
            END IF;
            pkg_leave_approval.take_action(l_leave, l_company, s.approver_id, 'APPROVE', 'Test approval');
            SELECT COUNT(*) INTO l_count FROM leave_app_history
             WHERE id = s.id AND approval_status = 'APPROVED'
               AND approval_date IS NOT NULL AND upd_by = s.approver_id;
            assert_true(l_count = 1, 'Completed stage retains actor and date');
            IF s.approver_level = 'MANAGING_DIRECTOR' THEN
                assert_request(l_leave, 'A', 'A');
            ELSE
                assert_request(l_leave, 'F', 'F');
            END IF;
            expect_action_error(l_leave, l_company, s.approver_id, 'APPROVE', -20817, -20814);
        END LOOP;
        pkg_leave_approval.take_action(l_leave, l_company, l_hrd, 'RECORD', 'Test HRD record');
        assert_request(l_leave, 'A', 'A');
        SELECT COUNT(*) INTO l_count FROM leave_app_history
         WHERE leave_id = l_leave AND approver_level = 'LEAVE_RECORD'
           AND approval_status = 'RECORDED' AND approval_date IS NOT NULL AND upd_by = l_hrd;
        assert_true(l_count = 1, 'HRD recording retains actor and date');
        expect_action_error(l_leave, l_company, l_hrd, 'RECORD', -20817);

        -- Reject at every approval stage, replaying earlier approvals each time.
        FOR target IN (SELECT * FROM v_leave_approval_steps
                        WHERE leave_id = l_leave AND step_no < 50 ORDER BY step_no) LOOP
            ROLLBACK TO route_ready;
            FOR earlier IN (SELECT * FROM v_leave_approval_steps
                             WHERE leave_id = l_leave AND step_no < target.step_no ORDER BY step_no) LOOP
                pkg_leave_approval.take_action(l_leave, l_company, earlier.approver_id, 'APPROVE', 'Before rejection');
            END LOOP;
            pkg_leave_approval.take_action(l_leave, l_company, target.approver_id, 'REJECT', 'Test rejection');
            assert_request(l_leave, 'R', 'F');
            SELECT COUNT(*) INTO l_count FROM leave_app_history
             WHERE leave_id = l_leave AND approval_status IN ('PENDING', 'WAITING');
            assert_true(l_count = 0, 'Rejection cancels every remaining step');
            expect_action_error(l_leave, l_company, l_hrd, 'RECORD', -20817);
        END LOOP;
        ROLLBACK TO route_case_start;
        l_cases := l_cases + 1;
        DBMS_OUTPUT.PUT_LINE('PASS ' || p_kind || ': routing, ordered approvals, final MD, HRD, rejection at each stage.');
    EXCEPTION WHEN OTHERS THEN
        ROLLBACK TO route_case_start;
        RAISE;
    END;

    PROCEDURE run_inactive_hod_case(p_empid NUMBER, p_kind VARCHAR2) IS
    BEGIN
        SAVEPOINT inactive_hod_fixture;
        IF NVL(p_empid, 0) = 0 THEN
            DBMS_OUTPUT.PUT_LINE('SKIP inactive HOD / ' || p_kind || ': no fixture supplied.');
            l_skipped := l_skipped + 1;
            RETURN;
        END IF;
        UPDATE hod SET status = 'INACTIVE'
         WHERE dept_id = (SELECT dept_id FROM employees WHERE id = p_empid)
           AND hod_id IN (SELECT id FROM employees WHERE com_id = l_company)
           AND UPPER(TRIM(status)) = 'ACTIVE';
        assert_true(SQL%ROWCOUNT = 1, 'One active HOD temporarily deactivated for new request');
        DBMS_OUTPUT.PUT_LINE('Testing new request with an inactive HOD assignment: ' || p_kind);
        run_case(p_empid, p_kind);
        ROLLBACK TO inactive_hod_fixture;
    EXCEPTION WHEN OTHERS THEN
        ROLLBACK TO inactive_hod_fixture;
        RAISE;
    END;

    PROCEDURE run_shared_approver_case(p_empid NUMBER, p_kind VARCHAR2) IS
        l_original_rp NUMBER;
        l_original_hod NUMBER;
        l_rp NUMBER;
        l_hod NUMBER;
        l_shared NUMBER;
        l_leave NUMBER;
        l_count NUMBER;
        l_people NUMBER;
        l_current_actor NUMBER;
        l_expected VARCHAR2(200);
        l_actual VARCHAR2(200);
        l_duplicate_role VARCHAR2(50);
    BEGIN
        SAVEPOINT shared_approver_fixture;
        IF NVL(p_empid, 0) = 0 THEN
            DBMS_OUTPUT.PUT_LINE('SKIP shared approver / ' || p_kind || ': no FULL fixture supplied.');
            l_skipped := l_skipped + 1;
            RETURN;
        END IF;
        -- Reuse the FULL fixture, then restore these assignments by rollback.
        SELECT rep_person_id INTO l_original_rp FROM emp_rp
         WHERE emp_id = p_empid AND UPPER(TRIM(status)) IN ('ACTIVE', '1', 'Y')
           AND rep_person_id IS NOT NULL;
        SELECT h.hod_id INTO l_original_hod FROM hod h
          JOIN employees e ON e.id = h.hod_id
         WHERE h.dept_id = (SELECT dept_id FROM employees WHERE id = p_empid)
           AND e.com_id = l_company AND UPPER(TRIM(h.status)) = 'ACTIVE';
        l_rp := l_original_rp;
        l_hod := l_original_hod;
        IF p_kind = 'RP_HOD' THEN
            l_hod := l_rp;
            l_shared := l_rp;
            l_expected := 'HOD,PLANT_HEAD,MANAGING_DIRECTOR,LEAVE_RECORD';
            l_duplicate_role := 'RP';
        ELSIF p_kind = 'HOD_PLANT' THEN
            l_hod := l_plant;
            l_shared := l_plant;
            l_expected := 'RP,PLANT_HEAD,MANAGING_DIRECTOR,LEAVE_RECORD';
            l_duplicate_role := 'HOD';
        ELSIF p_kind = 'RP_PLANT' THEN
            l_rp := l_plant;
            l_shared := l_plant;
            l_expected := 'HOD,PLANT_HEAD,MANAGING_DIRECTOR,LEAVE_RECORD';
            l_duplicate_role := 'RP';
        ELSIF p_kind = 'ALL_THREE' THEN
            l_rp := l_plant;
            l_hod := l_plant;
            l_shared := l_plant;
            l_expected := 'PLANT_HEAD,MANAGING_DIRECTOR,LEAVE_RECORD';
            l_duplicate_role := 'RP';
        ELSE
            RAISE_APPLICATION_ERROR(-20993, 'Unknown shared approver test case.');
        END IF;
        UPDATE emp_rp SET rep_person_id = l_rp
         WHERE emp_id = p_empid AND UPPER(TRIM(status)) IN ('ACTIVE', '1', 'Y')
           AND rep_person_id IS NOT NULL;
        assert_true(SQL%ROWCOUNT = 1, 'One temporary RP assignment');
        UPDATE hod SET hod_id = l_hod
         WHERE hod_id = l_original_hod AND UPPER(TRIM(status)) = 'ACTIVE'
           AND dept_id = (SELECT dept_id FROM employees WHERE id = p_empid);
        assert_true(SQL%ROWCOUNT = 1, 'One temporary HOD assignment');
        INSERT INTO leave_request
            (empid, leave_type, l_start_date, l_end_date, proposed_days,
             leave_purpose, leave_address, ent_by)
        VALUES (p_empid, TO_CHAR(l_type), DATE '2099-01-01', DATE '2099-01-01', 1,
                'ROLLBACK SHARED TEST ' || p_kind, 'Test address', p_empid)
        RETURNING leave_id INTO l_leave;
        pkg_leave_approval.submit_request(l_leave, l_company, p_empid);
        SELECT LISTAGG(approver_level, ',') WITHIN GROUP (ORDER BY step_no)
          INTO l_actual FROM v_leave_approval_steps WHERE leave_id = l_leave;
        assert_true(l_actual = l_expected, p_kind || ': exact combined route and order');
        SELECT COUNT(*), COUNT(DISTINCT approver_id) INTO l_count, l_people
          FROM leave_app_history WHERE leave_id = l_leave AND approver_level <> 'LEAVE_RECORD';
        assert_true(l_count = l_people, 'Every employee has only one approval step');
        SELECT COUNT(*) INTO l_count FROM leave_app_history
         WHERE leave_id = l_leave AND approver_id = l_shared AND approver_level <> 'LEAVE_RECORD';
        assert_true(l_count = 1, 'Shared employee is assigned once');

        -- A corrupted old/manual route must not make someone approve twice.
        SAVEPOINT shared_route_ready;
        SELECT approver_id INTO l_current_actor FROM leave_app_history
         WHERE leave_id = l_leave AND approval_status = 'PENDING';
        INSERT INTO leave_app_history
            (leave_id, approver_level, approver_id, approval_status, com_id, ent_by)
        VALUES (l_leave, l_duplicate_role, l_shared, 'WAITING', l_company, p_empid);
        expect_action_error(l_leave, l_company, l_current_actor, 'APPROVE', -20820);
        assert_request(l_leave, 'F', 'F');
        ROLLBACK TO shared_route_ready;

        FOR s IN (SELECT * FROM v_leave_approval_steps
                   WHERE leave_id = l_leave AND step_no < 50 ORDER BY step_no) LOOP
            SELECT COUNT(*) INTO l_count FROM leave_app_history
             WHERE id = s.id AND approval_status = 'PENDING';
            assert_true(l_count = 1, 'Next different approver is activated');
            pkg_leave_approval.take_action(l_leave, l_company, s.approver_id, 'APPROVE', 'Shared-role test');
            SELECT COUNT(*) INTO l_count FROM leave_app_history
             WHERE leave_id = l_leave AND approver_id = s.approver_id
               AND approver_level <> 'LEAVE_RECORD' AND approval_status = 'APPROVED';
            assert_true(l_count = 1, 'One completed approval per employee');
            IF s.approver_level = 'MANAGING_DIRECTOR' THEN
                assert_request(l_leave, 'A', 'A');
            ELSE
                assert_request(l_leave, 'F', 'F');
            END IF;
            expect_action_error(l_leave, l_company, s.approver_id, 'APPROVE', -20817, -20814);
        END LOOP;
        pkg_leave_approval.take_action(l_leave, l_company, l_hrd, 'RECORD', 'Shared-role HRD record');
        assert_request(l_leave, 'A', 'A');
        ROLLBACK TO shared_approver_fixture;
        l_cases := l_cases + 1;
        DBMS_OUTPUT.PUT_LINE('PASS shared ' || p_kind || ': one approval per employee, next approver, MD then HRD.');
    EXCEPTION WHEN OTHERS THEN
        ROLLBACK TO shared_approver_fixture;
        RAISE;
    END;
BEGIN
    SAVEPOINT company_leave_test_start;
    SELECT id INTO l_plant FROM v_leave_roles
     WHERE company_id = l_company AND UPPER(TRIM(role_code)) = 'PLANT_HEAD' AND UPPER(TRIM(active_yn)) = 'Y';
    SELECT id INTO l_md FROM v_leave_roles
     WHERE company_id = l_company AND UPPER(TRIM(role_code)) = 'MANAGING_DIRECTOR' AND UPPER(TRIM(active_yn)) = 'Y';
    SELECT id INTO l_hrd FROM v_leave_roles
     WHERE company_id = l_company AND UPPER(TRIM(role_code)) = 'LEAVE_RECORD' AND UPPER(TRIM(active_yn)) = 'Y';
    assert_true(l_plant <> l_md, 'Test company has distinct Plant Head and MD');
    SELECT MIN(lt_id) INTO l_type FROM leave_types
     WHERE active_flag = 'Y' AND (com_id = l_company OR com_id IS NULL);
    assert_true(l_type IS NOT NULL, 'Active leave type for test fixtures');
    run_case(&both_employee_id, 'FULL');
    run_case(&no_rp_employee_id, 'NO_RP');
    run_case(&no_hod_employee_id, 'NO_HOD');
    run_case(&neither_employee_id, 'NEITHER');
    run_inactive_hod_case(&both_employee_id, 'NO_HOD');
    run_inactive_hod_case(&no_rp_employee_id, 'NEITHER');
    run_shared_approver_case(&both_employee_id, 'RP_HOD');
    run_shared_approver_case(&both_employee_id, 'HOD_PLANT');
    run_shared_approver_case(&both_employee_id, 'RP_PLANT');
    run_shared_approver_case(&both_employee_id, 'ALL_THREE');
    run_case(l_plant, 'PLANT');
    SELECT MIN(h.hod_id) INTO l_hod_fixture FROM hod h JOIN employees e ON e.id = h.hod_id
     WHERE e.com_id = l_company AND e.dept_id = h.dept_id AND e.status = 1
       AND UPPER(TRIM(h.status)) = 'ACTIVE'
       AND h.hod_id NOT IN (l_plant, l_md);
    run_case(l_hod_fixture, 'HOD');
    ROLLBACK TO company_leave_test_start;
    DBMS_OUTPUT.PUT_LINE('Completed cases: ' || l_cases || '; skipped cases: ' || l_skipped || '.');
    DBMS_OUTPUT.PUT_LINE('All test request/history changes rolled back. Skipped cases are NOT verified.');
EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO company_leave_test_start;
    RAISE;
END;
/

UNDEFINE test_company_id
UNDEFINE both_employee_id
UNDEFINE no_rp_employee_id
UNDEFINE no_hod_employee_id
UNDEFINE neither_employee_id
WHENEVER SQLERROR CONTINUE NONE
