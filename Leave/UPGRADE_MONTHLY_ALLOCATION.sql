-- SQL*Plus / SQLcl, connected as HRMS. Run once before using monthly allocation.
-- DDL commits. No existing allocations are recalculated by this installer.
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM HRMS.t_emp_typ
     WHERE (id = 0 AND etype = 'Reguler')
        OR (id = 1 AND etype = 'Probation')
        OR (id = 2 AND etype = 'Confirmed')
        OR (id = 3 AND etype = 'Contractual')
        OR (id = 4 AND etype = 'Casual');
    IF v_count <> 5 THEN
        RAISE_APPLICATION_ERROR(-20057,
            'T_EMP_TYP does not match the supplied numeric type reference data.');
    END IF;

    SELECT COUNT(*) INTO v_count
      FROM (SELECT empid, leave_type_id, allocation_year
              FROM HRMS.leave_allocation
             GROUP BY empid, leave_type_id, allocation_year
            HAVING COUNT(*) > 1);
    IF v_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20051,
            'Duplicate employee/type/year allocations exist. Review them before upgrading.');
    END IF;

    SELECT COUNT(*) INTO v_count FROM all_constraints
     WHERE owner = 'HRMS' AND constraint_name = 'UK_LEAVE_ALLOC_EMP_TYPE_YEAR';
    IF v_count = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE HRMS.leave_allocation ADD '
            || 'CONSTRAINT uk_leave_alloc_emp_type_year '
            || 'UNIQUE (empid, leave_type_id, allocation_year)';
    END IF;
END;
/

-- Supply missing global leave codes without assuming fixed LT_ID values.
-- Company-specific active codes take precedence over the global defaults.
LOCK TABLE HRMS.leave_types IN EXCLUSIVE MODE;
DECLARE
    v_id NUMBER;
    v_count NUMBER;
BEGIN
    SELECT NVL(MAX(lt_id), 0) INTO v_id FROM HRMS.leave_types;
    FOR r IN (
        SELECT 'SL' code, 'Sick Leave' name, 14 quota FROM dual UNION ALL
        SELECT 'CL', 'Casual Leave', 10 FROM dual UNION ALL
        SELECT 'EL', 'Earned Leave', 30 FROM dual UNION ALL
        SELECT 'RL', 'Recreation Leave', 15 FROM dual
    ) LOOP
        SELECT COUNT(*) INTO v_count FROM HRMS.leave_types
         WHERE UPPER(TRIM(short_code)) = r.code
           AND active_flag = 'Y' AND com_id IS NULL;
        IF v_count = 0 THEN
            v_id := v_id + 1;
            INSERT INTO HRMS.leave_types
                (lt_id, short_code, leave_type_name, annual_quota, is_paid, active_flag)
            VALUES (v_id, r.code, r.name, r.quota, 'Y', 'Y');
        END IF;
    END LOOP;
END;
/
COMMIT;

@@FN_LEAVE_ENTITLEMENT.sql
@@P_LEAVE_ALLOCATION.sql

DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM all_errors
     WHERE owner = 'HRMS'
       AND name IN ('FN_LEAVE_ENTITLEMENT', 'P_LEAVE_ALLOCATION')
       AND attribute = 'ERROR';
    IF v_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20052,
            'Leave allocation compilation failed. Check ALL_ERRORS.');
    END IF;
END;
/

@@TEST_LEAVE_ENTITLEMENT.sql
WHENEVER SQLERROR CONTINUE NONE
