DROP PROCEDURE HRMS.PR_REVERSE_INCREMENT;

CREATE OR REPLACE PROCEDURE HRMS.pr_reverse_increment (
    p_emp_id      IN NUMBER,
    p_action_id   IN NUMBER DEFAULT NULL,
    p_remarks     IN VARCHAR2,
    p_user_id     IN NUMBER
)
IS
    v_action_id        NUMBER;
    v_reverse_action   NUMBER;

    v_old_basic        NUMBER;
    v_new_basic        NUMBER;
    v_old_gross        NUMBER;
    v_new_gross        NUMBER;
    v_effective_date   DATE;

    v_prev_inc_date    DATE;
BEGIN
    SELECT action_id,
           old_basic,
           new_basic,
           old_gross,
           new_gross,
           effective_date
      INTO v_action_id,
           v_old_basic,
           v_new_basic,
           v_old_gross,
           v_new_gross,
           v_effective_date
      FROM (
            SELECT action_id,
                   old_basic,
                   new_basic,
                   old_gross,
                   new_gross,
                   effective_date
              FROM hr_employee_action
             WHERE emp_id = p_emp_id
               AND action_type = 'INCREMENT'
               AND approval_status = 'APPROVED'
               AND (p_action_id IS NULL OR action_id = p_action_id)
             ORDER BY effective_date DESC, action_id DESC
           )
     WHERE ROWNUM = 1;

    MERGE INTO emp_salary_structure s
    USING (
        SELECT emp_id,
               sals_id,
               slno,
               headcode,
               old_amount
          FROM emp_salary_structure_hist
         WHERE action_id = v_action_id
           AND emp_id = p_emp_id
    ) h
    ON (
        s.employee_id = h.emp_id
        AND s.sals_id = h.sals_id
        AND s.slno = h.slno
        AND s.headcode = h.headcode
    )
    WHEN MATCHED THEN
        UPDATE SET s.amount        = h.old_amount,
                   s.revision_type = 'R',
                   s.updated_by    = p_user_id,
                   s.updated_date  = SYSDATE;

    UPDATE hr_employee_action
       SET approval_status = 'REVERSED',
           remarks = NVL(remarks, '') || ' | Reversed: ' || p_remarks
     WHERE action_id = v_action_id
       AND emp_id = p_emp_id;

    INSERT INTO hr_employee_action (
        emp_id,
        action_type,
        action_date,
        effective_date,
        old_emp_type_id,
        new_emp_type_id,
        old_job_id,
        new_job_id,
        old_desig_id,
        new_desig_id,
        old_dept_id,
        new_dept_id,
        old_basic,
        new_basic,
        old_gross,
        new_gross,
        increment_amount,
        old_eb_status,
        new_eb_status,
        reason,
        remarks,
        approval_status,
        ent_by,
        approved_by,
        approved_date
    )
    SELECT emp_id,
           'REVERSE_INCREMENT',
           SYSDATE,
           effective_date,
           new_emp_type_id,
           old_emp_type_id,
           new_job_id,
           old_job_id,
           new_desig_id,
           old_desig_id,
           new_dept_id,
           old_dept_id,
           new_basic,
           old_basic,
           new_gross,
           old_gross,
           old_basic - new_basic,
           new_eb_status,
           old_eb_status,
           'Reverse annual increment',
           p_remarks,
           'APPROVED',
           p_user_id,
           p_user_id,
           SYSDATE
      FROM hr_employee_action
     WHERE action_id = v_action_id
       AND emp_id = p_emp_id;

    SELECT MAX(action_id)
      INTO v_reverse_action
      FROM hr_employee_action
     WHERE emp_id = p_emp_id
       AND action_type = 'REVERSE_INCREMENT'
       AND ent_by = p_user_id;

    SELECT MAX(effective_date)
      INTO v_prev_inc_date
      FROM hr_employee_action
     WHERE emp_id = p_emp_id
       AND action_type = 'INCREMENT'
       AND approval_status = 'APPROVED'
       AND effective_date < v_effective_date;

    UPDATE employees
       SET last_increment_date = v_prev_inc_date,
           next_increment_date =
               CASE
                   WHEN v_prev_inc_date IS NOT NULL
                   THEN ADD_MONTHS(v_prev_inc_date, NVL(increment_cycle_months, 12))
                   ELSE NULL
               END
     WHERE id = p_emp_id;

    COMMIT;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(
            -20101,
            'No approved increment found to reverse.'
        );

    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/
