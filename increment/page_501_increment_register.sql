/*
  Oracle APEX Page 501 - Increment Register
  Region Type : Interactive Report
  Static ID   : INCREMENT_REGISTER
  Purpose     : Read-only register of every increment occurrence.

  Create these page items above the report:
    P501_COM_ID          Select List (company ID), Required = Yes
    P501_SALARY_MONTH    Select List (YYYYMM)
    P501_EMP_SEARCH      Text Field
    P501_DEPT_ID         Select List
    P501_STATUS          Select List
    P501_DECISION_CODE   Select List
    P501_DATE_FROM       Date Picker, Format Mask DD-MON-YYYY
    P501_DATE_TO         Date Picker, Format Mask DD-MON-YYYY

  P501_COM_ID must use the application's authorized-company LOV. Do not expose
  an unrestricted company LOV to users who cannot view every company.

  Suggested LOVs (set Display Null Value = Yes except for company):
    P501_SALARY_MONTH
      SELECT TO_CHAR(TO_DATE(TO_CHAR(salary_month) || '01', 'YYYYMMDD'),
                     'FMMonth YYYY', 'NLS_DATE_LANGUAGE=English') d,
             salary_month r
        FROM hr_employee_increment
       WHERE com_id = TO_NUMBER(:P501_COM_ID)
       GROUP BY salary_month
       ORDER BY salary_month DESC

    P501_DEPT_ID
      SELECT dept_name d, id r FROM departments ORDER BY dept_name

    P501_STATUS
      Draft / Review;DRAFT
      Increment Ready;READY
      Salary Applied;APPLIED
      Salary Done / Letter Ready;POSTED
      Temporary Hold;HOLD
      Punishment Delay;PUNISHMENT
      Increment Forfeited;FORFEITED
      Maximum Reached;CLOSED_NO_INCREMENT
      Reversed Before Final;REVERSED
      Processing Error;ERROR

    P501_DECISION_CODE
      Apply for Increment;READY
      Temporary Hold;TEMP_HOLD
      Punishment Delay;PUNISHMENT_DELAY
      Punishment Forfeit;PUNISHMENT_FORFEIT
      EB Hold;EB_HOLD
      Maximum Reached;MAX_REACHED

  Add every item above to the report region's "Page Items to Submit" property.
  On item Change, use one Dynamic Action to Refresh INCREMENT_REGISTER.

  Configure LETTER_CENTER_URL as a Link column:
    Link Text       : Letter Center
    Target          : URL
    URL             : #LETTER_CENTER_URL#

  Configure PRINT_URL as a Link column:
    Link Text       : Print Letter
    Target          : URL
    URL             : #PRINT_URL#
    Link Attributes : target="_blank" rel="noopener"

  Set both URL columns to Type = Link so the raw URL is never displayed as
  report text. The links are returned only for POSTED rows and
  APEX_PAGE.GET_URL adds the checksum required by the protected target items.

  Page authorization: INC_VIEW
  Report editing     : Disabled (the register is permanently read-only)
  APEX source paste  : Omit the final semicolon.
*/

