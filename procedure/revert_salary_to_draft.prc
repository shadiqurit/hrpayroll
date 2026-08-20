DROP PROCEDURE HRMS.REVERT_SALARY_TO_DRAFT;

CREATE OR REPLACE PROCEDURE HRMS.revert_salary_to_draft (
    p_salary_month  IN NUMBER,
    p_employee_id   IN NUMBER,
    p_reverted_by   IN NUMBER DEFAULT NULL
)
IS
    v_status  VARCHAR2(20);
BEGIN
    BEGIN
        SELECT status INTO v_status
          FROM monthly_salary
         WHERE employee_id = p_employee_id
           AND salary_month = p_salary_month;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'Salary record not found for Employee '
                || p_employee_id || ', Month ' || p_salary_month);
    END;

    IF v_status = 'PAID' THEN
        RAISE_APPLICATION_ERROR(-20004, 'Cannot revert. Salary is already PAID.');
    END IF;

    IF v_status = 'DRAFT' THEN
        RAISE_APPLICATION_ERROR(-20005, 'Salary is already in DRAFT status.');
    END IF;

    UPDATE monthly_salary
       SET status       = 'DRAFT',
           updated_by   = p_reverted_by,
           updated_date = SYSDATE
     WHERE employee_id  = p_employee_id
       AND salary_month = p_salary_month;

    COMMIT;
END;
/
