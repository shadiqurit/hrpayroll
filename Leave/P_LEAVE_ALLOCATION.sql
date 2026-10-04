CREATE OR REPLACE PROCEDURE HRMS.p_leave_allocation (
    p_year                  IN NUMBER,
    p_as_of_date            IN DATE DEFAULT SYSDATE,
    p_rl_all_employees      IN NUMBER DEFAULT 0
)
AUTHID DEFINER
AS
    v_check NUMBER;
BEGIN
    -- Validate even when the employee table is empty.
    v_check := HRMS.fn_leave_entitlement(
        p_year, p_as_of_date, NULL, NULL, NULL, NULL, 'EL', p_rl_all_employees);

    -- EMPLOYEES.EMP_TYPE is VARCHAR2 in the supplied table definition but
    -- stores numeric T_EMP_TYP.ID values. Compare their character forms to
    -- validate references without converting invalid legacy text to NUMBER.
    SELECT COUNT(*) INTO v_check
      FROM HRMS.employees e
      LEFT JOIN HRMS.t_emp_typ et ON TRIM(e.emp_type) = TO_CHAR(et.id)
     WHERE e.status = 1 AND et.id IS NULL;
    IF v_check > 0 THEN
        RAISE_APPLICATION_ERROR(-20056,
            'Active employees have missing or invalid EMP_TYPE references. Use numeric T_EMP_TYP.ID values.');
    END IF;

    -- Global codes are fallbacks for companies without a local active code.
    SELECT COUNT(*) INTO v_check
      FROM (
        SELECT e.id, UPPER(TRIM(lt.short_code))
          FROM HRMS.employees e
          JOIN HRMS.leave_types lt
            ON lt.active_flag = 'Y'
           AND UPPER(TRIM(lt.short_code)) IN ('SL', 'CL', 'EL', 'RL')
           AND (lt.com_id = e.com_id OR
                (lt.com_id IS NULL AND NOT EXISTS (
                    SELECT 1 FROM HRMS.leave_types local_lt
                     WHERE local_lt.com_id = e.com_id
                       AND local_lt.active_flag = 'Y'
                       AND UPPER(TRIM(local_lt.short_code)) = UPPER(TRIM(lt.short_code))
                )))
         WHERE e.status = 1
         GROUP BY e.id, UPPER(TRIM(lt.short_code))
        HAVING COUNT(*) > 1
      );
    IF v_check > 0 THEN
        RAISE_APPLICATION_ERROR(-20054, 'Duplicate active leave codes exist for an employee company.');
    END IF;

    MERGE INTO HRMS.leave_allocation la
    USING (
        SELECT e.id AS empid, e.com_id, lt.lt_id AS leave_type_id,
               HRMS.fn_leave_entitlement(
                   p_year, p_as_of_date, e.join_date, e.dob,
                   et.id, e.conf_date, lt.short_code, p_rl_all_employees
               ) AS allocated_days
          FROM HRMS.employees e
          JOIN HRMS.t_emp_typ et ON TRIM(e.emp_type) = TO_CHAR(et.id)
          JOIN HRMS.leave_types lt
            ON lt.active_flag = 'Y'
           AND UPPER(TRIM(lt.short_code)) IN ('SL', 'CL', 'EL', 'RL')
           AND (lt.com_id = e.com_id OR
                (lt.com_id IS NULL AND NOT EXISTS (
                    SELECT 1 FROM HRMS.leave_types local_lt
                     WHERE local_lt.com_id = e.com_id
                       AND local_lt.active_flag = 'Y'
                       AND UPPER(TRIM(local_lt.short_code)) = UPPER(TRIM(lt.short_code))
                )))
         WHERE e.status = 1
    ) src
    ON (la.empid = src.empid
        AND la.leave_type_id = src.leave_type_id
        AND la.allocation_year = p_year)
    WHEN MATCHED THEN UPDATE SET
        la.allocated_days = src.allocated_days,
        la.allocated_date = LEAST(TRUNC(p_as_of_date),
            ADD_MONTHS(TO_DATE(TO_CHAR(p_year, 'FM0000') || '0101', 'YYYYMMDD'), 12) - 1),
        la.upd_date = SYSDATE,
        la.com_id = src.com_id
    WHEN NOT MATCHED THEN INSERT
        (empid, leave_type_id, allocated_days, allocation_year, allocated_date, com_id)
    VALUES
        (src.empid, src.leave_type_id, src.allocated_days, p_year,
         LEAST(TRUNC(p_as_of_date),
            ADD_MONTHS(TO_DATE(TO_CHAR(p_year, 'FM0000') || '0101', 'YYYYMMDD'), 12) - 1),
         src.com_id);

    -- Recalculate cumulative annual entitlement, never add it again.
    -- Caller controls COMMIT/ROLLBACK; consumption is maintained separately.
END p_leave_allocation;
/
