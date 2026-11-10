-- TEST HRMS database only, clean session. All business changes roll back.
-- Pick a date with exactly one existing attendance row and no pending/approved
-- manual correction for the applicant. Sequence values are consumed.
SET SERVEROUTPUT ON
SET VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
ACCEPT test_company_id NUMBER PROMPT 'Test company ID: '
ACCEPT test_employee_id NUMBER PROMPT 'Test active ordinary employee ID: '
ACCEPT test_att_date CHAR PROMPT 'Existing attendance date (YYYY-MM-DD): '

DECLARE
    l_company NUMBER := &test_company_id;
    l_employee NUMBER := &test_employee_id;
    l_date DATE := TO_DATE('&test_att_date', 'YYYY-MM-DD');
    l_target NUMBER;
    l_id NUMBER;
    l_other_id NUMBER;
    l_rp NUMBER;
    l_final NUMBER;
    l_hrd NUMBER;
    l_finals NUMBER;
    l_count NUMBER;
    l_in DATE;
    l_out DATE;
    l_status VARCHAR2(20);
    l_stage VARCHAR2(1);
    l_errors NUMBER := 0;

    PROCEDURE assert_true(p_ok BOOLEAN, p_message VARCHAR2) IS
    BEGIN
        IF p_ok IS NULL OR NOT p_ok THEN
            RAISE_APPLICATION_ERROR(-20990, 'FAIL: ' || p_message);
        END IF;
    END;

    PROCEDURE assert_state(p_id NUMBER, p_status VARCHAR2, p_stage VARCHAR2) IS
    BEGIN
        SELECT status, request_status INTO l_status, l_stage FROM manual_att WHERE id = p_id;
        assert_true(l_status = p_status AND l_stage = p_stage, 'Request state ' || p_status || '/' || p_stage);
    END;

    PROCEDURE expect_action_error(p_actor NUMBER, p_company NUMBER, p_action VARCHAR2, p_code NUMBER) IS
    BEGIN
        pkg_m_att_approval.take_action(l_id, p_company, p_actor, p_action, 'Expected error');
        RAISE_APPLICATION_ERROR(-20991, 'Action unexpectedly succeeded.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE <> p_code THEN RAISE; END IF;
        l_errors := l_errors + 1;
    END;

    PROCEDURE new_draft IS
    BEGIN
        l_id := NULL;
        pkg_m_att_approval.save_draft(l_id, l_company, l_employee, l_date,
            l_date + 9/24, l_date + 17/24, 'ROLLBACK manual approval test', 'Draft');
        assert_state(l_id, 'D', 'D');
        SELECT COUNT(*) INTO l_count FROM m_att_app_history WHERE m_att_id = l_id;
        assert_true(l_count = 0, 'Draft has no approval route');
    END;

    PROCEDURE submit_and_recommend IS
    BEGIN
        pkg_m_att_approval.submit_request(l_id, l_company, l_employee);
        assert_state(l_id, 'F', 'F');
        SELECT COUNT(*), MAX(approver_id) INTO l_count, l_rp FROM m_att_app_history
         WHERE m_att_id = l_id AND approver_level = 'RP';
        SELECT MIN(approver_id), COUNT(*) INTO l_final, l_finals FROM m_att_app_history
         WHERE m_att_id = l_id AND approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR');
        SELECT approver_id INTO l_hrd FROM m_att_app_history
         WHERE m_att_id = l_id AND approver_level = 'LEAVE_RECORD';
        assert_true(l_finals >= 1, 'At least one final candidate');
        expect_action_error(l_employee, l_company, 'APPROVE', -20817);
        expect_action_error(l_final, l_company + 1, 'APPROVE', -20805);
        expect_action_error(l_final, l_company, NULL, -20810);
        SELECT COUNT(*) INTO l_count FROM m_att_app_history
         WHERE m_att_id = l_id AND approver_id = l_hrd AND approval_status = 'PENDING';
        expect_action_error(l_hrd, l_company, 'RECORD',
            CASE WHEN l_count = 1 THEN -20813 ELSE -20817 END);
        IF l_rp IS NOT NULL THEN
            expect_action_error(l_final, l_company, 'APPROVE', -20817);
            pkg_m_att_approval.take_action(l_id, l_company, l_rp, 'APPROVE', 'RP recommendation');
            assert_state(l_id, 'F', 'F');
            expect_action_error(l_rp, l_company, 'APPROVE', -20817);
        END IF;
        SELECT COUNT(*) INTO l_count FROM m_att_app_history
         WHERE m_att_id = l_id AND approval_status = 'PENDING'
           AND approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR');
        assert_true(l_count = l_finals, 'Eligible final alternatives pending together');
    END;
BEGIN
    SAVEPOINT manual_test_start;
    SELECT attendance_id INTO l_target FROM attendance_details
     WHERE emp_id = l_employee AND com_id = l_company
       AND attendance_date >= l_date AND attendance_date < l_date + 1;
    UPDATE attendance_details SET in_time = l_date + 10/24, out_time = l_date + 16/24
     WHERE attendance_id = l_target;

    -- Draft edit/delete and validation.
    SAVEPOINT draft_case;
    new_draft;
    pkg_m_att_approval.save_draft(l_id, l_company, l_employee, l_date,
        l_date + 9/24, l_date + 17/24, 'Edited draft');
    pkg_m_att_approval.delete_draft(l_id, l_company, l_employee);
    SELECT COUNT(*) INTO l_count FROM manual_att WHERE id = l_id;
    assert_true(l_count = 0, 'Applicant can delete a draft');
    BEGIN
        l_id := NULL;
        pkg_m_att_approval.save_draft(l_id, l_company, l_employee, l_date,
            NULL, NULL, 'Invalid missing times');
        RAISE_APPLICATION_ERROR(-20991, 'Missing times accepted.');
    EXCEPTION WHEN OTHERS THEN IF SQLCODE <> -20826 THEN RAISE; END IF; END;
    ROLLBACK TO draft_case;

    -- Successful route: no attendance change until final approval.
    SAVEPOINT approve_case;
    new_draft;
    submit_and_recommend;
    SELECT in_time, out_time INTO l_in, l_out FROM attendance_details WHERE attendance_id = l_target;
    assert_true(l_in = l_date + 10/24 AND l_out = l_date + 16/24, 'Submit/RP do not post');
    BEGIN
        UPDATE manual_att SET reason = 'Unauthorized edit after submit' WHERE id = l_id;
        RAISE_APPLICATION_ERROR(-20991, 'Submitted edit accepted.');
    EXCEPTION WHEN OTHERS THEN IF SQLCODE <> -20807 THEN RAISE; END IF; END;
    BEGIN
        pkg_m_att_approval.delete_draft(l_id, l_company, l_employee);
        RAISE_APPLICATION_ERROR(-20991, 'Submitted delete accepted.');
    EXCEPTION WHEN OTHERS THEN IF SQLCODE <> -20807 THEN RAISE; END IF; END;
    -- Duplicate submission is atomic: the second draft remains a draft.
    l_other_id := NULL;
    pkg_m_att_approval.save_draft(l_other_id, l_company, l_employee, l_date,
        l_date + 9/24, l_date + 17/24, 'Duplicate test');
    BEGIN
        pkg_m_att_approval.submit_request(l_other_id, l_company, l_employee);
        RAISE_APPLICATION_ERROR(-20991, 'Duplicate date submitted.');
    EXCEPTION WHEN OTHERS THEN IF SQLCODE <> -20827 THEN RAISE; END IF; END;
    assert_state(l_other_id, 'D', 'D');

    pkg_m_att_approval.take_action(l_id, l_company, l_final, 'APPROVE', 'Final decision');
    assert_state(l_id, 'A', 'A');
    SELECT in_time, out_time INTO l_in, l_out FROM attendance_details WHERE attendance_id = l_target;
    assert_true(l_in = l_date + 9/24 AND l_out = l_date + 17/24, 'Final approval applies times');
    SELECT COUNT(*) INTO l_count FROM m_att_app_history
     WHERE m_att_id = l_id AND approval_status = 'APPROVED'
       AND approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR');
    assert_true(l_count = 1, 'Exactly one final winner');
    SELECT COUNT(*) INTO l_count FROM m_att_app_history
     WHERE m_att_id = l_id AND approval_status = 'CANCELLED';
    assert_true(l_count = l_finals - 1, 'Unused alternatives cancelled');
    expect_action_error(l_final, l_company, 'APPROVE',
        CASE WHEN l_final = l_hrd THEN -20814 ELSE -20817 END);
    FOR loser IN (SELECT approver_id FROM m_att_app_history
                   WHERE m_att_id = l_id AND approval_status = 'CANCELLED') LOOP
        expect_action_error(loser.approver_id, l_company, 'APPROVE',
            CASE WHEN loser.approver_id = l_hrd THEN -20814 ELSE -20817 END);
    END LOOP;
    post_manual_attendance(l_id, l_company, l_final);
    SELECT COUNT(*) INTO l_count FROM attendance_details WHERE attendance_id = l_target;
    assert_true(l_count = 1, 'Posting retry does not duplicate attendance');
    pkg_m_att_approval.take_action(l_id, l_company, l_hrd, 'RECORD', 'Recorded');
    SELECT COUNT(*) INTO l_count FROM v_m_att_report
     WHERE id = l_id AND status_text = 'Approved' AND recording_status = 'Recorded' AND pending_with IS NULL;
    assert_true(l_count = 1, 'Applicant sees approved/recorded with no pending actor');
    expect_action_error(l_hrd, l_company, 'RECORD', -20817);
    ROLLBACK TO approve_case;

    -- Rejection closes all waiting work and does not post.
    SAVEPOINT reject_case;
    new_draft;
    submit_and_recommend;
    pkg_m_att_approval.take_action(l_id, l_company, l_final, 'REJECT', 'Rejected');
    assert_state(l_id, 'R', 'F');
    SELECT COUNT(*) INTO l_count FROM m_att_app_history
     WHERE m_att_id = l_id AND approval_status IN ('PENDING', 'WAITING');
    assert_true(l_count = 0, 'Rejection closes all open steps');
    SELECT in_time, out_time INTO l_in, l_out FROM attendance_details WHERE attendance_id = l_target;
    assert_true(l_in = l_date + 10/24 AND l_out = l_date + 16/24, 'Rejection does not post');
    expect_action_error(l_hrd, l_company, 'RECORD', -20817);
    ROLLBACK TO reject_case;

    -- Failed posting rolls back the decision/history while preserving caller work.
    SAVEPOINT failed_post_case;
    new_draft;
    submit_and_recommend;
    DELETE FROM attendance_details WHERE attendance_id = l_target;
    expect_action_error(l_final, l_company, 'APPROVE', -20829);
    assert_state(l_id, 'F', 'F');
    SELECT COUNT(*) INTO l_count FROM m_att_app_history
     WHERE m_att_id = l_id AND approver_id = l_final AND approval_status = 'PENDING';
    assert_true(l_count = 1, 'Failed posting leaves final step pending');
    SELECT COUNT(*) INTO l_count FROM attendance_details WHERE attendance_id = l_target;
    assert_true(l_count = 0, 'Failed action does not roll back earlier caller work');
    ROLLBACK TO failed_post_case;

    -- Explicit shift date survives an OUT-only overnight request and update.
    SAVEPOINT night_case;
    l_id := NULL;
    pkg_m_att_approval.save_draft(l_id, l_company, l_employee, l_date,
        NULL, l_date + 1 + 6/24, 'OUT-only overnight test');
    UPDATE manual_att SET comments = 'Date retained' WHERE id = l_id;
    SELECT COUNT(*) INTO l_count FROM manual_att WHERE id = l_id AND att_date = l_date;
    assert_true(l_count = 1, 'Night OUT retains explicit shift date');
    ROLLBACK TO night_case;

    ROLLBACK TO manual_test_start;
    DBMS_OUTPUT.PUT_LINE('PASS: draft, validation, route, approval, recording, rejection, duplicate date, attendance posting, rollback and overnight date. Expected action errors: ' || l_errors);
EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO manual_test_start;
    RAISE;
END;
/
WHENEVER SQLERROR CONTINUE NONE
