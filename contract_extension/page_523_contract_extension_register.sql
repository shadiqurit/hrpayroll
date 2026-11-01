/* PAGE 523 - CONTRACT EXTENSION REGISTER
   Normal page. Authorization CONTRACT_EXTEND_VIEW.
   Items: P523_COM_ID (required company), P523_DUE_TO (Date, DD-MON-YYYY,
   default TRUNC(SYSDATE)+90), P523_TERM_MONTHS (6/12/24, default 12),
   P523_STATUS (ALL/DRAFT/POSTED), P523_EMP_ID (Hidden, Value Protected No),
   P523_EXTENSION_ID (Hidden, Protected).
   No salary method, grade, scale or increment controls.

   Company LOV (use this same authorized-company LOV on all three pages): */
SELECT c.name d, c.id r FROM company c
 WHERE EXISTS (SELECT 1 FROM users_company uc
                WHERE uc.empid = TO_NUMBER(:USER_ID) AND uc.com_id = c.id)
 ORDER BY c.name;

/* Region: Due Employees, Interactive Report.
   Submit items P523_COM_ID,P523_DUE_TO,P523_TERM_MONTHS.
   PREPARE_ACTION: Escape Special Characters No; other columns Yes.
   Probation employees without a contract row use existing probation dates.
   Contractual employees without recorded dates use New Extension instead. */
SELECT '<button type="button" class="t-Button t-Button--small js-prepare-extension" data-emp-id="'
       || apex_escape.html_attribute(TO_CHAR(v.emp_id))
       || '">Prepare Extension</button>' AS prepare_action,
       v.employee_code, v.employee_name, v.employee_type,
       v.designation, v.department, NVL(v.grade, 'Non-grade') AS grade,
       v.current_from_date, v.current_to_date,
       TRUNC(v.current_to_date) + 1 AS proposed_from_date,
       ADD_MONTHS(TRUNC(v.current_to_date) + 1, NVL(TO_NUMBER(:P523_TERM_MONTHS), 12)) - 1 AS proposed_to_date,
       CASE WHEN TRUNC(v.current_to_date) < TRUNC(SYSDATE) THEN 'Expired'
            ELSE 'Due' END AS due_status
  FROM v_hr_contract_ext_eligible v
 WHERE v.com_id = TO_NUMBER(:P523_COM_ID)
   AND EXISTS (SELECT 1 FROM users_company uc
                WHERE uc.empid = TO_NUMBER(:USER_ID) AND uc.com_id = v.com_id)
   AND v.current_from_date IS NOT NULL
   AND TRUNC(v.current_to_date) <= NVL(TO_DATE(:P523_DUE_TO, 'DD-MON-YYYY'), TRUNC(SYSDATE)+90)
   AND NOT EXISTS (SELECT 1 FROM hr_contract_extension r WHERE r.emp_id = v.emp_id AND r.status = 'DRAFT')
 ORDER BY v.current_to_date, v.employee_code;

/* Page JavaScript, Function and Global Variable Declaration. */
apex.jQuery(document).on('click.contractExtension', '.js-prepare-extension', function () {
    apex.item('P523_EMP_ID').setValue(apex.jQuery(this).attr('data-emp-id'));
    apex.submit({ request: 'PREPARE_EXTENSION', showWait: true });
});

/* Process PREPARE_EXTENSION, After Submit, request PREPARE_EXTENSION only.
   Authorization CONTRACT_EXTEND_EDIT. */
DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM v_hr_contract_ext_eligible v
     WHERE v.emp_id = TO_NUMBER(:P523_EMP_ID) AND v.com_id = TO_NUMBER(:P523_COM_ID)
       AND v.current_from_date IS NOT NULL
       AND TRUNC(v.current_to_date) <= NVL(TO_DATE(:P523_DUE_TO, 'DD-MON-YYYY'), TRUNC(SYSDATE)+90)
       AND EXISTS (SELECT 1 FROM users_company uc
                    WHERE uc.empid = TO_NUMBER(:USER_ID) AND uc.com_id = v.com_id);
    IF l_count <> 1 THEN
        RAISE_APPLICATION_ERROR(-20750, 'Employee is not eligible in this authorized company/due list.');
    END IF;
    hrms.pkg_hr_contract_extension.create_due_extension(
        p_emp_id => TO_NUMBER(:P523_EMP_ID), p_salary_mode => 'MANUAL',
        p_term_months => NVL(TO_NUMBER(:P523_TERM_MONTHS), 12),
        p_user_id => TO_NUMBER(:USER_ID), p_extension_id => :P523_EXTENSION_ID);
END;
/* Branch to 524, clear 524:
   P524_EXTENSION_ID=&P523_EXTENSION_ID., P524_COM_ID=&P523_COM_ID.
   Success: Draft prepared. Current amounts copied unchanged. */

/* Region: Extension Register, Interactive Report.
   Submit P523_COM_ID,P523_STATUS. ENTRY_URL and LETTER_URL are link targets.
   Require session checksums on target pages/items in Page Designer; GET_URL
   generates the applicable checksum. */
SELECT apex_page.get_url(
           p_page => 524, p_clear_cache => '524',
           p_items => 'P524_EXTENSION_ID,P524_COM_ID',
           p_values => r.extension_id || ',' || e.com_id) AS entry_url,
       CASE WHEN r.status = 'POSTED' THEN apex_page.get_url(
           p_page => 525, p_clear_cache => '525',
           p_items => 'P525_EXTENSION_ID,P525_COM_ID',
           p_values => r.extension_id || ',' || e.com_id) END AS letter_url,
       r.extension_no, r.emp_code_snapshot AS employee_code,
       r.emp_name_snapshot AS employee_name,
       CASE r.emp_type_snapshot WHEN '1' THEN 'Probationary' WHEN '3' THEN 'Contractual' END AS employee_type,
       r.current_to_date, r.new_from_date, r.new_to_date,
       r.old_gross, r.new_gross, r.new_gross-r.old_gross AS manual_change,
       r.status, r.created_date, r.posted_date
  FROM hr_contract_extension r JOIN employees e ON e.id = r.emp_id
 WHERE e.com_id = TO_NUMBER(:P523_COM_ID)
   AND EXISTS (SELECT 1 FROM users_company uc
                WHERE uc.empid = TO_NUMBER(:USER_ID) AND uc.com_id = e.com_id)
   AND (:P523_STATUS IS NULL OR :P523_STATUS = 'ALL' OR r.status = :P523_STATUS)
 ORDER BY r.created_date DESC, r.extension_id DESC;

/* NEW_EXTENSION button: redirect 524, clear 524, set P524_COM_ID=&P523_COM_ID.
   Authorization CONTRACT_EXTEND_EDIT.
   Show this button so HR can record missing current contractual dates.
   Filters Change -> Refresh matching region(s). */
