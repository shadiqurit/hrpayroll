-- Existing tables only: no DROP/CREATE, request backfill, or balance recalculation.
-- SQL*Plus/SQLcl as HRMS. DDL commits; pause approval/consumption writes first.
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
DECLARE
    l_count NUMBER;
BEGIN
    IF USER <> 'HRMS' THEN
        RAISE_APPLICATION_ERROR(-20824, 'Connect as HRMS before upgrading leave consumption.');
    END IF;
    SELECT COUNT(*) INTO l_count FROM
        (SELECT empid, leave_type_id, allocation_year FROM leave_allocation
          GROUP BY empid, leave_type_id, allocation_year HAVING COUNT(*) > 1);
    IF l_count <> 0 THEN
        RAISE_APPLICATION_ERROR(-20834, 'Duplicate employee/type/year allocations require review before posting is enabled.');
    END IF;
    SELECT COUNT(*) INTO l_count FROM user_tab_columns
     WHERE table_name = 'LEAVE_CONSUMPTION' AND column_name = 'LEAVE_ID';
    IF l_count = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE HRMS.leave_consumption ADD (leave_id NUMBER)';
    END IF;
END;
/

DECLARE
    l_count NUMBER;
BEGIN
    -- One lockable allocation row per employee/type/year is essential to
    -- serialize approvals of different requests competing for the same balance.
    SELECT COUNT(*) INTO l_count FROM user_constraints c
     WHERE c.table_name = 'LEAVE_ALLOCATION' AND c.constraint_type IN ('U', 'P')
       AND c.status = 'ENABLED' AND c.validated = 'VALIDATED'
       AND (SELECT COUNT(*) FROM user_cons_columns cc
             WHERE cc.constraint_name = c.constraint_name) = 3
       AND (SELECT COUNT(*) FROM user_cons_columns cc
             WHERE cc.constraint_name = c.constraint_name
               AND cc.column_name IN ('EMPID', 'LEAVE_TYPE_ID', 'ALLOCATION_YEAR')) = 3;
    IF l_count = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE HRMS.leave_allocation ADD CONSTRAINT '
            || 'uk_leave_alloc_emp_type_year UNIQUE (empid, leave_type_id, allocation_year)';
    END IF;

    SELECT COUNT(*) INTO l_count FROM user_constraints
     WHERE table_name = 'LEAVE_CONSUMPTION' AND constraint_name = 'UK_LEAVE_CONSUM_REQUEST';
    IF l_count = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE HRMS.leave_consumption ADD CONSTRAINT '
            || 'uk_leave_consum_request UNIQUE (leave_id)';
    END IF;
    SELECT COUNT(*) INTO l_count FROM user_constraints
     WHERE table_name = 'LEAVE_CONSUMPTION' AND constraint_name = 'FK_LEAVE_CONSUM_REQUEST';
    IF l_count = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE HRMS.leave_consumption ADD CONSTRAINT '
            || 'fk_leave_consum_request FOREIGN KEY (leave_id) REFERENCES HRMS.leave_request (leave_id)';
    END IF;
    SELECT COUNT(*) INTO l_count FROM user_constraints
     WHERE table_name = 'LEAVE_CONSUMPTION' AND constraint_name = 'CK_LEAVE_CONSUM_REQUEST';
    IF l_count = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE HRMS.leave_consumption ADD CONSTRAINT '
            || 'ck_leave_consum_request CHECK (leave_id IS NULL OR '
            || '(consum_year IS NOT NULL AND consum_year = TRUNC(consum_year) AND consumed_days > 0))';
    END IF;
    SELECT COUNT(*) INTO l_count FROM user_constraints
     WHERE constraint_name IN ('UK_LEAVE_CONSUM_REQUEST', 'FK_LEAVE_CONSUM_REQUEST',
                               'CK_LEAVE_CONSUM_REQUEST')
       AND table_name = 'LEAVE_CONSUMPTION'
       AND status = 'ENABLED' AND validated = 'VALIDATED';
    IF l_count <> 3 THEN
        RAISE_APPLICATION_ERROR(-20835, 'Consumption request constraints must be enabled and validated.');
    END IF;
END;
/
@@TRG_LEAVE_CONSUMPTION_PK.sql
PROMPT Consumption request link installed. Existing rows remain unlinked and unchanged.
