/* Read-only post-install checks. Run as HRMS. */

/* Compilation: no rows expected. */
SELECT name,type,line,position,text FROM user_errors
 WHERE name IN ('PKG_HR_CONTRACT_EXTENSION','TRG_HR_CONTRACT_EXTENSION_NO','V_HR_CONTRACT_EXT_ELIGIBLE')
 ORDER BY name,sequence;

/* Required objects should be VALID. */
SELECT object_name,object_type,status FROM user_objects
 WHERE object_name IN ('HR_EMPLOYEE_CONTRACT','HR_CONTRACT_EXTENSION',
    'HR_CONTRACT_EXTENSION_SALARY','HR_CONTRACT_EXT_RECIPIENT',
    'V_HR_CONTRACT_EXT_ELIGIBLE','PKG_HR_CONTRACT_EXTENSION')
 ORDER BY object_type,object_name;

/* NEW_GRADE_ID, NEW_SCALE_ID and NEW_STEP_NO must be nullable. */
SELECT column_name,nullable FROM user_tab_columns
 WHERE table_name='HR_CONTRACT_EXTENSION'
   AND column_name IN ('NEW_GRADE_ID','NEW_SCALE_ID','NEW_STEP_NO','EMP_TYPE_SNAPSHOT','SALARY_MODE');

/* Confirm employee-type codes against your actual master. */
SELECT id,etype FROM t_emp_typ ORDER BY id;

/* Eligible population, with and without grade/contract dates. */
SELECT emp_id,employee_code,employee_name,employee_type,grade,
       current_from_date,current_to_date FROM v_hr_contract_ext_eligible
 ORDER BY current_to_date,employee_code;

/* Invalid draft mode or missing employee type: no rows expected. */
SELECT extension_id,extension_no,salary_mode,emp_type_snapshot
  FROM hr_contract_extension WHERE status='DRAFT'
   AND (salary_mode<>'MANUAL' OR emp_type_snapshot IS NULL);

/* Active draft eligibility/type must still match. */
SELECT r.extension_id,r.extension_no FROM hr_contract_extension r JOIN employees e ON e.id=r.emp_id
 WHERE r.status='DRAFT' AND (TRIM(e.emp_type) NOT IN ('1','3') OR e.emp_type IS NULL
       OR r.emp_type_snapshot<>TRIM(e.emp_type)
       OR (e.sep_date IS NOT NULL AND TRUNC(e.sep_date)<=TRUNC(SYSDATE)));

/* Every posted record needs an action, an issued linked letter and posted details.
   No rows expected. Older posted records are checked without rewriting them. */
SELECT r.extension_id,r.extension_no FROM hr_contract_extension r
 LEFT JOIN hr_employee_letter l ON l.letter_id=r.letter_id
 WHERE r.status='POSTED' AND (r.action_id IS NULL OR r.letter_id IS NULL
    OR l.letter_id IS NULL OR NVL(l.status,'?')<>'ISSUED'
    OR NVL(l.contract_extension_id,-1)<>r.extension_id
    OR EXISTS (SELECT 1 FROM hr_contract_extension_salary d
                WHERE d.extension_id=r.extension_id AND d.is_posted<>'Y'));

/* Shared current dates may come from either renewal or extension.
   Extension history is read from HR_CONTRACT_EXTENSION, without a renewal pointer. */

/* Templates and signatories for HR review. */
SELECT template_code,template_name,is_active FROM hr_letter_template
 WHERE action_type='CONTRACT_EXTENSION' ORDER BY template_code;
SELECT signatory_code,name_en,title_en,is_active FROM hr_letter_signatory ORDER BY display_order;

/* Audit manual changes. Empty salary details are valid. */
SELECT r.extension_no,r.status,d.head_name,d.old_amount,d.new_amount,
       d.new_amount-d.old_amount AS entered_change
  FROM hr_contract_extension r JOIN hr_contract_extension_salary d ON d.extension_id=r.extension_id
 WHERE d.new_amount<>d.old_amount ORDER BY r.extension_id,d.print_order,d.slno;
