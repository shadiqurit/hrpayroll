/* ============================================================================
   PAGE 520 - DUE CONTRACTS AND ONE-CLICK RENEWAL PREPARATION

   Simple user flow:
     1. Choose due date, salary method, and renewal term.
     2. Click Prepare Renewal beside one employee.
     3. This page creates HR_CONTRACT_RENEWAL and all
        HR_CONTRACT_RENEWAL_SALARY rows.
     4. Page 521 opens with the generated master/detail record.
   ============================================================================ */

/* Page items
   -----------------------------------------------------------------------------
   P520_COM_ID          Required company select list
   P520_DUE_TO          Date Picker; default TRUNC(SYSDATE) + 90
   P520_SALARY_MODE     Radio Group; default AUTO
   P520_TERM_MONTHS     Select List; default 12
   P520_STATUS          ALL / DRAFT / POSTED; default ALL
   P520_EMP_ID          Hidden, Value Protected = No; server validated
   P520_RENEWAL_ID      Hidden, Value Protected = Yes

   P520_SALARY_MODE static LOV:
     Automatic increase;AUTO
     Manual adjustment;MANUAL

   P520_TERM_MONTHS static LOV:
     6 months;6
     12 months;12
     24 months;24

   Help text:
     AUTO   = next configured pay-scale step; configured salary heads recalculate.
     MANUAL = current step and salary copy; adjust the proposal on Page 521.
*/


