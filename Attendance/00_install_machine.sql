-- Run as a SQL*Plus/SQLcl script in a TEST HRMS schema first.
-- Machine foundation only: manual attendance / leave / short leave are pending.
-- DDL commits: finish unrelated transactions before installation.
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

@@V_ATT_GEN1.sql
@@P_ATT_SCHEDULE.sql
@@P_ATT_CONT_SHIFT_FAST.sql
@@P_ATT_UPDATE_DETAILS.sql
@@P_ATT_REBUILD_MACHINE.sql

SELECT name, type, line, position, text
  FROM all_errors
 WHERE owner = 'HRMS'
   AND name IN ('V_ATT_GEN1', 'P_ATT_SCHEDULE', 'P_ATT_CONT_SHIFT_FAST',
                'P_ATT_UPDATE_DETAILS', 'P_ATT_REBUILD_MACHINE')
   AND attribute = 'ERROR'
 ORDER BY name, sequence;

DECLARE
    l_invalid NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_invalid
      FROM all_objects
     WHERE owner = 'HRMS'
       AND object_name IN ('V_ATT_GEN1', 'P_ATT_SCHEDULE', 'P_ATT_CONT_SHIFT_FAST',
                           'P_ATT_UPDATE_DETAILS', 'P_ATT_REBUILD_MACHINE')
       AND status <> 'VALID';
    IF l_invalid <> 0 THEN
        RAISE_APPLICATION_ERROR(-20903, 'Attendance compilation failed; see errors above.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('Machine rebuild objects compiled. No attendance data was rebuilt.');
END;
/
