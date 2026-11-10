-- Final approval posts supplied boundaries and recalculates the applicant only.
-- Caller owns the transaction; a failure also rolls back the approval decision.
CREATE OR REPLACE PROCEDURE HRMS.post_manual_attendance(
    p_att_id NUMBER, p_company_id NUMBER, p_actor_id NUMBER) AUTHID DEFINER IS
    l_request manual_att%ROWTYPE;
    l_id NUMBER;
    l_in DATE;
    l_out DATE;
    l_count NUMBER;
BEGIN
    SAVEPOINT manual_post_start;
    SELECT * INTO l_request FROM manual_att WHERE id = p_att_id FOR UPDATE;
    IF p_company_id IS NULL OR l_request.com_id IS NULL
       OR l_request.com_id <> p_company_id OR NVL(l_request.status, '#') <> 'A'
       OR NVL(l_request.request_status, '#') <> 'A' OR NVL(l_request.workflow_version, 0) <> 1 THEN
        RAISE_APPLICATION_ERROR(-20828, 'Only a final-approved company request can update attendance.');
    END IF;
    SELECT COUNT(*) INTO l_count FROM m_att_app_history
     WHERE m_att_id = p_att_id AND com_id = p_company_id
       AND approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR')
       AND approval_status = 'APPROVED' AND approver_id = p_actor_id;
    IF l_count <> 1 THEN
        RAISE_APPLICATION_ERROR(-20828, 'The final approval decision is required before posting.');
    END IF;
    SELECT attendance_id, NVL(l_request.m_intime, in_time), NVL(l_request.m_outtime, out_time)
      INTO l_id, l_in, l_out FROM attendance_details
     WHERE emp_id = l_request.empid AND com_id = p_company_id
       AND attendance_date >= TRUNC(l_request.att_date)
       AND attendance_date < TRUNC(l_request.att_date) + 1 FOR UPDATE;
    IF l_in IS NOT NULL AND l_out IS NOT NULL AND (l_out < l_in OR l_out - l_in > 1) THEN
        RAISE_APPLICATION_ERROR(-20826, 'Correction conflicts with the other attendance punch. Supply both corrected times.');
    END IF;
    UPDATE attendance_details SET in_time = l_in, out_time = l_out,
        remarks = SUBSTR('Manual attendance #' || TO_CHAR(p_att_id), 1, 255)
     WHERE attendance_id = l_id;
    HRMS.p_att_update_details(l_request.att_date, l_request.att_date,
                             p_commit => 0, p_emp_id => l_request.empid);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        ROLLBACK TO manual_post_start;
        RAISE_APPLICATION_ERROR(-20829, 'Request or attendance schedule row is missing. Generate the employee shift/date before approval.');
    WHEN TOO_MANY_ROWS THEN
        ROLLBACK TO manual_post_start;
        RAISE_APPLICATION_ERROR(-20829, 'Multiple attendance rows exist for this employee/date; review the shift key.');
    WHEN OTHERS THEN
        ROLLBACK TO manual_post_start;
        RAISE;
END;
/