/* Region: Due Employees - Interactive Report

   Set Page Items to Submit to:
     P520_COM_ID,P520_DUE_TO,P520_SALARY_MODE,P520_TERM_MONTHS

   PREPARE_ACTION is an HTML column:
     Escape Special Characters: No

   If AUTO is selected and the employee is already at the highest step,
   the button is replaced by a message asking the user to use Manual.
*/
WITH live_salary AS (
    SELECT s.employee_id,
           MAX(CASE
                   WHEN LPAD(TRIM(s.headcode), 3, '0') = '001' OR s.slno = 1
                   THEN s.amount
               END) AS current_basic,
           SUM(CASE WHEN ah.head_type = 'EARNING' THEN NVL(s.amount, 0) ELSE 0 END)
               AS current_gross
      FROM emp_salary_structure s
      JOIN allowance_head ah ON ah.head_id = s.slno
     WHERE NVL(s.is_active, 'Y') = 'Y'
     GROUP BY s.employee_id
),
due_base AS (
    SELECT c.emp_id,
           e.com_id,
           e.emp_id AS employee_code,
           TRIM(e.f_name || ' ' || e.l_name) AS employee_name,
           d.designation,
           dp.dept_name AS department,
           l.name AS location_name,
           c.contract_from_date,
           c.contract_to_date,
           NVL(c.grade_id, NVL(d.grade, e.job_id)) AS grade_id,
           c.scale_id,
           c.step_no,
           g.grade_name,
           g.grade_order,
           ls.current_basic,
           ls.current_gross
      FROM hr_employee_contract c
      JOIN employees e ON e.id = c.emp_id
      LEFT JOIN designations d ON d.id = e.desig_id
      LEFT JOIN departments dp ON dp.id = e.dept_id
      LEFT JOIN locations l ON l.id = e.loc_id
      LEFT JOIN job_grades g ON g.id = c.grade_id
      LEFT JOIN live_salary ls ON ls.employee_id = c.emp_id
     WHERE c.contract_status = 'ACTIVE'
       AND e.com_id = :P520_COM_ID
       AND NVL(e.status, 1) <> 0
       AND c.contract_to_date <= NVL(
               TO_DATE(:P520_DUE_TO, 'DD-MON-YYYY'),
               TRUNC(SYSDATE) + 90
           )
       AND NOT EXISTS (
           SELECT 1
             FROM hr_contract_renewal r
            WHERE r.emp_id = c.emp_id
              AND r.status = 'DRAFT'
       )
),
due_employee AS (
    SELECT db.*,
           (SELECT MIN(m.scale_id)
                       KEEP (
                           DENSE_RANK FIRST ORDER BY
                           CASE WHEN m.scale_id = db.scale_id THEN 0 ELSE 1 END,
                           m.revision_no DESC,
                           NVL(m.effective_from, DATE '1900-01-01') DESC,
                           m.scale_id DESC
                       )
              FROM pay_scale_master m
             WHERE m.grade_id = db.grade_id
               AND m.is_active = 'Y'
               AND (m.effective_from IS NULL
                    OR m.effective_from <= TRUNC(db.contract_to_date) + 1)
               AND (m.effective_to IS NULL
                    OR m.effective_to >= TRUNC(db.contract_to_date) + 1)
           ) AS new_scale_id
      FROM due_base db
),
due_position AS (
    SELECT de.*,
           NVL(de.scale_id, de.new_scale_id) AS current_scale_id,
           NVL(
               de.step_no,
               (SELECT COALESCE(
                           MAX(CASE
                                   WHEN sd.basic_amount <= de.current_basic
                                   THEN sd.step_no
                               END),
                           MIN(sd.step_no)
                       )
                  FROM pay_scale_detail sd
                 WHERE sd.scale_id = NVL(de.scale_id, de.new_scale_id)
               )
           ) AS current_step_no
      FROM due_employee de
),
due_ready AS (
    SELECT dp.*,
           (SELECT MIN(sd.step_no)
              FROM pay_scale_detail sd
             WHERE sd.scale_id = dp.new_scale_id
               AND sd.step_no > dp.current_step_no) AS next_step_no
      FROM due_position dp
)
SELECT CASE
           WHEN de.new_scale_id IS NULL
           THEN '<span class="u-danger-text">No active scale</span>'
           WHEN de.current_step_no IS NULL
           THEN '<span class="u-danger-text">Missing Basic/step</span>'
           WHEN NVL(:P520_SALARY_MODE, 'AUTO') = 'AUTO'
                AND de.next_step_no IS NULL
           THEN '<span class="u-danger-text">Use Manual</span>'
           WHEN NVL(:P520_SALARY_MODE, 'AUTO') = 'MANUAL'
                AND proposed_current_sd.step_no IS NULL
           THEN '<span class="u-danger-text">Step not configured</span>'
           ELSE '<button type="button" '
                || 'class="t-Button t-Button--small t-Button--hot js-prepare-renewal" '
                || 'data-emp-id="'
                || apex_escape.html_attribute(TO_CHAR(de.emp_id))
                || '"><span class="fa fa-magic" aria-hidden="true"></span> '
                || 'Prepare</button>'
       END AS prepare_action,
       de.employee_code,
       de.employee_name,
       de.designation,
       de.department,
       de.location_name,
       de.contract_from_date,
       de.contract_to_date,
       TRUNC(de.contract_to_date) + 1 AS proposed_from_date,
       ADD_MONTHS(
           TRUNC(de.contract_to_date) + 1,
           NVL(TO_NUMBER(:P520_TERM_MONTHS), 12)
       ) - 1 AS proposed_to_date,
       de.contract_to_date - TRUNC(SYSDATE) AS days_remaining,
       CASE
           WHEN de.contract_to_date < TRUNC(SYSDATE) THEN 'EXPIRED'
           WHEN de.contract_to_date <= TRUNC(SYSDATE) + 30 THEN 'DUE NOW'
           ELSE 'DUE SOON'
       END AS due_stage,
       de.grade_name,
       target_scale.revision_name AS proposed_scale,
       de.current_step_no AS current_step,
       de.current_basic,
       de.current_gross,
       CASE NVL(:P520_SALARY_MODE, 'AUTO')
           WHEN 'AUTO' THEN de.next_step_no
           ELSE de.current_step_no
       END AS proposed_step,
       CASE NVL(:P520_SALARY_MODE, 'AUTO')
           WHEN 'AUTO' THEN next_sd.basic_amount
           ELSE proposed_current_sd.basic_amount
       END AS proposed_basic,
       CASE NVL(:P520_SALARY_MODE, 'AUTO')
           WHEN 'AUTO' THEN NVL(next_sd.basic_amount, de.current_basic)
                            - NVL(de.current_basic, 0)
           ELSE 0
       END AS basic_increase,
       CASE
           WHEN de.new_scale_id IS NULL
           THEN 'No active pay scale exists for the renewal date'
           WHEN de.current_step_no IS NULL
           THEN 'Current step cannot be derived; check the Basic salary'
           WHEN NVL(:P520_SALARY_MODE, 'AUTO') = 'AUTO'
                AND de.next_step_no IS NULL
           THEN 'Maximum step reached - use Manual adjustment'
           WHEN NVL(:P520_SALARY_MODE, 'AUTO') = 'MANUAL'
                AND proposed_current_sd.step_no IS NULL
           THEN 'Current step is missing from the active scale'
           WHEN NVL(:P520_SALARY_MODE, 'AUTO') = 'AUTO'
           THEN 'Ready for automatic increase'
           ELSE 'Ready for manual adjustment'
       END AS ready_message
  FROM due_ready de
  LEFT JOIN pay_scale_master target_scale
    ON target_scale.scale_id = de.new_scale_id
  LEFT JOIN pay_scale_detail proposed_current_sd
    ON proposed_current_sd.scale_id = de.new_scale_id
   AND proposed_current_sd.step_no = de.current_step_no
  LEFT JOIN pay_scale_detail next_sd
    ON next_sd.scale_id = de.new_scale_id
   AND next_sd.step_no = de.next_step_no
 ORDER BY de.contract_to_date, de.employee_code;


/* Page process: PREPARE_RENEWAL
   Point: After Submit
   Sequence: 10
   Server-side condition: Request = PREPARE_RENEWAL
   Authorization: CONTRACT_RENEW_EDIT
*/
DECLARE
    L_ALLOWED PLS_INTEGER;
