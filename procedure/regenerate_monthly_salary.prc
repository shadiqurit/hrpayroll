DROP PROCEDURE HRMS.REGENERATE_MONTHLY_SALARY;

CREATE OR REPLACE PROCEDURE HRMS.regenerate_monthly_salary (
    p_salary_month  IN NUMBER,
    p_employee_id   IN NUMBER,
    p_created_by    IN NUMBER DEFAULT NULL
)
IS
    v_ms_id   NUMBER;
    v_status  VARCHAR2(20);
BEGIN
    BEGIN
        SELECT ms_id, status
          INTO v_ms_id, v_status
          FROM monthly_salary
         WHERE employee_id = p_employee_id
           AND salary_month = p_salary_month;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'Salary record not found for Employee '
                || p_employee_id || ', Month ' || p_salary_month);
    END;

    IF v_status != 'DRAFT' THEN
        RAISE_APPLICATION_ERROR(-20002, 'Cannot modify salary. Status is ' || v_status
            || '. Only DRAFT salary can be regenerated.');
    END IF;

    -- Clear old details
    DELETE FROM monthly_salary_details WHERE ms_id = v_ms_id;

    -- Re-insert from structure
    INSERT INTO monthly_salary_details
        (ms_id, employee_id, salary_month, slno, headcode, head_name, head_type, amount, source, created_by, created_date)
    SELECT v_ms_id, sl.employee_id, p_salary_month, sl.slno, sl.headcode,
           ah.head_name, ah.head_type, sl.amount, 'STRUCTURE', p_created_by, SYSDATE
      FROM emp_salary_structure sl
      JOIN allowance_head ah ON sl.slno = ah.head_id
     WHERE sl.employee_id = p_employee_id;

    -- Re-insert from adjustments
    INSERT INTO monthly_salary_details
        (ms_id, employee_id, salary_month, slno, headcode, head_name, head_type, amount, source, remarks, created_by, created_date)
    SELECT v_ms_id, adj.employee_id, p_salary_month, NULL, adj.headcode,
           adj.head_name, adj.head_type, adj.amount, 'ADDITIONAL', adj.remarks, p_created_by, SYSDATE
      FROM monthly_salary_adjustment adj
     WHERE adj.employee_id = p_employee_id
       AND adj.salary_month = p_salary_month;

    -- Recalculate totals
    UPDATE monthly_salary
       SET (total_earning, total_deduction, net_salary) = (
               SELECT NVL(SUM(CASE WHEN head_type = 'EARNING' THEN amount ELSE 0 END), 0),
                      NVL(SUM(CASE WHEN head_type = 'DEDUCTION' THEN amount ELSE 0 END), 0),
                      NVL(SUM(CASE WHEN head_type = 'EARNING' THEN amount ELSE 0 END), 0)
                    - NVL(SUM(CASE WHEN head_type = 'DEDUCTION' THEN amount ELSE 0 END), 0)
                 FROM monthly_salary_details
                WHERE ms_id = v_ms_id
           ),
           updated_by   = p_created_by,
           updated_date  = SYSDATE
     WHERE ms_id = v_ms_id;

    COMMIT;
END;
/
