/* SIMPLE CONTRACT RENEWAL - POST-INSTALL CHECKS */

/* 1. Compilation - this should return no rows. */
SELECT name, type, line, position, text
  FROM user_errors
 WHERE name IN ('PKG_HR_CONTRACT_RENEWAL', 'TRG_HR_CONTRACT_RENEWAL_NO')
 ORDER BY name, sequence;

/* 2. Required objects */
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name IN (
       'HR_EMPLOYEE_CONTRACT',
       'HR_CONTRACT_RENEWAL',
       'HR_CONTRACT_RENEWAL_SALARY',
       'HR_CONTRACT_RENEW_RECIPIENT',
       'PKG_HR_CONTRACT_RENEWAL'
 )
 ORDER BY object_type, object_name;

/* 3. Letter setup */
SELECT signatory_id, signatory_code, name_bn, title_bn, is_active
  FROM hr_letter_signatory
 ORDER BY display_order;

SELECT template_id, template_code, template_name, is_active
  FROM hr_letter_template
 WHERE action_type = 'CONTRACT_RENEWAL'
   AND template_code IN ('CONTRACT_RENEWAL_EN', 'CONTRACT_RENEWAL_BN')
 ORDER BY template_code;

/* 4. Current contractual employees shown by Page 520 */
SELECT c.emp_id, e.emp_id employee_code,
       c.contract_from_date, c.contract_to_date,
       c.grade_id, c.scale_id, c.step_no, c.contract_status
  FROM hr_employee_contract c
  JOIN employees e ON e.id = c.emp_id
 WHERE c.contract_status <> 'CLOSED'
 ORDER BY c.contract_to_date, e.emp_id;

/* 5. Drafts and final renewals */
SELECT r.renewal_no, r.emp_code_snapshot, r.emp_name_snapshot,
       r.status, r.salary_mode, r.new_from_date, r.new_to_date,
       r.old_step_no, r.new_step_no,
       r.old_basic, r.new_basic, r.old_gross, r.new_gross,
       r.action_id, r.letter_id
  FROM hr_contract_renewal r
 ORDER BY r.created_date DESC;

/* 6. Every posted renewal must have an action, issued letter, and current
   contract pointer. This query should return no rows. */
SELECT r.renewal_id, r.renewal_no,
       r.action_id, r.letter_id,
       l.status letter_status,
       c.latest_renewal_id
  FROM hr_contract_renewal r
  LEFT JOIN hr_employee_letter l ON l.letter_id = r.letter_id
  LEFT JOIN hr_employee_contract c ON c.emp_id = r.emp_id
 WHERE r.status = 'POSTED'
   AND (r.action_id IS NULL
        OR r.letter_id IS NULL
        OR l.status <> 'ISSUED'
        OR c.latest_renewal_id <> r.renewal_id);

/* 7. Every renewal master must have salary detail, including exactly one
   Basic row. This query should return no rows. */
SELECT r.renewal_id, r.renewal_no,
       COUNT(d.renewal_salary_id) AS detail_count,
       COUNT(CASE
                 WHEN LPAD(TRIM(d.headcode), 3, '0') = '001' OR d.slno = 1
                 THEN 1
             END) AS basic_count
  FROM hr_contract_renewal r
  LEFT JOIN hr_contract_renewal_salary d ON d.renewal_id = r.renewal_id
 GROUP BY r.renewal_id, r.renewal_no
HAVING COUNT(d.renewal_salary_id) = 0
    OR COUNT(CASE
                 WHEN LPAD(TRIM(d.headcode), 3, '0') = '001' OR d.slno = 1
                 THEN 1
             END) <> 1;

/* 8. AUTO drafts must propose a higher configured step. This query should
   return no rows. */
SELECT renewal_id, renewal_no, emp_code_snapshot,
       old_step_no, new_step_no
  FROM hr_contract_renewal
 WHERE salary_mode = 'AUTO'
   AND new_step_no <= old_step_no;

/* UAT:
   A. Prepare an AUTO renewal from Page 520 and verify master/detail creation.
   B. Prepare a MANUAL renewal and edit one allowance on Page 521.
   C. Final Submit on/after the effective date.
   D. Verify salary, current contract, employee action and issued letter.
   E. Change live salary after creating a test draft; Final Submit must reject
      it until Refresh Salary is used and the proposal is reviewed again.
   F. Verify a POSTED renewal cannot be edited, deleted or posted again.
   G. Verify an EXPIRED contract appears on Page 520 and can be renewed.
   H. Verify a CLOSED contract is absent from Page 520 and cannot be renewed.
   I. Verify grade 1-14 uses CONTRACT_RENEWAL_EN and English output.
   J. Verify grade 16-20 uses CONTRACT_RENEWAL_BN and Bangla output.
   K. Verify grade 15 is rejected because no language range was specified.
*/