SELECT i.increment_id,
       i.com_id,
       c.code AS company_code,
       c.name AS company_name,
       i.emp_id AS employee_pk,
       e.emp_id AS employee_id,
       NVL(e.empno, e.emp_id) AS employee_code,
       TRIM(e.f_name || ' ' || e.l_name) AS employee_name,
       d.designation,
       dp.dept_name,
       loc.name AS location_name,
       NVL(g.grade_code, g.grade_name) AS grade_name,
       i.original_list_date,
       i.current_list_date,
       i.salary_month,
       TO_CHAR(
           TO_DATE(TO_CHAR(i.salary_month) || '01', 'YYYYMMDD'),
           'FMMonth YYYY',
           'NLS_DATE_LANGUAGE=English'
       ) AS salary_month_name,
       CASE
           WHEN i.current_list_date = i.original_list_date THEN 'NEW DUE'
           ELSE 'CARRY FORWARD'
       END AS list_source,
       i.due_date AS consideration_date,
       i.effective_date AS original_effective_date,
       i.revised_effective_date,
       NVL(i.revised_effective_date, i.effective_date) AS payable_effective_date,
       i.old_basic,
       i.proposed_basic AS new_basic,
       i.increment_amount,
       i.old_gross,
       i.proposed_gross AS new_gross,
       CASE
           WHEN i.proposed_gross IS NOT NULL
           THEN i.proposed_gross - NVL(i.old_gross, 0)
       END AS gross_increase,
       i.scale_id,
       i.from_step_no,
       i.to_step_no,
       i.total_steps,
       CASE
           WHEN i.decision_code = 'EB_HOLD' THEN 'EB HOLD'
           WHEN i.scale_id IS NULL THEN 'NO SCALE'
           WHEN i.to_step_no IS NULL THEN 'NOT CALCULATED'
           WHEN i.to_step_no >= NVL(i.total_steps, 25) THEN 'MAX STEP'
           WHEN i.to_step_no = ps.steps_before_eb THEN 'EB STEP'
           WHEN i.to_step_no < ps.steps_before_eb THEN 'PRE-EB'
           ELSE 'POST-EB'
       END AS scale_position,
       i.decision_code,
       i.status AS database_status,
       CASE i.status
           WHEN 'DRAFT'               THEN 'Draft / Review'
           WHEN 'READY'               THEN 'Increment Ready'
           WHEN 'APPLIED'             THEN 'Salary Applied'
           WHEN 'POSTED'              THEN 'Salary Done / Letter Ready'
           WHEN 'HOLD'                THEN 'Temporary Hold'
           WHEN 'PUNISHMENT'          THEN 'Punishment Delay'
           WHEN 'FORFEITED'           THEN 'Increment Forfeited'
           WHEN 'CLOSED_NO_INCREMENT' THEN 'Maximum Reached'
           WHEN 'REVERSED'            THEN 'Reversed Before Final'
           WHEN 'ERROR'               THEN 'Processing Error'
           ELSE INITCAP(REPLACE(i.status, '_', ' '))
       END AS process_status,
       i.hold_type,
       i.hold_reason,
       i.hold_review_date,
       i.punishment_ref_no,
       i.change_reason,
       i.remarks,
       i.created_by,
       i.created_date,
       i.applied_by,
       i.applied_date,
       i.posted_by,
       i.posted_date,
       i.updated_by,
       i.updated_date,
       i.action_id,
       a.action_date,
       a.approval_status AS action_approval_status,
       a.approved_by AS action_approved_by,
       a.approved_date AS action_approved_date,
       i.reverse_action_id,
       ra.action_type AS reverse_action_type,
       i.reversed_by,
       i.reversed_date,
       i.reversal_reason,
       (
           SELECT COUNT(*)
             FROM emp_salary_structure_hist h
            WHERE h.action_id = i.action_id
              AND h.emp_id = i.emp_id
       ) AS salary_history_rows,
       l.letter_id,
       l.letter_no,
       l.letter_date,
       NVL(l.status, 'NOT GENERATED') AS letter_status,
       CASE
           WHEN i.status = 'POSTED' THEN
               apex_page.get_url(
                   p_page        => 502,
                   p_clear_cache => '502',
                   p_items       => 'P502_COM_ID,P502_SALARY_MONTH',
                   p_values      => TO_CHAR(i.com_id)
                                    || ',' || TO_CHAR(i.salary_month)
               )
       END AS letter_center_url,
       CASE
           WHEN i.status = 'POSTED' THEN
               apex_page.get_url(
                   p_page        => 503,
                   p_clear_cache => '503',
                   p_items       => 'P503_COM_ID,P503_SALARY_MONTH,P503_INCREMENT_ID',
                   p_values      => TO_CHAR(i.com_id)
                                    || ',' || TO_CHAR(i.salary_month)
                                    || ',' || TO_CHAR(i.increment_id)
               )
       END AS print_url
  FROM hr_employee_increment i
       JOIN employees e
         ON e.id = i.emp_id
       JOIN company c
         ON c.id = i.com_id
       LEFT JOIN departments dp
         ON dp.id = e.dept_id
       LEFT JOIN designations d
         ON d.id = e.desig_id
       LEFT JOIN locations loc
         ON loc.id = e.loc_id
       LEFT JOIN pay_scale_master ps
         ON ps.scale_id = i.scale_id
       LEFT JOIN job_grades g
         ON g.id = ps.grade_id
       LEFT JOIN hr_employee_action a
         ON a.action_id = i.action_id
       LEFT JOIN hr_employee_action ra
         ON ra.action_id = i.reverse_action_id
       LEFT JOIN (
           SELECT letter_id,
                  action_id,
                  letter_no,
                  letter_date,
                  status
             FROM (
                 SELECT el.letter_id,
                        el.action_id,
                        el.letter_no,
                        el.letter_date,
                        el.status,
                        ROW_NUMBER() OVER (
                            PARTITION BY el.action_id
                            ORDER BY el.letter_id DESC
                        ) AS rn
                   FROM hr_employee_letter el
                  WHERE el.status <> 'CANCELLED'
             )
            WHERE rn = 1
       ) l
         ON l.action_id = i.action_id
 WHERE i.com_id = TO_NUMBER(:P501_COM_ID)
   AND (
       :P501_SALARY_MONTH IS NULL
       OR i.salary_month = TO_NUMBER(:P501_SALARY_MONTH)
   )
   AND (:P501_DEPT_ID IS NULL OR e.dept_id = TO_NUMBER(:P501_DEPT_ID))
   AND (:P501_STATUS IS NULL OR i.status = :P501_STATUS)
   AND (
       :P501_DECISION_CODE IS NULL
       OR i.decision_code = :P501_DECISION_CODE
   )
   AND (
       :P501_DATE_FROM IS NULL
       OR TRUNC(NVL(i.posted_date, NVL(i.applied_date, i.created_date))) >=
          TO_DATE(:P501_DATE_FROM, 'DD-MON-YYYY', 'NLS_DATE_LANGUAGE=English')
   )
   AND (
       :P501_DATE_TO IS NULL
       OR TRUNC(NVL(i.posted_date, NVL(i.applied_date, i.created_date))) <=
          TO_DATE(:P501_DATE_TO, 'DD-MON-YYYY', 'NLS_DATE_LANGUAGE=English')
   )
   AND (
       :P501_EMP_SEARCH IS NULL
       OR UPPER(
              e.emp_id || ' ' || NVL(e.empno, '') || ' '
              || TRIM(e.f_name || ' ' || e.l_name)
          ) LIKE '%' || UPPER(TRIM(:P501_EMP_SEARCH)) || '%'
   )
 ORDER BY i.due_date DESC, e.emp_id, i.increment_id DESC;
