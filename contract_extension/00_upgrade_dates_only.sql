/* Existing installations only. Run as HRMS. No tables/data are dropped.
   Also update APEX Pages 523/524/525 using the supplied Page Designer snippets. */
SET DEFINE OFF;
SET SERVEROUTPUT ON;
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK;

@@02_contract_extension_letter_config.sql
@@04_contract_extension_views.sql
@@03_pkg_hr_contract_extension.sql

COMMENT ON TABLE HRMS.HR_CONTRACT_EXTENSION IS
    'Confirmation extension history: old/new due dates, reason, user and timestamp. DRAFT then POSTED.';
COMMENT ON TABLE HRMS.HR_CONTRACT_EXTENSION_SALARY IS
    'Legacy salary snapshots retained for historical letters. Not used by date-only extensions.';
COMMENT ON COLUMN HRMS.HR_CONTRACT_EXTENSION.SALARY_MODE IS
    'Legacy compatibility value MANUAL. Date-only extensions never change payroll.';

SELECT name,type,line,position,text FROM user_errors
 WHERE name IN ('PKG_HR_CONTRACT_EXTENSION','V_HR_CONTRACT_EXT_ELIGIBLE')
 ORDER BY name,sequence;
DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM user_errors
     WHERE name IN ('PKG_HR_CONTRACT_EXTENSION','V_HR_CONTRACT_EXT_ELIGIBLE');
    IF l_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20799, 'Date-only extension has compilation errors. Review USER_ERRORS.');
    END IF;
END;
/
@@99_contract_extension_checks.sql
PROMPT Date-only extension installed. Update APEX page snippets before use.
