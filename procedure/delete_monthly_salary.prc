DROP PROCEDURE HRMS.DELETE_MONTHLY_SALARY;

CREATE OR REPLACE PROCEDURE HRMS.delete_monthly_salary (
    p_salary_month   IN NUMBER,
    p_employee_id    IN NUMBER DEFAULT NULL      -- NULL = all DRAFT employees
                                           )
IS
    v_status   VARCHAR2 (20);
BEGIN
    IF p_employee_id IS NOT NULL
    THEN
        -- Single employee delete
        BEGIN
            SELECT status
              INTO v_status
              FROM monthly_salary
             WHERE     employee_id = p_employee_id
                   AND salary_month = p_salary_month;
        EXCEPTION
            WHEN NO_DATA_FOUND
            THEN
                RAISE_APPLICATION_ERROR (
                    -20001,
                       'Salary record not found for Employee '
                    || p_employee_id
                    || ', Month '
                    || p_salary_month);
        END;

        IF v_status != 'DRAFT'
        THEN
            RAISE_APPLICATION_ERROR (
                -20002,
                   'Cannot delete salary. Status is '
                || v_status
                || '. Only DRAFT salary can be deleted.');
        END IF;

        DELETE FROM
            monthly_salary_details
              WHERE ms_id =
                    (SELECT ms_id
                       FROM monthly_salary
                      WHERE     employee_id = p_employee_id
                            AND salary_month = p_salary_month);

        DELETE FROM
            monthly_salary
              WHERE     employee_id = p_employee_id
                    AND salary_month = p_salary_month;
    ELSE
        -- Bulk delete all DRAFT for the month
        DELETE FROM
            monthly_salary_details
              WHERE ms_id IN
                        (SELECT ms_id
                           FROM monthly_salary
                          WHERE     salary_month = p_salary_month
                                AND status = 'DRAFT');

        DELETE FROM hr_adv_installments
              WHERE YEARMN = p_salary_month;

        DELETE FROM monthly_salary
              WHERE salary_month = p_salary_month AND status = 'DRAFT';
    END IF;

    COMMIT;
END;
/
