/* PAGE 523 - CONTRACT EXTENSION LIST
   Normal page; authorization CONTRACT_EXTEND_VIEW.
   This page contains ONE report and ONE New Extension button.

   Item P523_COM_ID: required company Select List, submit page on change.
   Use the same numeric authenticated USER_ID as the rest of the HR application.
   Company LOV: */
SELECT c.name d, c.id r
  FROM company c
 WHERE EXISTS (SELECT 1 FROM users_company uc
                WHERE uc.empid = TO_NUMBER(:USER_ID) AND uc.com_id = c.id)
 ORDER BY c.name;

/* Region: Extensions, Interactive Report; Static ID extension_list.
   SQL Query below. Page Items to Submit: P523_COM_ID.
   Only saved/posted extensions appear. No due list, drafts, term-month selector,
   Prepare action, salary columns or editable report columns.

   PRINT_URL: column type Link; Target URL #PRINT_URL#; Link Text Print Letter.
   Escape ordinary text columns, including employee name and reason.
   Show the two date columns as DD-MON-YYYY. Hide PRINT_URL's raw value.
   Additional report sorting/filtering can use the normal report search bar. */
SELECT r.extension_no,
       r.emp_code_snapshot AS employee_code,
       r.emp_name_snapshot AS employee_name,
       r.current_to_date AS previous_confirmation_due_date,
       r.new_to_date AS extended_confirmation_due_date,
       r.reason,
       r.posted_date AS recorded_date,
       r.posted_by AS recorded_by,
       apex_page.get_url(
           p_page => 525, p_clear_cache => '525',
           p_items => 'P525_EXTENSION_ID,P525_COM_ID',
           p_values => r.extension_id || ',' || e.com_id) AS print_url
  FROM hr_contract_extension r
  JOIN employees e ON e.id = r.emp_id
 WHERE r.status = 'POSTED'
   AND e.com_id = TO_NUMBER(:P523_COM_ID)
   AND EXISTS (SELECT 1 FROM users_company uc
                WHERE uc.empid = TO_NUMBER(:USER_ID) AND uc.com_id = e.com_id)
 ORDER BY r.posted_date DESC, r.extension_id DESC;

/* NEW_EXTENSION button, label New Extension, authorization CONTRACT_EXTEND_EDIT.
   Action: Redirect to Page in this Application.
   Page 524; Clear Cache 524; Set P524_COM_ID = &P523_COM_ID.
   Require P523_COM_ID to be selected (hide button if it is null).
   Page links must carry session checksums. Do not build f?p links manually.

   Migration: remove old Due Employees report, P523_DUE_TO/P523_TERM_MONTHS/
   P523_STATUS/P523_EMP_ID/P523_EXTENSION_ID and PREPARE_EXTENSION process/JS.
   Remove old entry/edit links. Existing POSTED history remains printable. */
