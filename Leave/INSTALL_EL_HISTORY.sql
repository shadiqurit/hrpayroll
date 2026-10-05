-- SQL*Plus/SQLcl connected as HRMS. LEAVE_DATA must already exist/populate.
-- Install UPGRADE_MONTHLY_ALLOCATION.sql first. DDL commits existing work.
-- This script creates HRMS tracking objects; LEAVE_DATA is read-only.
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM all_objects
     WHERE owner = 'HRMS' AND status = 'VALID'
       AND ((object_type = 'FUNCTION' AND object_name = 'FN_EL_ENTITLEMENT')
         OR (object_type = 'TABLE' AND object_name IN
             ('LEAVE_DATA', 'LEAVE_ALLOCATION', 'LEAVE_CONSUMPTION', 'EMPLOYEES', 'T_EMP_TYP')));
    IF v_count <> 6 THEN
        RAISE_APPLICATION_ERROR(-20085, 'Missing EL history prerequisites, including the populated LEAVE_DATA table.');
    END IF;
    SELECT COUNT(*) INTO v_count FROM all_constraints
     WHERE owner = 'HRMS' AND table_name = 'LEAVE_ALLOCATION'
       AND constraint_name = 'UK_LEAVE_ALLOC_EMP_TYPE_YEAR'
       AND status = 'ENABLED' AND validated = 'VALIDATED';
    IF v_count <> 1 THEN
        RAISE_APPLICATION_ERROR(-20086, 'Install UPGRADE_MONTHLY_ALLOCATION.sql before EL history.');
    END IF;
END;
/

@@EL_HISTORY_SCHEMA.sql
@@FN_EL_SOURCE_KEY.sql
@@V_EL_LEGACY_SOURCE.sql
@@PKG_EL_HISTORY.sql
@@V_EL_YEAR_BALANCE.sql

DECLARE
    v_errors NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_errors FROM all_errors
     WHERE owner = 'HRMS' AND attribute = 'ERROR'
       AND name IN ('FN_EL_SOURCE_KEY', 'V_EL_LEGACY_SOURCE',
                    'PKG_EL_HISTORY', 'V_EL_YEAR_BALANCE', 'V_EL_BALANCE');
    IF v_errors > 0 THEN
        RAISE_APPLICATION_ERROR(-20082, 'EL history compilation failed; check ALL_ERRORS.');
    END IF;
END;
/

-- Run TEST_EL_REFERENCE.sql and TEST_EL_HISTORY.sql in a test schema for rollback-based
-- integration checks; it is not automatically run against business data.
WHENEVER SQLERROR CONTINUE NONE
