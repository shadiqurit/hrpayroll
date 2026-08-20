DROP PROCEDURE HRMS.PR_CONFIRM_EMPLOYEE;

CREATE OR REPLACE PROCEDURE HRMS.pr_confirm_employee (
    p_emp_id         IN NUMBER,
    p_confirm_date   IN DATE,
    p_remarks        IN VARCHAR2,
    p_user_id        IN NUMBER)
IS
    v_action_id      NUMBER;
    v_old_basic      NUMBER;
    v_old_gross      NUMBER;
    v_old_emp_type   NUMBER;
    v_job_id         NUMBER;
    v_desig_id       NUMBER;
    v_dept_id        NUMBER;
BEGIN
    SELECT e.emp_type,
           e.job_id,
           e.desig_id,
           e.dept_id,
           NVL (v.basic_salary, 0),
           NVL (v.gross_salary, 0)
      INTO v_old_emp_type,
           v_job_id,
           v_desig_id,
           v_dept_id,
           v_old_basic,
           v_old_gross
      FROM employees e LEFT JOIN vw_employee_salary v ON v.emp_id = e.id
     WHERE e.id = p_emp_id;

    INSERT INTO hr_employee_action (emp_id,
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
                                    reason,
                                    remarks,
                                    approval_status,
                                    ent_by,
                                    approved_by,
                                    approved_date)
         VALUES (p_emp_id,
                 'CONFIRMATION',
                 SYSDATE,
                 p_confirm_date,
                 v_old_emp_type,
                 2,
                 v_job_id,
                 v_job_id,
                 v_desig_id,
                 v_desig_id,
                 v_dept_id,
                 v_dept_id,
                 v_old_basic,
                 v_old_basic,
                 v_old_gross,
                 v_old_gross,
                 'Employee confirmed from probation',
                 p_remarks,
                 'APPROVED',
                 p_user_id,
                 p_user_id,
                 SYSDATE)
      RETURNING action_id
           INTO v_action_id;

    INSERT INTO hr_employee_career_hist (emp_id,
                                         action_id,
                                         action_type,
                                         effective_date,
                                         old_emp_type_id,
                                         new_emp_type_id,
                                         old_job_id,
                                         new_job_id,
                                         old_desig_id,
                                         new_desig_id,
                                         old_dept_id,
                                         new_dept_id,
                                         remarks,
                                         ent_by)
         VALUES (p_emp_id,
                 v_action_id,
                 'CONFIRMATION',
                 p_confirm_date,
                 v_old_emp_type,
                 2,
                 v_job_id,
                 v_job_id,
                 v_desig_id,
                 v_desig_id,
                 v_dept_id,
                 v_dept_id,
                 p_remarks,
                 p_user_id);

    UPDATE employees
       SET emp_type = 2,
           conf_date = p_confirm_date,
           last_increment_date = p_confirm_date,
           next_increment_date =
               ADD_MONTHS (p_confirm_date, NVL (increment_cycle_months, 12))
     WHERE id = p_emp_id;

    COMMIT;
END;
/
