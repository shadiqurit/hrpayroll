/* ============================================================================
   PAGE 520 - CONTRACT RENEWAL LIST

   This file contains region sources and link definitions. It is not an APEX
   application export. Build the page as described in README.md.
   ============================================================================ */

/* --------------------------------------------------------------------------
   Region: KPI Cards
   Type: Cards (one row per card)
   -------------------------------------------------------------------------- */
SELECT 'DUE_30' card_code,
       'Due in 30 Days' card_title,
       COUNT(*) card_value,
       'fa-calendar-clock' card_icon,
       apex_page.get_url(
           p_page   => 520,
           p_items  => 'P520_VIEW_MODE',
           p_values => 'DUE'
       ) card_link
  FROM hr_employee_contract c
  JOIN employees e ON e.id = c.emp_id
 WHERE c.contract_status = 'ACTIVE'
   AND c.contract_to_date BETWEEN TRUNC(SYSDATE) AND TRUNC(SYSDATE) + 30
   AND (:P520_COM_ID IS NULL OR e.com_id = :P520_COM_ID)
UNION ALL
SELECT 'SUBMITTED', 'Pending Approval', COUNT(*), 'fa-user-check',
       apex_page.get_url(p_page => 520,
                         p_items => 'P520_STATUS', p_values => 'SUBMITTED')
  FROM hr_contract_renewal r
  JOIN employees e ON e.id = r.emp_id
 WHERE r.approval_status = 'SUBMITTED'
   AND (:P520_COM_ID IS NULL OR e.com_id = :P520_COM_ID)
UNION ALL
SELECT 'APPROVED', 'Approved / Final Pending', COUNT(*), 'fa-file-check',
       apex_page.get_url(p_page => 520,
                         p_items => 'P520_STATUS', p_values => 'APPROVED')
  FROM hr_contract_renewal r
  JOIN employees e ON e.id = r.emp_id
 WHERE r.approval_status = 'APPROVED'
   AND (:P520_COM_ID IS NULL OR e.com_id = :P520_COM_ID)
UNION ALL
SELECT 'POSTED', 'Salary Updated', COUNT(*), 'fa-circle-check',
       apex_page.get_url(p_page => 520,
                         p_items => 'P520_STATUS', p_values => 'POSTED')
  FROM hr_contract_renewal r
  JOIN employees e ON e.id = r.emp_id
 WHERE r.approval_status = 'POSTED'
   AND (:P520_COM_ID IS NULL OR e.com_id = :P520_COM_ID);


/* --------------------------------------------------------------------------
   Region: Contracts Due for Renewal
   Type: Interactive Report
   Show when P520_VIEW_MODE is ALL or DUE.
   The link opens Page 521 in create mode with the employee preselected.
   -------------------------------------------------------------------------- */
SELECT apex_page.get_url(
           p_page        => 521,
           p_clear_cache => '521',
           p_items       => 'P521_EMP_ID,P521_COM_ID',
           p_values      => c.emp_id || ',' || e.com_id
       ) AS create_url,
       e.emp_id AS employee_code,
       TRIM(e.f_name || ' ' || e.l_name) AS employee_name,
       d.designation,
       dp.dept_name AS department,
       l.name AS location_name,
       c.contract_from_date,
       c.contract_to_date,
       c.contract_to_date - TRUNC(SYSDATE) AS days_remaining,
       g.grade_name,
       g.grade_order,
       c.step_no,
       CASE
           WHEN c.contract_to_date < TRUNC(SYSDATE) THEN 'EXPIRED'
           WHEN c.contract_to_date <= TRUNC(SYSDATE) + 30 THEN 'DUE NOW'
           WHEN c.contract_to_date <= TRUNC(SYSDATE) + 90 THEN 'DUE SOON'
           ELSE 'FUTURE'
       END AS due_stage
  FROM hr_employee_contract c
  JOIN employees e ON e.id = c.emp_id
  LEFT JOIN designations d ON d.id = e.desig_id
  LEFT JOIN departments dp ON dp.id = e.dept_id
  LEFT JOIN locations l ON l.id = e.loc_id
  LEFT JOIN job_grades g ON g.id = c.grade_id
 WHERE c.contract_status = 'ACTIVE'
   AND c.contract_to_date <= NVL(
           TO_DATE(:P520_DUE_TO, 'DD-MON-YYYY'),
           TRUNC(SYSDATE) + 90
       )
   AND (:P520_COM_ID IS NULL OR e.com_id = :P520_COM_ID)
   AND NOT EXISTS (
       SELECT 1
         FROM hr_contract_renewal r
        WHERE r.emp_id = c.emp_id
          AND r.approval_status IN ('DRAFT', 'SUBMITTED', 'APPROVED')
   )
 ORDER BY c.contract_to_date, e.emp_id;

