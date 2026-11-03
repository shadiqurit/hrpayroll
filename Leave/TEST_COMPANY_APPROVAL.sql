-- Run only in a TEST HRMS database after INSTALL_COMPANY_APPROVAL.sql.
-- Clean session required. Requests/history/consumption and temporary allocations
-- and RP/HOD changes roll back. Tests verify posting inside final approval.
-- Sequence values are consumed. Company-role assignments and employees are not changed.
SET SERVEROUTPUT ON
SET VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
ACCEPT test_company_id NUMBER PROMPT 'Test company ID: '
ACCEPT test_employee_id NUMBER PROMPT 'Ordinary employee with distinct active RP and HOD: '

DECLARE
    l_company NUMBER := &test_company_id;
    l_employee NUMBER := &test_employee_id;
    l_rp NUMBER;
    l_hod NUMBER;
    l_plant NUMBER;
    l_md NUMBER;
    l_hrd NUMBER;
    l_type NUMBER;
    l_count NUMBER;
    l_leave NUMBER;
    l_allocation_id NUMBER;
    l_cases NUMBER := 0;

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
        assert_true(l_status = p_status AND l_stage = p_stage, 'Request state ' || p_status || '/' || p_stage);
    END;

    PROCEDURE expect_action_error(p_id NUMBER, p_company NUMBER, p_actor NUMBER,
                                  p_action VARCHAR2, p_code NUMBER) IS
    BEGIN
        pkg_leave_approval.take_action(p_id, p_company, p_actor, p_action, 'Negative test');
        RAISE_APPLICATION_ERROR(-20992, 'Action unexpectedly succeeded: ' || p_action);
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE <> p_code THEN RAISE; END IF;
    END;

    PROCEDURE expect_submit_error(p_id NUMBER, p_code NUMBER) IS
    BEGIN
        pkg_leave_approval.submit_request(p_id, l_company, l_employee);
        RAISE_APPLICATION_ERROR(-20991, 'Submit unexpectedly succeeded.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE <> p_code THEN RAISE; END IF;
    END;

    FUNCTION new_request(p_empid NUMBER) RETURN NUMBER IS
        l_id NUMBER;
    BEGIN
        INSERT INTO leave_request
            (empid, leave_type, l_start_date, l_end_date, proposed_days,
             leave_purpose, leave_address, ent_by)
        VALUES (p_empid, TO_CHAR(l_type), DATE '2099-01-01', DATE '2099-01-01', 1,
                'ROLLBACK ONE FINAL APPROVAL TEST', 'Test address', p_empid)
        RETURNING leave_id INTO l_id;
        RETURN l_id;
    END;

    PROCEDURE run_decision(p_empid NUMBER, p_winner_role VARCHAR2,
                           p_expected_roles VARCHAR2, p_expect_rp BOOLEAN,
                           p_reject BOOLEAN DEFAULT FALSE) IS
        l_id NUMBER;
        l_actor NUMBER;
        l_rp_actor NUMBER;
        l_count NUMBER;
        l_finals NUMBER;
        l_actual VARCHAR2(200);
        l_balance_before NUMBER;
    BEGIN
        SAVEPOINT decision_case;
        l_id := new_request(p_empid);
        SELECT COUNT(*) INTO l_count FROM leave_app_history WHERE leave_id = l_id;
        assert_true(l_count = 0, 'Draft has no history');
        pkg_leave_approval.submit_request(l_id, l_company, p_empid);
        assert_request(l_id, 'F', 'F');
        SELECT balance_days INTO l_balance_before FROM v_leave_year_balance
         WHERE empid = p_empid AND leave_type_id = l_type AND leave_year = 2099;
        SELECT COUNT(*) INTO l_count FROM leave_consumption WHERE leave_id = l_id;
        assert_true(l_count = 0, 'Submitting a request does not consume leave');
        SELECT LISTAGG(approver_level, ',') WITHIN GROUP (ORDER BY approver_level), COUNT(*)
          INTO l_actual, l_finals FROM leave_app_history
         WHERE leave_id = l_id AND approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR');
        assert_true(l_actual = p_expected_roles, 'Exact eligible final set: ' || p_expected_roles);
        SELECT approver_id INTO l_actor FROM leave_app_history
         WHERE leave_id = l_id AND approver_level = p_winner_role;
        SELECT COUNT(*), MAX(approver_id) INTO l_count, l_rp_actor
          FROM leave_app_history WHERE leave_id = l_id AND approver_level = 'RP';
        assert_true((p_expect_rp AND l_count = 1) OR (NOT p_expect_rp AND l_count = 0), 'Distinct RP requirement');
        expect_action_error(l_id, l_company + 1, l_actor, 'APPROVE', -20805);
        expect_action_error(l_id, l_company, p_empid, 'APPROVE', -20817);
        expect_action_error(l_id, l_company, l_hrd, 'RECORD', -20817);
        expect_action_error(l_id, l_company, l_actor, NULL, -20810);
        IF p_expect_rp THEN
            expect_action_error(l_id, l_company, l_actor, 'APPROVE', -20817);
            pkg_leave_approval.take_action(l_id, l_company, l_rp_actor, 'APPROVE', 'RP recommendation');
            assert_request(l_id, 'F', 'F');
            SELECT COUNT(*) INTO l_count FROM leave_consumption WHERE leave_id = l_id;
            assert_true(l_count = 0, 'RP recommendation does not consume leave');
            expect_action_error(l_id, l_company, l_rp_actor, 'APPROVE', -20817);
        END IF;
        SELECT COUNT(*) INTO l_count FROM leave_app_history
         WHERE leave_id = l_id AND approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR')
           AND approval_status = 'PENDING';
        assert_true(l_count = l_finals, 'All alternatives pending together');
        pkg_leave_approval.take_action(l_id, l_company, l_actor,
            CASE WHEN p_reject THEN 'REJECT' ELSE 'APPROVE' END, 'Final decision');
        IF p_reject THEN
            assert_request(l_id, 'R', 'F');
            SELECT COUNT(*) INTO l_count FROM leave_app_history
             WHERE leave_id = l_id AND approval_status IN ('PENDING', 'WAITING');
            assert_true(l_count = 0, 'Rejection closes every open step');
            SELECT COUNT(*) INTO l_count FROM leave_consumption WHERE leave_id = l_id;
            assert_true(l_count = 0, 'Rejection does not consume leave');
            expect_action_error(l_id, l_company, l_hrd, 'RECORD', -20817);
        ELSE
            assert_request(l_id, 'A', 'A');
            SELECT COUNT(*) INTO l_count FROM leave_consumption
             WHERE leave_id = l_id AND empid = p_empid AND leave_type_id = l_type
               AND consumed_days = 1 AND consum_year = 2099
               AND ent_by = l_actor AND com_id = l_company;
            assert_true(l_count = 1, 'Final approval posts the approved quantity once');
            SELECT COUNT(*) INTO l_count FROM v_leave_year_balance
             WHERE empid = p_empid AND leave_type_id = l_type AND leave_year = 2099
               AND balance_days = l_balance_before - 1;
            assert_true(l_count = 1, 'Balance decreases immediately after final approval');
            post_leave_consumption(l_id, l_company, l_actor);
            SELECT COUNT(*) INTO l_count FROM leave_consumption WHERE leave_id = l_id;
            assert_true(l_count = 1, 'Safe posting retry does not deduct twice');
            SELECT COUNT(*) INTO l_count FROM leave_app_history
             WHERE leave_id = l_id AND approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR')
               AND approval_status = 'APPROVED';
            assert_true(l_count = 1, 'Exactly one final approval');
            SELECT COUNT(*) INTO l_count FROM leave_app_history
             WHERE leave_id = l_id AND approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR')
               AND approval_status = 'CANCELLED';
            assert_true(l_count = l_finals - 1, 'Unused alternatives cancelled');
            FOR loser IN (SELECT approver_id FROM leave_app_history
                           WHERE leave_id = l_id AND approval_status = 'CANCELLED') LOOP
                expect_action_error(l_id, l_company, loser.approver_id, 'APPROVE', -20817);
            END LOOP;
            expect_action_error(l_id, l_company, l_hrd, 'APPROVE', -20814);
            pkg_leave_approval.take_action(l_id, l_company, l_hrd, 'RECORD', 'HRD record');
            assert_request(l_id, 'A', 'A');
            SELECT COUNT(*) INTO l_count FROM leave_app_history
             WHERE leave_id = l_id AND approver_level = 'LEAVE_RECORD'
               AND approval_status = 'RECORDED' AND approval_date IS NOT NULL AND upd_by = l_hrd;
            assert_true(l_count = 1, 'HRD recording is separate and audited');
            SELECT COUNT(*) INTO l_count FROM leave_consumption WHERE leave_id = l_id;
            assert_true(l_count = 1, 'HRD recording does not post again');
            expect_action_error(l_id, l_company, l_hrd, 'RECORD', -20817);
        END IF;
        expect_action_error(l_id, l_company, l_actor, 'APPROVE', -20817);
        ROLLBACK TO decision_case;
        l_cases := l_cases + 1;
        DBMS_OUTPUT.PUT_LINE('PASS ' || p_empid || ': ' || p_winner_role || CASE WHEN p_reject THEN ' rejects' ELSE ' approves' END);
    EXCEPTION WHEN OTHERS THEN
        ROLLBACK TO decision_case;
        RAISE;
    END;
BEGIN
    SAVEPOINT approval_test_start;
    SELECT id INTO l_plant FROM v_leave_roles
     WHERE company_id = l_company AND UPPER(TRIM(role_code)) = 'PLANT_HEAD' AND UPPER(TRIM(active_yn)) = 'Y';
    SELECT id INTO l_md FROM v_leave_roles
     WHERE company_id = l_company AND UPPER(TRIM(role_code)) = 'MANAGING_DIRECTOR' AND UPPER(TRIM(active_yn)) = 'Y';
    SELECT id INTO l_hrd FROM v_leave_roles
     WHERE company_id = l_company AND UPPER(TRIM(role_code)) = 'LEAVE_RECORD' AND UPPER(TRIM(active_yn)) = 'Y';
    SELECT rep_person_id INTO l_rp FROM emp_rp
     WHERE emp_id = l_employee AND UPPER(TRIM(status)) IN ('ACTIVE', '1', 'Y') AND rep_person_id IS NOT NULL;
    SELECT h.hod_id INTO l_hod FROM hod h JOIN employees e ON e.id = h.hod_id
     WHERE h.dept_id = (SELECT dept_id FROM employees WHERE id = l_employee)
       AND e.com_id = l_company AND UPPER(TRIM(h.status)) = 'ACTIVE';
    SELECT COUNT(*) INTO l_count FROM employees
     WHERE id IN (l_employee, l_rp, l_hod, l_plant, l_md, l_hrd) AND status = 1;
    assert_true(l_count = 6, 'Six distinct active applicant/RP/HOD/Plant Head/MD/HRD fixture people');
    SELECT COUNT(*) INTO l_count FROM employees
     WHERE id IN (l_employee, l_rp, l_hod, l_plant, l_md, l_hrd) AND com_id = l_company;
    assert_true(l_count = 6, 'All six fixture employees belong to the test company');
    SELECT COUNT(*) INTO l_count FROM hod WHERE hod_id = l_employee AND UPPER(TRIM(status)) = 'ACTIVE';
    assert_true(l_count = 0, 'Ordinary applicant is not a HOD');
    SELECT MIN(lt_id) INTO l_type FROM leave_types
     WHERE active_flag = 'Y' AND lt_id > 0 AND (com_id = l_company OR com_id IS NULL);
    assert_true(l_type IS NOT NULL, 'Active leave type');

    -- Each applicant gets 100 days of spare test balance, preserving any native
    -- 2099 usage in the fixture. All allocation changes roll back at the end.
    FOR person IN (SELECT id FROM employees WHERE id IN (l_employee, l_hod, l_plant)) LOOP
        SELECT COUNT(*) INTO l_count FROM leave_allocation
         WHERE empid = person.id AND leave_type_id = l_type AND allocation_year = 2099;
        IF l_count = 0 THEN
            SELECT LEAST(NVL(MIN(allocation_id), 0), 0) - 1 INTO l_allocation_id FROM leave_allocation;
            INSERT INTO leave_allocation (allocation_id, empid, leave_type_id,
                allocated_days, allocation_year, allocated_date, com_id)
            VALUES (l_allocation_id, person.id, l_type, 0, 2099, DATE '2099-01-01', l_company);
        END IF;
        UPDATE leave_allocation
           SET allocated_days = 100 + (SELECT NVL(SUM(c.consumed_days), 0)
                 FROM leave_consumption c WHERE c.empid = person.id
                   AND c.leave_type_id = l_type AND c.consum_year = 2099)
         WHERE empid = person.id AND leave_type_id = l_type AND allocation_year = 2099;
    END LOOP;

    run_decision(l_employee, 'HOD', 'HOD,PLANT_HEAD', TRUE);
    run_decision(l_employee, 'PLANT_HEAD', 'HOD,PLANT_HEAD', TRUE);
    run_decision(l_employee, 'HOD', 'HOD,PLANT_HEAD', TRUE, TRUE);
    run_decision(l_employee, 'PLANT_HEAD', 'HOD,PLANT_HEAD', TRUE, TRUE);
    run_decision(l_hod, 'PLANT_HEAD', 'MANAGING_DIRECTOR,PLANT_HEAD', FALSE);
    run_decision(l_hod, 'MANAGING_DIRECTOR', 'MANAGING_DIRECTOR,PLANT_HEAD', FALSE);
    run_decision(l_hod, 'PLANT_HEAD', 'MANAGING_DIRECTOR,PLANT_HEAD', FALSE, TRUE);
    run_decision(l_hod, 'MANAGING_DIRECTOR', 'MANAGING_DIRECTOR,PLANT_HEAD', FALSE, TRUE);
    run_decision(l_plant, 'MANAGING_DIRECTOR', 'MANAGING_DIRECTOR', FALSE);
    run_decision(l_plant, 'MANAGING_DIRECTOR', 'MANAGING_DIRECTOR', FALSE, TRUE);

    SAVEPOINT changed_mapping;
    UPDATE emp_rp SET status = 'INACTIVE' WHERE emp_id = l_employee AND UPPER(TRIM(status)) IN ('ACTIVE', '1', 'Y');
    run_decision(l_employee, 'HOD', 'HOD,PLANT_HEAD', FALSE);
    ROLLBACK TO changed_mapping;
    SAVEPOINT changed_mapping;
    UPDATE hod SET status = 'INACTIVE'
     WHERE hod_id = l_hod AND dept_id = (SELECT dept_id FROM employees WHERE id = l_employee)
       AND UPPER(TRIM(status)) = 'ACTIVE';
    run_decision(l_employee, 'PLANT_HEAD', 'PLANT_HEAD', TRUE);
    UPDATE emp_rp SET status = 'INACTIVE' WHERE emp_id = l_employee AND UPPER(TRIM(status)) IN ('ACTIVE', '1', 'Y');
    run_decision(l_employee, 'PLANT_HEAD', 'PLANT_HEAD', FALSE);
    ROLLBACK TO changed_mapping;

    SAVEPOINT changed_mapping;
    UPDATE emp_rp SET rep_person_id = l_hod WHERE emp_id = l_employee AND UPPER(TRIM(status)) IN ('ACTIVE', '1', 'Y');
    run_decision(l_employee, 'HOD', 'HOD,PLANT_HEAD', FALSE);
    run_decision(l_employee, 'PLANT_HEAD', 'HOD,PLANT_HEAD', FALSE);
    ROLLBACK TO changed_mapping;
    SAVEPOINT changed_mapping;
    UPDATE emp_rp SET rep_person_id = l_plant WHERE emp_id = l_employee AND UPPER(TRIM(status)) IN ('ACTIVE', '1', 'Y');
    run_decision(l_employee, 'PLANT_HEAD', 'HOD,PLANT_HEAD', FALSE);
    ROLLBACK TO changed_mapping;
    SAVEPOINT changed_mapping;
    UPDATE hod SET hod_id = l_plant
     WHERE hod_id = l_hod AND dept_id = (SELECT dept_id FROM employees WHERE id = l_employee)
       AND UPPER(TRIM(status)) = 'ACTIVE';
    run_decision(l_employee, 'PLANT_HEAD', 'PLANT_HEAD', TRUE);
    UPDATE emp_rp SET rep_person_id = l_plant WHERE emp_id = l_employee AND UPPER(TRIM(status)) IN ('ACTIVE', '1', 'Y');
    run_decision(l_employee, 'PLANT_HEAD', 'PLANT_HEAD', FALSE);
    ROLLBACK TO changed_mapping;

    SAVEPOINT negative_case;
    l_leave := new_request(l_employee);
    pkg_leave_approval.submit_request(l_leave, l_company, l_employee);
    expect_submit_error(l_leave, -20807);
    expect_action_error(l_leave, l_company, l_md, 'APPROVE', -20817);
    pkg_leave_approval.take_action(l_leave, l_company, l_rp, 'REJECT', 'RP rejects');
    assert_request(l_leave, 'R', 'F');
    SELECT COUNT(*) INTO l_count FROM leave_app_history WHERE leave_id = l_leave AND approval_status IN ('PENDING', 'WAITING');
    assert_true(l_count = 0, 'RP rejection cancels finals and HRD');
    ROLLBACK TO negative_case;

    SAVEPOINT negative_case;
    l_leave := new_request(l_employee);
    pkg_leave_approval.submit_request(l_leave, l_company, l_employee);
    INSERT INTO leave_app_history (leave_id, approver_level, approver_id, approval_status, com_id)
    VALUES (l_leave, 'MANAGING_DIRECTOR', l_md, 'WAITING', l_company);
    expect_action_error(l_leave, l_company, l_rp, 'APPROVE', -20820);
    assert_request(l_leave, 'F', 'F');
    ROLLBACK TO negative_case;

    SAVEPOINT negative_case;
    l_leave := new_request(l_employee);
    pkg_leave_approval.submit_request(l_leave, l_company, l_employee);
    UPDATE hod SET status = 'INACTIVE'
     WHERE hod_id = l_hod AND dept_id = (SELECT dept_id FROM employees WHERE id = l_employee)
       AND UPPER(TRIM(status)) = 'ACTIVE';
    expect_action_error(l_leave, l_company, l_rp, 'APPROVE', -20820);
    ROLLBACK TO negative_case;

    SAVEPOINT negative_case;
    l_leave := new_request(l_md);
    BEGIN
        pkg_leave_approval.submit_request(l_leave, l_company, l_md);
        RAISE_APPLICATION_ERROR(-20991, 'MD self-route unexpectedly succeeded.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE <> -20809 THEN RAISE; END IF;
    END;
    ROLLBACK TO negative_case;

    SAVEPOINT negative_case;
    l_leave := new_request(l_employee);
    pkg_leave_approval.submit_request(l_leave, l_company, l_employee);
    pkg_leave_approval.take_action(l_leave, l_company, l_rp, 'APPROVE', 'Recommend');
    UPDATE leave_allocation SET allocated_days = 0
     WHERE empid = l_employee AND leave_type_id = l_type AND allocation_year = 2099;
    expect_action_error(l_leave, l_company, l_hod, 'APPROVE', -20836);
    assert_request(l_leave, 'F', 'F');
    SELECT COUNT(*) INTO l_count FROM leave_app_history
     WHERE leave_id = l_leave AND approver_level = 'HOD' AND approval_status = 'PENDING';
    assert_true(l_count = 1, 'Insufficient balance rolls back the final approval');
    SELECT COUNT(*) INTO l_count FROM leave_consumption WHERE leave_id = l_leave;
    assert_true(l_count = 0, 'Insufficient balance leaves no consumption');
    ROLLBACK TO negative_case;

    SAVEPOINT negative_case;
    l_leave := new_request(l_employee);
    pkg_leave_approval.submit_request(l_leave, l_company, l_employee);
    pkg_leave_approval.take_action(l_leave, l_company, l_rp, 'APPROVE', 'Recommend');
    DELETE FROM leave_allocation
     WHERE empid = l_employee AND leave_type_id = l_type AND allocation_year = 2099;
    expect_action_error(l_leave, l_company, l_hod, 'APPROVE', -20834);
    assert_request(l_leave, 'F', 'F');
    ROLLBACK TO negative_case;

    SAVEPOINT negative_case;
    l_leave := new_request(l_employee);
    UPDATE leave_request SET l_start_date = DATE '2099-12-31',
           l_end_date = DATE '2100-01-02', proposed_days = 3 WHERE leave_id = l_leave;
    pkg_leave_approval.submit_request(l_leave, l_company, l_employee);
    pkg_leave_approval.take_action(l_leave, l_company, l_rp, 'APPROVE', 'Recommend');
    pkg_leave_approval.take_action(l_leave, l_company, l_hod, 'APPROVE', 'Final cross-year leave');
    SELECT COUNT(*) INTO l_count FROM leave_consumption
     WHERE leave_id = l_leave AND consumed_days = 3 AND consum_year = 2099
       AND start_date = DATE '2099-12-31' AND end_date = DATE '2100-01-02';
    assert_true(l_count = 1, 'Full cross-year quantity is charged only to start year');
    BEGIN
        INSERT INTO leave_consumption (leave_id, empid, leave_type_id, consumed_days, consum_year)
        VALUES (l_leave, l_employee, l_type, 3, 2099);
        RAISE_APPLICATION_ERROR(-20994, 'Duplicate linked consumption unexpectedly succeeded.');
    EXCEPTION WHEN DUP_VAL_ON_INDEX THEN NULL;
    END;
    ROLLBACK TO negative_case;

    SAVEPOINT negative_case;
    l_leave := new_request(l_employee);
    pkg_leave_approval.submit_request(l_leave, l_company, l_employee);
    pkg_leave_approval.take_action(l_leave, l_company, l_rp, 'APPROVE', 'Recommend');
    INSERT INTO leave_consumption
        (empid, leave_type_id, consumed_days, start_date, end_date, consum_year, com_id)
    VALUES (l_employee, l_type, 1, DATE '2099-01-01', DATE '2099-01-01', 2099, l_company);
    expect_action_error(l_leave, l_company, l_hod, 'APPROVE', -20838);
    assert_request(l_leave, 'F', 'F');
    SELECT COUNT(*) INTO l_count FROM leave_consumption WHERE leave_id = l_leave;
    assert_true(l_count = 0, 'Unlinked manual usage is not silently posted twice');
    ROLLBACK TO negative_case;

    ROLLBACK TO approval_test_start;
    DBMS_OUTPUT.PUT_LINE('Completed decision cases: ' || l_cases || '; negative/legacy/mapping tests also passed.');
    DBMS_OUTPUT.PUT_LINE('All request/history/consumption, allocation and RP/HOD changes rolled back.');
EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO approval_test_start;
    RAISE;
END;
/
UNDEFINE test_company_id
UNDEFINE test_employee_id
WHENEVER SQLERROR CONTINUE NONE
