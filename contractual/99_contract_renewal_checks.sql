/* ============================================================================
   CONTRACT RENEWAL - POST-INSTALL AND UAT CHECKS
   Read-only except for the deliberately commented sample API calls.
   ============================================================================ */

/* 1. Compilation */
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
       'HR_CONTRACT_RENEWAL_AUDIT',
       'HR_CONTRACT_RENEW_RECIPIENT',
       'PKG_HR_CONTRACT_RENEWAL'
 )
 ORDER BY object_type, object_name;

/* 3. Letter configuration. Verify the real names/titles before production. */
SELECT signatory_id, signatory_code, name_bn, title_bn, is_active
  FROM hr_letter_signatory
 ORDER BY display_order;

SELECT template_id, template_code, template_name, action_type, is_active
  FROM hr_letter_template
 WHERE action_type = 'CONTRACT_RENEWAL';

SELECT letter_recipient_id, recipient_code,
       recipient_name_bn, display_order, is_active
  FROM hr_letter_recipient
 WHERE recipient_code IN (
       'MD_BOARD_INFO', 'ADMIN_CIVIL', 'ACCOUNTS_PAYROLL',
       'PERSONAL_FILE', 'OFFICE_COPY'
 )
 ORDER BY display_order;

/* 4. Current-contract baseline completeness.
   Employees absent here cannot appear in the Page 520 due list. Their first
   Page 521 draft can create the baseline after HR enters current term details. */
SELECT c.emp_id, e.emp_id employee_code,
       c.contract_from_date, c.contract_to_date,
       c.grade_id, c.scale_id, c.step_no, c.contract_status
  FROM hr_employee_contract c
  JOIN employees e ON e.id = c.emp_id
 ORDER BY c.contract_to_date, e.emp_id;

/* 5. Open workflow and salary variance */
SELECT r.renewal_no, r.emp_code_snapshot, r.emp_name_snapshot,
       r.approval_status, r.new_from_date, r.new_to_date,
       r.old_basic, r.new_basic, r.old_gross, r.new_gross,
       r.new_gross - r.old_gross gross_change
  FROM hr_contract_renewal r
 WHERE r.approval_status IN ('DRAFT', 'SUBMITTED', 'APPROVED')
 ORDER BY r.created_date;

/* 6. Final consistency: posted renewals must have action, issued letter, and
   a current-contract pointer. This query should return zero rows. */
SELECT r.renewal_id, r.renewal_no,
       r.action_id, r.letter_id,
       l.status letter_status,
       c.latest_renewal_id
  FROM hr_contract_renewal r
  LEFT JOIN hr_employee_letter l ON l.letter_id = r.letter_id
  LEFT JOIN hr_employee_contract c ON c.emp_id = r.emp_id
 WHERE r.approval_status = 'POSTED'
   AND (r.action_id IS NULL
        OR r.letter_id IS NULL
        OR l.status <> 'ISSUED'
        OR c.latest_renewal_id <> r.renewal_id);

/* 7. Audit trail */
SELECT r.renewal_no, a.event_type, a.from_status, a.to_status,
       a.event_remarks, a.event_by, a.event_date
  FROM hr_contract_renewal_audit a
  JOIN hr_contract_renewal r ON r.renewal_id = a.renewal_id
 ORDER BY a.audit_id;

/* UAT sequence (execute from Page 521, not directly in production):
   A. Create draft; verify salary snapshot and Basic from selected scale/step.
   B. Change one allowance; save; confirm old/new totals.
   C. Submit; confirm grids and header become read-only.
   D. Approve; verify Page 522 exists and has pending-final watermark.
   E. Return to draft; verify the old letter is cancelled, then resubmit/approve.
   F. Before final, alter a live salary in a test transaction; final submit must
      reject stale data. Roll back the test change and refresh/reapprove.
   G. Final submit on/after effective date; verify salary, contract, action,
      letter status, and audit row change in one transaction.
   H. Double-click approve/final; the second request must be rejected by status.
*/