/* Create link column:
   Target = #CREATE_URL#
   Link text = <span class="fa fa-plus" aria-hidden="true"></span> Renew
   Escape Special Characters = No
   Authorization = CONTRACT_RENEW_CREATE
*/


/* --------------------------------------------------------------------------
   Region: Renewal Register
   Type: Interactive Report
   -------------------------------------------------------------------------- */
SELECT apex_page.get_url(
           p_page        => 521,
           p_clear_cache => '521',
           p_items       => 'P521_RENEWAL_ID,P521_COM_ID',
           p_values      => r.renewal_id || ',' || e.com_id
       ) AS entry_url,
       CASE
           WHEN r.approval_status IN ('APPROVED', 'POSTED')
           THEN apex_page.get_url(
                    p_page        => 522,
                    p_clear_cache => '522',
                    p_items       => 'P522_RENEWAL_ID,P522_COM_ID',
                    p_values      => r.renewal_id || ',' || e.com_id
                )
       END AS letter_url,
       r.renewal_id,
       r.renewal_no,
       r.emp_code_snapshot AS employee_code,
       r.emp_name_snapshot AS employee_name,
       r.designation_snapshot AS designation,
       r.department_snapshot AS department,
       r.current_from_date,
       r.current_to_date,
       r.new_from_date,
       r.new_to_date,
       r.grade_snapshot AS grade_no,
       r.pay_scale_snapshot AS pay_scale,
       r.old_basic,
       r.new_basic,
       r.old_gross,
       r.new_gross,
       r.new_gross - r.old_gross AS gross_change,
       r.approval_status,
       CASE r.approval_status
           WHEN 'DRAFT' THEN 'Draft'
           WHEN 'SUBMITTED' THEN 'Pending Approval'
           WHEN 'APPROVED' THEN 'Letter Ready / Final Pending'
           WHEN 'POSTED' THEN 'Salary Updated / Final'
           WHEN 'CANCELLED' THEN 'Cancelled'
       END AS stage_label,
       r.prepared_date,
       r.submitted_date,
       r.approved_date,
       r.posted_date
  FROM hr_contract_renewal r
  JOIN employees e ON e.id = r.emp_id
 WHERE (:P520_COM_ID IS NULL OR e.com_id = :P520_COM_ID)
   AND (:P520_STATUS IS NULL OR :P520_STATUS = 'ALL'
        OR r.approval_status = :P520_STATUS)
   AND (:P520_FROM_DATE IS NULL
        OR r.new_from_date >= TO_DATE(:P520_FROM_DATE, 'DD-MON-YYYY'))
   AND (:P520_TO_DATE IS NULL
        OR r.new_from_date <= TO_DATE(:P520_TO_DATE, 'DD-MON-YYYY'))
 ORDER BY r.created_date DESC, r.renewal_id DESC;

/* ENTRY_URL link text:
     <span class="fa fa-edit" aria-hidden="true"></span>
   LETTER_URL link text:
     <span class="fa fa-file-pdf-o" aria-hidden="true"></span>
   Set both URL columns to Escape Special Characters = No and URL type Link.
   Hide RENEWAL_ID.
*/


/* --------------------------------------------------------------------------
   P520_STATUS static LOV
   --------------------------------------------------------------------------
   All;ALL
   Draft;DRAFT
   Pending Approval;SUBMITTED
   Approved / Final Pending;APPROVED
   Posted / Salary Updated;POSTED
   Cancelled;CANCELLED
*/

/* NEW_RENEWAL button target:
   Page 521, Clear Cache 521,
   Set P521_COM_ID = &P520_COM_ID.
   Use a session-level checksum because P521_COM_ID is protected.
*/
