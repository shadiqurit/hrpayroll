-- Run as a SQL*Plus / SQLcl script after the REQUEST_STATUS upgrade.
-- Installs the fix; this script does not delete existing leave requests.
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

@@TRG_LEAVE_REQUEST_DELETE.sql
@@DELETE_LEAVE_REQUEST.sql

DECLARE
    v_errors NUMBER;
BEGIN
    SELECT COUNT(*)
      INTO v_errors
      FROM all_errors
     WHERE owner = 'HRMS'
       AND name IN ('TRG_LEAVE_REQUEST_DELETE', 'DELETE_LEAVE_REQUEST')
       AND attribute = 'ERROR';

    IF v_errors > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20004,
            'Leave delete fix has compilation errors. Check ALL_ERRORS for HRMS leave objects.'
        );
    END IF;
END;
/

WHENEVER SQLERROR CONTINUE NONE