BEGIN
    IF NOT REGEXP_LIKE(NVL(:P520_EMP_ID, 'x'), '^\d+$')
       OR NOT REGEXP_LIKE(NVL(:P520_COM_ID, 'x'), '^\d+$')
    THEN
        RAISE_APPLICATION_ERROR(-20750, 'Invalid employee or company selection.');
    END IF;

    SELECT COUNT(*)
      INTO L_ALLOWED
      FROM hr_employee_contract c
      JOIN employees e ON e.id = c.emp_id
     WHERE c.emp_id = TO_NUMBER(:P520_EMP_ID)
       AND e.com_id = TO_NUMBER(:P520_COM_ID)
       AND NVL(e.status, 1) <> 0
       AND c.contract_status = 'ACTIVE'
       AND c.contract_to_date <= NVL(
               TO_DATE(:P520_DUE_TO, 'DD-MON-YYYY'),
               TRUNC(SYSDATE) + 90
           );

    IF L_ALLOWED <> 1 THEN
        RAISE_APPLICATION_ERROR(-20750, 'The selected employee is not in this due list.');
    END IF;

    hrms.pkg_hr_contract_renewal.create_due_renewal(
        p_emp_id      => TO_NUMBER(:P520_EMP_ID),
        p_salary_mode => NVL(:P520_SALARY_MODE, 'AUTO'),
        p_term_months => NVL(TO_NUMBER(:P520_TERM_MONTHS), 12),
        p_user_id     => TO_NUMBER(:USER_ID),
        p_renewal_id  => :P520_RENEWAL_ID
    );
END;

/* Success message:
   Renewal master and salary details generated. Review and final submit.

   Branch after PREPARE_RENEWAL:
     Page: 521
     Clear Cache: 521
     Set P521_RENEWAL_ID = &P520_RENEWAL_ID.
     Set P521_COM_ID     = &P520_COM_ID.
*/


/* Region: Renewal Register - Interactive Report */
SELECT apex_page.get_url(
           p_page          => 521,
           p_clear_cache   => '521',
           p_items         => 'P521_RENEWAL_ID,P521_COM_ID',
           p_values        => r.renewal_id || ',' || e.com_id,
           p_checksum_type => 'SESSION'
       ) AS entry_url,
       CASE
           WHEN r.status = 'POSTED'
           THEN apex_page.get_url(
                    p_page          => 522,
                    p_clear_cache   => '522',
                    p_items         => 'P522_RENEWAL_ID,P522_COM_ID',
                    p_values        => r.renewal_id || ',' || e.com_id,
                    p_checksum_type => 'SESSION'
                )
       END AS letter_url,
       r.renewal_no,
       r.emp_code_snapshot AS employee_code,
       r.emp_name_snapshot AS employee_name,
       r.designation_snapshot AS designation,
       r.department_snapshot AS department,
       r.current_to_date AS previous_contract_end,
       r.new_from_date,
       r.new_to_date,
       r.salary_mode,
       r.old_step_no,
       r.new_step_no,
       r.old_basic,
       r.new_basic,
       r.old_gross,
       r.new_gross,
       r.status,
       CASE r.status
           WHEN 'DRAFT' THEN 'Draft - Review'
           WHEN 'POSTED' THEN 'Final - Salary Updated'
       END AS status_label,
       r.created_date,
       r.posted_date
  FROM hr_contract_renewal r
  JOIN employees e ON e.id = r.emp_id
 WHERE e.com_id = :P520_COM_ID
   AND (:P520_STATUS IS NULL OR :P520_STATUS = 'ALL'
        OR r.status = :P520_STATUS)
 ORDER BY r.created_date DESC, r.renewal_id DESC;

/* ENTRY_URL link text:
     DRAFT  = Review
     POSTED = View

   LETTER_URL link text:
     <span class="fa fa-file-text-o" aria-hidden="true"></span> Letter

   P520_STATUS static LOV:
     All;ALL
     Draft - Review;DRAFT
     Final - Salary Updated;POSTED
*/


/* Dynamic Action: Refresh Due List
   Event: Change
   Items: P520_COM_ID,P520_DUE_TO,P520_SALARY_MODE,P520_TERM_MONTHS
   True action: Refresh the Due Employees region.
*/

/* Page JavaScript: Function and Global Variable Declaration

   The report button must submit Page 520 so the After Submit process runs.
   P520_EMP_ID is deliberately not Value Protected; the server-side process
   validates employee, company, active contract, and due date before creation.
*/
apex.jQuery(document).on('click.contractRenewal', '.js-prepare-renewal', function () {
    apex.item('P520_EMP_ID').setValue($(this).attr('data-emp-id'));
    apex.submit({
        request: 'PREPARE_RENEWAL',
        showWait: true
    });
});
