/*
  Existing-schema migration for the two-stage increment lifecycle:

      READY -> APPLIED -> POSTED
                    \
                     -> READY (undo before final only)

  Run as HRMS (or a DBA with ALTER privilege) after taking a backup.
  Oracle DDL commits automatically.
*/

DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*)
      INTO v_count
      FROM user_tab_columns
     WHERE table_name = 'HR_EMPLOYEE_INCREMENT'
       AND column_name = 'APPLIED_BY';

    IF v_count = 0 THEN
        EXECUTE IMMEDIATE
            'ALTER TABLE HRMS.HR_EMPLOYEE_INCREMENT ADD (APPLIED_BY NUMBER)';
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM user_tab_columns
     WHERE table_name = 'HR_EMPLOYEE_INCREMENT'
       AND column_name = 'APPLIED_DATE';

    IF v_count = 0 THEN
        EXECUTE IMMEDIATE
            'ALTER TABLE HRMS.HR_EMPLOYEE_INCREMENT ADD (APPLIED_DATE DATE)';
    END IF;
END;
/

DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*)
      INTO v_count
      FROM user_constraints
     WHERE table_name = 'HR_EMPLOYEE_INCREMENT'
       AND constraint_name = 'CHK_HR_EMP_INC_STATUS';

    IF v_count > 0 THEN
        EXECUTE IMMEDIATE
            'ALTER TABLE HRMS.HR_EMPLOYEE_INCREMENT '
            || 'DROP CONSTRAINT CHK_HR_EMP_INC_STATUS';
    END IF;

    EXECUTE IMMEDIATE q'[
        ALTER TABLE HRMS.HR_EMPLOYEE_INCREMENT ADD CONSTRAINT CHK_HR_EMP_INC_STATUS
        CHECK (STATUS IN (
            'DRAFT', 'READY', 'APPLIED', 'EXTENDED', 'HOLD', 'PUNISHMENT',
            'FORFEITED', 'POSTED', 'CANCELLED', 'ERROR', 'REVERSED',
            'CLOSED_NO_INCREMENT'
        ))
    ]';
END;
/

SELECT constraint_name, status
  FROM user_constraints
 WHERE table_name = 'HR_EMPLOYEE_INCREMENT'
   AND constraint_name = 'CHK_HR_EMP_INC_STATUS';

