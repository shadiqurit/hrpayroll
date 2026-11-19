/* Read-only post-install checks. Run as HRMS. */

/* Compilation: no rows expected. */
SELECT name,type,line,position,text FROM user_errors
 WHERE name IN ('PKG_HR_CONTRACT_EXTENSION','TRG_HR_CONTRACT_EXTENSION_NO','V_HR_CONTRACT_EXT_ELIGIBLE')
 ORDER BY name,sequence;

/* Required objects should be VALID. Salary table is retained for historical letters. */
SELECT object_name,object_type,status FROM user_objects
 WHERE object_name IN ('HR_CONTRACT_EXTENSION',
    'HR_CONTRACT_EXTENSION_SALARY','HR_CONTRACT_EXT_RECIPIENT',
    'V_HR_CONTRACT_EXT_ELIGIBLE','PKG_HR_CONTRACT_EXTENSION')
 ORDER BY object_type,object_name;

/* Both history date columns are required on the shared employee action table. */
SELECT column_name,data_type FROM user_tab_columns
 WHERE table_name='HR_EMPLOYEE_ACTION'
   AND column_name IN ('OLD_EFFECTIVE_DATE','NEW_EFFECTIVE_DATE');

SELECT id,etype FROM t_emp_typ ORDER BY id;
SELECT emp_id,employee_code,employee_name,employee_type,grade,
       current_from_date,current_to_date FROM v_hr_contract_ext_eligible
 ORDER BY current_to_date,employee_code;

/* Draft employee type must still match: no rows expected. */
SELECT r.extension_id,r.extension_no FROM hr_contract_extension r JOIN employees e ON e.id=r.emp_id
 WHERE r.status='DRAFT' AND (TRIM(e.emp_type) NOT IN ('1','3') OR e.emp_type IS NULL
       OR r.emp_type_snapshot IS NULL OR r.emp_type_snapshot<>TRIM(e.emp_type)
       OR e.conf_date IS NOT NULL OR e.confirmation_due_date IS NULL
       OR TRUNC(e.confirmation_due_date)<>r.current_to_date
       OR (e.sep_date IS NOT NULL AND TRUNC(e.sep_date)<=TRUNC(SYSDATE)));

/* Existing drafts needing a reason/clearance of old additional terms before posting. */
SELECT extension_no,reason FROM hr_contract_extension
 WHERE status='DRAFT' AND (TRIM(reason) IS NULL OR NVL(DBMS_LOB.GETLENGTH(special_terms),0)>0);

/* Every posted record needs an extension action and issued linked letter.
   No rows expected. Historical salary snapshots are not changed or required. */
SELECT r.extension_id,r.extension_no FROM hr_contract_extension r
 LEFT JOIN hr_employee_letter l ON l.letter_id=r.letter_id
 LEFT JOIN hr_employee_action a ON a.action_id=r.action_id
 WHERE r.status='POSTED' AND (a.action_id IS NULL OR NVL(a.action_type,'?')<>'CONTRACT_EXTENSION'
    OR NVL(a.emp_id,-1)<>r.emp_id OR r.letter_id IS NULL OR l.letter_id IS NULL
    OR NVL(l.status,'?')<>'ISSUED' OR NVL(l.contract_extension_id,-1)<>r.extension_id);

/* Employee extension history, similar to a disciplinary log. */
SELECT r.emp_code_snapshot,r.emp_name_snapshot,r.extension_no,
       r.current_to_date AS previous_confirmation_due_date,r.new_to_date AS extended_confirmation_due_date,
       r.new_to_date-r.current_to_date AS extension_days,r.reason,r.remarks,
       r.posted_by,r.posted_date,a.old_effective_date,a.new_effective_date
  FROM hr_contract_extension r
  LEFT JOIN hr_employee_action a ON a.action_id=r.action_id
 WHERE r.status='POSTED' ORDER BY r.emp_id,r.posted_date DESC,r.extension_id DESC;

SELECT template_code,template_name,is_active FROM hr_letter_template
 WHERE action_type='CONTRACT_EXTENSION' ORDER BY template_code;
SELECT signatory_code,name_en,title_en,is_active FROM hr_letter_signatory ORDER BY display_order;
