/* Contract Extension module install order. Run from SQLcl or SQL*Plus as HRMS. */
SET DEFINE OFF;
SET SERVEROUTPUT ON;
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK;

/* Install the existing renewal database objects first. This module adds only
   extension objects and extension links; it never reinstalls renewal. */
DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM user_tables
     WHERE table_name IN ('HR_EMPLOYEE_CONTRACT', 'HR_CONTRACT_RENEWAL',
        'HR_EMPLOYEE_ACTION', 'HR_EMPLOYEE_LETTER', 'HR_LETTER_TEMPLATE',
        'HR_LETTER_SIGNATORY', 'HR_LETTER_RECIPIENT', 'EMPLOYEES',
        'EMP_SALARY_STRUCTURE', 'ALLOWANCE_HEAD', 'USERS_COMPANY');
    IF l_count <> 11 THEN
        RAISE_APPLICATION_ERROR(-20799, 'Install the existing contract renewal and HR tables before extension.');
    END IF;
END;
/

@@01_contract_extension_tables.sql
@@02_contract_extension_letter_config.sql
@@04_contract_extension_views.sql
@@03_pkg_hr_contract_extension.sql

PROMPT Contract Extension database objects installed.
PROMPT Check USER_ERRORS before building APEX Pages 523, 524 and 525.

SELECT name, type, line, position, text
  FROM user_errors
 WHERE name = 'PKG_HR_CONTRACT_EXTENSION'
 ORDER BY sequence;

DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM user_errors
     WHERE name IN ('PKG_HR_CONTRACT_EXTENSION', 'TRG_HR_CONTRACT_EXTENSION_NO', 'V_HR_CONTRACT_EXT_ELIGIBLE');
    IF l_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20799, 'Contract extension has compilation errors. Review USER_ERRORS.');
    END IF;
END;
/

