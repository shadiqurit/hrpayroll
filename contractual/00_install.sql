/* Contract Renewal module install order. Run from SQLcl or SQL*Plus as HRMS. */
SET DEFINE OFF;
SET SERVEROUTPUT ON;

@@01_contract_renewal_tables.sql
@@02_contract_renewal_letter_config.sql
@@03_pkg_hr_contract_renewal.sql

PROMPT Contract Renewal database objects installed.
PROMPT Check USER_ERRORS before building APEX Pages 520, 521 and 522.

SELECT name, type, line, position, text
  FROM user_errors
 WHERE name = 'PKG_HR_CONTRACT_RENEWAL'
 ORDER BY sequence;

