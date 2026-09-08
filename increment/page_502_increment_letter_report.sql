/*
  Oracle APEX Page 502
  Region Type : Interactive Report
  Purpose     : List finalized increments and open their printable letters.

  Required page items:
    P502_COM_ID          NUMBER, required
    P502_SALARY_MONTH    NUMBER(6), required, for example 202608

  Configure PRINT_URL as a Link column:
    Link Text       : Print Increment Letter
    Target          : URL
    URL             : #PRINT_URL#
    Link Attributes : target="_blank" rel="noopener"

  Keep PRINT_URL hidden from report users. APEX_PAGE.GET_URL generates the
  checksum required by Page 503's protected items.
*/

SELECT i.increment_id,
       e.emp_id AS employee_code,
       TRIM(e.f_name || ' ' || e.l_name) AS employee_name,
       d.designation,
       dp.dept_name,
       NVL(d.grade, e.job_id) AS grade_id,
       i.due_date,
       NVL(i.revised_effective_date, i.effective_date) AS effective_date,
       i.from_step_no,
       i.to_step_no,
       i.old_basic,
       i.proposed_basic AS new_basic,
       i.increment_amount,
       i.old_gross,
       i.proposed_gross AS new_gross,
       'SALARY DONE' AS process_status,
       l.letter_id,
       l.letter_no,
       l.letter_date,
       NVL(l.status, 'NOT GENERATED') AS letter_status,
       apex_page.get_url(
           p_page        => 503,
           p_clear_cache => '503',
           p_items       => 'P503_COM_ID,P503_SALARY_MONTH,P503_INCREMENT_ID',
           p_values      => TO_CHAR(i.com_id)
                            || ',' || TO_CHAR(i.salary_month)
                            || ',' || TO_CHAR(i.increment_id)
       ) AS print_url
  FROM hr_employee_increment i
       JOIN employees e
         ON e.id = i.emp_id
       LEFT JOIN designations d
         ON d.id = e.desig_id
       LEFT JOIN departments dp
         ON dp.id = e.dept_id
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
 WHERE i.com_id = TO_NUMBER(:P502_COM_ID)
   AND i.salary_month = TO_NUMBER(:P502_SALARY_MONTH)
   AND i.status = 'POSTED'
 ORDER BY e.emp_id, i.increment_id;
