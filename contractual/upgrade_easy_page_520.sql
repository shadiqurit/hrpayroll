/* Existing installation only: run this before recompiling
   PKG_HR_CONTRACT_RENEWAL from 03_pkg_hr_contract_renewal.sql. */
DECLARE
    L_COUNT PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
      INTO L_COUNT
      FROM USER_TAB_COLUMNS
     WHERE TABLE_NAME = 'HR_CONTRACT_RENEWAL'
       AND COLUMN_NAME = 'SALARY_MODE';

    IF L_COUNT = 0 THEN
        EXECUTE IMMEDIATE q'~
            ALTER TABLE HRMS.HR_CONTRACT_RENEWAL
            ADD SALARY_MODE VARCHAR2(10 BYTE) DEFAULT 'MANUAL' NOT NULL
        ~';
    END IF;

    SELECT COUNT(*)
      INTO L_COUNT
      FROM USER_CONSTRAINTS
     WHERE TABLE_NAME = 'HR_CONTRACT_RENEWAL'
       AND CONSTRAINT_NAME = 'CK_HR_CON_RENEW_SAL_MODE';

    IF L_COUNT = 0 THEN
        EXECUTE IMMEDIATE q'~
            ALTER TABLE HRMS.HR_CONTRACT_RENEWAL
            ADD CONSTRAINT CK_HR_CON_RENEW_SAL_MODE
            CHECK (SALARY_MODE IN ('AUTO', 'MANUAL'))
        ~';
    END IF;
END;
/

COMMENT ON COLUMN HRMS.HR_CONTRACT_RENEWAL.SALARY_MODE IS
    'AUTO advances the configured step and recalculates configured heads; MANUAL copies values for review.';

@@03_pkg_hr_contract_renewal.sql

PROMPT Page 520 automatic renewal generation upgrade installed.
