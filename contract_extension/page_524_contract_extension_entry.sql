/* PAGE 524 - NEW CONTRACT EXTENSION
   Normal BLANK page, authorization CONTRACT_EXTEND_EDIT.
   ONE Static Content region: Contract Extension.
   Do not create an automatic database form or automatic row DML process.

   Visible items, in this order:
   P524_EMP_ID          Popup LOV, required, label Employee.
   P524_EMP_NAME        Display Only, label Employee name.
   P524_CURRENT_TO_DATE Display Only, label Current confirmation due date.
                       Save session state / Send on Page Submit = Yes.
   P524_NEW_TO_DATE     Date Picker, required, label Extended confirmation due date.
   P524_REASON          Textarea, required, maximum 1000, label Reason.
   P524_SIGNATORY_ID    Select List, required, label Letter signatory.

   Hidden items: P524_COM_ID, P524_EXTENSION_ID (Value Protected Yes).
   P524_EXTENSION_ID starts null; never pass an existing extension to this page.
   All dates use DD-MON-YYYY. No start dates, salary, grade, status, remarks,
   draft buttons or approval controls.

   Buttons:
   SAVE_EXTENSION (label Save Extension), Submit Page, Show Processing Yes.
       Authorization CONTRACT_EXTEND_POST. Enable normal required-item validations.
   CANCEL, Redirect to Page 523, Clear Cache 523,
       Set P523_COM_ID = &P524_COM_ID.; no submit/validations.

   Employee Popup LOV; Items to Submit P524_COM_ID. */
SELECT v.employee_code || ' - ' || v.employee_name d, v.emp_id r
  FROM v_hr_contract_ext_eligible v
 WHERE v.com_id = TO_NUMBER(:P524_COM_ID)
   AND EXISTS (SELECT 1 FROM users_company uc
                WHERE uc.empid = TO_NUMBER(:USER_ID) AND uc.com_id = v.com_id)
   AND NOT EXISTS (SELECT 1 FROM hr_contract_extension r
                    WHERE r.emp_id = v.emp_id AND r.status = 'DRAFT')
 ORDER BY v.employee_code;

/* Dynamic Action LOAD_EMPLOYEE:
   Event Change, Item P524_EMP_ID, Fire on Initialization No.
   True Action Execute Server-side Code; Wait for Result Yes.
   Items to Submit: P524_EMP_ID,P524_COM_ID.
   Items to Return: P524_EMP_NAME,P524_CURRENT_TO_DATE,P524_NEW_TO_DATE.
   Leave the new date blank so HR explicitly chooses the extended date. */
BEGIN
    :P524_EMP_NAME := NULL;
    :P524_CURRENT_TO_DATE := NULL;
    :P524_NEW_TO_DATE := NULL;
    IF :P524_EMP_ID IS NOT NULL THEN
        SELECT v.employee_name,
               TO_CHAR(v.current_to_date, 'DD-MON-YYYY', 'NLS_DATE_LANGUAGE=English')
          INTO :P524_EMP_NAME, :P524_CURRENT_TO_DATE
          FROM v_hr_contract_ext_eligible v
         WHERE v.emp_id = TO_NUMBER(:P524_EMP_ID)
           AND v.com_id = TO_NUMBER(:P524_COM_ID)
           AND EXISTS (SELECT 1 FROM users_company uc
                        WHERE uc.empid = TO_NUMBER(:USER_ID) AND uc.com_id = v.com_id);
    END IF;
END;

/* P524_SIGNATORY_ID LOV. */
SELECT name_en || ' - ' || title_en d, signatory_id r
  FROM hr_letter_signatory
 WHERE is_active = 'Y'
 ORDER BY display_order, name_en;

/* P524_SIGNATORY_ID Default: Type SQL Query (single value).
   Default the first active signatory, so HR can normally leave it as-is. */
SELECT MIN(signatory_id) KEEP (DENSE_RANK FIRST ORDER BY display_order,signatory_id)
  FROM hr_letter_signatory WHERE is_active = 'Y';

/* Process SAVE_EXTENSION, Type Execute Code, Point Processing, Sequence 10.
   When Button Pressed SAVE_EXTENSION; Authorization CONTRACT_EXTEND_POST.
   Success Message: Extension saved. Select Print Letter from the list.
   One call updates the confirmation due date and writes history/letter together.
   No COMMIT and no swallowed exceptions: let APEX roll back a failed request. */
DECLARE
    l_count PLS_INTEGER;
    l_letter_id NUMBER;
BEGIN
    IF NOT apex_authorization.is_authorized('CONTRACT_EXTEND_EDIT')
       OR NOT apex_authorization.is_authorized('CONTRACT_EXTEND_POST') THEN
        RAISE_APPLICATION_ERROR(-20751, 'You are not authorized to save an extension.');
    END IF;
    IF :P524_EXTENSION_ID IS NOT NULL THEN
        RAISE_APPLICATION_ERROR(-20719, 'This extension was already saved. Open a new entry from the list.');
    END IF;
    SELECT COUNT(*) INTO l_count
      FROM v_hr_contract_ext_eligible v
     WHERE v.emp_id = TO_NUMBER(:P524_EMP_ID)
       AND v.com_id = TO_NUMBER(:P524_COM_ID)
       AND EXISTS (SELECT 1 FROM users_company uc
                    WHERE uc.empid = TO_NUMBER(:USER_ID) AND uc.com_id = v.com_id);
    IF l_count <> 1 THEN
        RAISE_APPLICATION_ERROR(-20751, 'Choose an eligible employee in your authorized company.');
    END IF;
    hrms.pkg_hr_contract_extension.extend_confirmation_date(
        p_emp_id => TO_NUMBER(:P524_EMP_ID),
        p_expected_due_date => TO_DATE(:P524_CURRENT_TO_DATE, 'DD-MON-YYYY', 'NLS_DATE_LANGUAGE=English'),
        p_new_due_date => TO_DATE(:P524_NEW_TO_DATE, 'DD-MON-YYYY', 'NLS_DATE_LANGUAGE=English'),
        p_reason => :P524_REASON,
        p_user_id => TO_NUMBER(:USER_ID),
        p_extension_id => :P524_EXTENSION_ID,
        p_letter_id => l_letter_id,
        p_signatory_id => TO_NUMBER(:P524_SIGNATORY_ID));
END;

/* Branch AFTER processing, When Button Pressed SAVE_EXTENSION:
   Page 523; Clear Cache 523,524; Set P523_COM_ID = &P524_COM_ID.
   Return to the list only after successful validation and processing.

   Migration: remove ALL old Page 524 processes/branches/buttons/DA code before
   adding this setup: CREATE_DRAFT, VALIDATE_AND_LOCK, salary grid DML,
   SAVE_HEADER, FINAL_SUBMIT, REFRESH_SALARY, DELETE_DRAFT and old record loading.
   Remove all old items except those explicitly listed above.
   There is one user action: Save Extension. Internal legacy draft APIs are
   retained only for database compatibility and are not part of this page. */
