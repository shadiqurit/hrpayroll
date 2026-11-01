/* PAGE 524 - CONTRACT EXTENSION ENTRY
   Normal page, authorization CONTRACT_EXTEND_VIEW.
   No approval workflow. DRAFT -> POSTED.

   Hidden, Protected: P524_EXTENSION_ID,P524_COM_ID,P524_VERSION_NO,
                     P524_ACTION_ID,P524_LETTER_ID.
   New record: P524_EMP_ID (required employee Popup LOV),
               P524_CURRENT_FROM_DATE,P524_CURRENT_TO_DATE (date pickers).
   Draft: P524_NEW_TO_DATE (required date picker),
          P524_REASON,P524_REMARKS (text, max 1000),
          P524_SPECIAL_TERMS (Textarea, max 4000), P524_SIGNATORY_ID.
   Display: P524_NEW_FROM_DATE (date, saved session state),
            P524_EXTENSION_NO,P524_STATUS,P524_EMP_NAME,P524_EMP_TYPE,
            P524_GRADE,P524_OLD_BASIC,P524_NEW_BASIC,P524_OLD_GROSS,P524_NEW_GROSS.
   Existing record: employee/current dates read-only; all items read-only when POSTED.
   All date items use DD-MON-YYYY. Additional terms are plain text.

   Buttons:
   CREATE_DRAFT (new), SAVE_DRAFT (draft), FINAL_SUBMIT (draft),
   REFRESH_SALARY (draft), DELETE_DRAFT (draft), VIEW_LETTER (posted), BACK.
   Write buttons/processes: CONTRACT_EXTEND_EDIT; Final: CONTRACT_EXTEND_POST.
   Do not use automatic form DML or automatic table grid DML.

   Employee LOV: */
SELECT v.employee_code || ' - ' || v.employee_name || ' (' || v.employee_type || ')' d, v.emp_id r
  FROM v_hr_contract_ext_eligible v
 WHERE v.com_id = TO_NUMBER(:P524_COM_ID)
   AND EXISTS (SELECT 1 FROM users_company uc
                WHERE uc.empid = TO_NUMBER(:USER_ID) AND uc.com_id = v.com_id)
   AND NOT EXISTS (SELECT 1 FROM hr_contract_extension r WHERE r.emp_id = v.emp_id AND r.status = 'DRAFT')
 ORDER BY v.employee_code;

/* Dynamic Action: P524_EMP_ID Change, only on new records.
   Execute Server-side Code. Items to Submit P524_EMP_ID,P524_COM_ID.
   Return current dates plus P524_EMP_NAME,P524_EMP_TYPE,P524_GRADE.
   Dates with no existing record remain blank and must be entered manually. */
BEGIN
    SELECT TO_CHAR(v.current_from_date, 'DD-MON-YYYY', 'NLS_DATE_LANGUAGE=English'),
           TO_CHAR(v.current_to_date, 'DD-MON-YYYY', 'NLS_DATE_LANGUAGE=English'),
           v.employee_name, v.employee_type, NVL(v.grade, 'Non-grade')
      INTO :P524_CURRENT_FROM_DATE, :P524_CURRENT_TO_DATE,
           :P524_EMP_NAME, :P524_EMP_TYPE, :P524_GRADE
      FROM v_hr_contract_ext_eligible v
     WHERE v.emp_id = TO_NUMBER(:P524_EMP_ID) AND v.com_id = TO_NUMBER(:P524_COM_ID)
       AND EXISTS (SELECT 1 FROM users_company uc
                    WHERE uc.empid = TO_NUMBER(:USER_ID) AND uc.com_id = v.com_id);
END;

/* Dynamic Action: current end date Change on new record.
   Submit P524_CURRENT_TO_DATE; return P524_NEW_FROM_DATE,P524_NEW_TO_DATE.
   End date starts with a 12-month suggestion; HR may change it. */
BEGIN
    :P524_NEW_FROM_DATE := TO_CHAR(TO_DATE(:P524_CURRENT_TO_DATE, 'DD-MON-YYYY')+1, 'DD-MON-YYYY', 'NLS_DATE_LANGUAGE=English');
    :P524_NEW_TO_DATE := TO_CHAR(ADD_MONTHS(TO_DATE(:P524_CURRENT_TO_DATE, 'DD-MON-YYYY')+1, 12)-1, 'DD-MON-YYYY', 'NLS_DATE_LANGUAGE=English');
END;

/* Before Header: Load Existing Extension, condition P524_EXTENSION_ID is not null.
   Run on render, not on submit. Displayed totals reflect saved draft detail. */
BEGIN
    SELECT r.emp_id, r.extension_no, r.emp_name_snapshot,
           CASE r.emp_type_snapshot WHEN '1' THEN 'Probationary' WHEN '3' THEN 'Contractual' END,
           NVL(r.grade_snapshot, 'Non-grade'),
           TO_CHAR(r.current_from_date, 'DD-MON-YYYY', 'NLS_DATE_LANGUAGE=English'),
           TO_CHAR(r.current_to_date, 'DD-MON-YYYY', 'NLS_DATE_LANGUAGE=English'),
           TO_CHAR(r.new_from_date, 'DD-MON-YYYY', 'NLS_DATE_LANGUAGE=English'),
           TO_CHAR(r.new_to_date, 'DD-MON-YYYY', 'NLS_DATE_LANGUAGE=English'),
           r.reason, r.remarks, r.special_terms, r.signatory_id, r.status,
           r.version_no, r.old_basic, r.new_basic, r.old_gross, r.new_gross,
           r.action_id, r.letter_id
      INTO :P524_EMP_ID,:P524_EXTENSION_NO,:P524_EMP_NAME,:P524_EMP_TYPE,:P524_GRADE,
           :P524_CURRENT_FROM_DATE,:P524_CURRENT_TO_DATE,:P524_NEW_FROM_DATE,:P524_NEW_TO_DATE,
           :P524_REASON,:P524_REMARKS,:P524_SPECIAL_TERMS,:P524_SIGNATORY_ID,:P524_STATUS,
           :P524_VERSION_NO,:P524_OLD_BASIC,:P524_NEW_BASIC,:P524_OLD_GROSS,:P524_NEW_GROSS,
           :P524_ACTION_ID,:P524_LETTER_ID
      FROM hr_contract_extension r JOIN employees e ON e.id = r.emp_id
     WHERE r.extension_id = TO_NUMBER(:P524_EXTENSION_ID) AND e.com_id = TO_NUMBER(:P524_COM_ID)
       AND EXISTS (SELECT 1 FROM users_company uc
                    WHERE uc.empid = TO_NUMBER(:USER_ID) AND uc.com_id = e.com_id);
END;

/* Signatory LOV. */
SELECT name_en || ' - ' || title_en d, signatory_id r
  FROM hr_letter_signatory WHERE is_active = 'Y' ORDER BY display_order, name_en;

/* Process CREATE_DRAFT (request only, CONTRACT_EXTEND_EDIT). */
DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM v_hr_contract_ext_eligible v
     WHERE v.emp_id = TO_NUMBER(:P524_EMP_ID) AND v.com_id = TO_NUMBER(:P524_COM_ID)
       AND EXISTS (SELECT 1 FROM users_company uc
                    WHERE uc.empid = TO_NUMBER(:USER_ID) AND uc.com_id = v.com_id);
    IF l_count <> 1 OR :P524_EXTENSION_ID IS NOT NULL THEN
        RAISE_APPLICATION_ERROR(-20751, 'Choose an eligible employee in your authorized company.');
    END IF;
    hrms.pkg_hr_contract_extension.create_draft(
        p_emp_id => TO_NUMBER(:P524_EMP_ID),
        p_current_from_date => TO_DATE(:P524_CURRENT_FROM_DATE, 'DD-MON-YYYY'),
        p_current_to_date => TO_DATE(:P524_CURRENT_TO_DATE, 'DD-MON-YYYY'),
        p_new_from_date => TO_DATE(:P524_NEW_FROM_DATE, 'DD-MON-YYYY'),
        p_new_to_date => TO_DATE(:P524_NEW_TO_DATE, 'DD-MON-YYYY'),
        p_user_id => TO_NUMBER(:USER_ID), p_extension_id => :P524_EXTENSION_ID);
    hrms.pkg_hr_contract_extension.save_draft(
        p_extension_id => TO_NUMBER(:P524_EXTENSION_ID),
        p_new_from_date => TO_DATE(:P524_NEW_FROM_DATE, 'DD-MON-YYYY'),
        p_new_to_date => TO_DATE(:P524_NEW_TO_DATE, 'DD-MON-YYYY'),
        p_reason => :P524_REASON, p_remarks => :P524_REMARKS,
        p_special_terms => :P524_SPECIAL_TERMS, p_signatory_id => TO_NUMBER(:P524_SIGNATORY_ID),
        p_user_id => TO_NUMBER(:USER_ID));
END;
/* Branch back to 524, clear 524, passing extension/company IDs. */

/* Salary grid: static ID extension_salary. Visible only with existing extension ID.
   Allowed insert/update, no delete. Hide built-in Save toolbar action; save
   only through page SAVE_DRAFT / FINAL_SUBMIT.
   Submit P524_EXTENSION_ID,P524_COM_ID. Show SLNO as Popup LOV, OLD_AMOUNT,
   NEW_AMOUNT, CHANGE_AMOUNT, INCLUDE_IN_LETTER.
   Primary key EXTENSION_SALARY_ID. SLNO editable only for new rows.
   OLD_AMOUNT, HEADCODE, CHANGE_AMOUNT: always read-only.
   NEW_AMOUNT: editable for EVERY head including Basic while DRAFT.
   No defaults from pay scale. New rows: NEW_AMOUNT 0; INCLUDE_IN_LETTER Y.
   Old amount for new rows is set to 0 by the package, never from the browser. */
SELECT d.extension_salary_id,d.slno,d.headcode,d.old_amount,d.new_amount,
       d.new_amount-d.old_amount AS change_amount,d.include_in_letter
  FROM hr_contract_extension_salary d
  JOIN hr_contract_extension r ON r.extension_id = d.extension_id
  JOIN employees e ON e.id = r.emp_id
 WHERE r.extension_id = TO_NUMBER(:P524_EXTENSION_ID) AND e.com_id = TO_NUMBER(:P524_COM_ID)
   AND EXISTS (SELECT 1 FROM users_company uc
                WHERE uc.empid = TO_NUMBER(:USER_ID) AND uc.com_id = e.com_id)
 ORDER BY NVL(d.print_order,d.slno),d.slno;

/* SLNO LOV includes all existing heads for display and active heads for entry. */
SELECT head_name d, head_id r FROM allowance_head ORDER BY NVL(print_order,head_id),head_name;

/* Process VALIDATE_AND_LOCK, Sequence 5, request SAVE_DRAFT/FINAL_SUBMIT/
   REFRESH_SALARY/DELETE_DRAFT. Apply matching edit/post authorization.
   This runs BEFORE any grid DML. Protect VERSION_NO from client changes. */
DECLARE
    l_count PLS_INTEGER;
BEGIN
    IF NOT apex_authorization.is_authorized('CONTRACT_EXTEND_EDIT')
       OR (:REQUEST = 'FINAL_SUBMIT' AND NOT apex_authorization.is_authorized('CONTRACT_EXTEND_POST')) THEN
        RAISE_APPLICATION_ERROR(-20751, 'You are not authorized for this extension action.');
    END IF;
    SELECT COUNT(*) INTO l_count FROM hr_contract_extension r JOIN employees e ON e.id = r.emp_id
     WHERE r.extension_id = TO_NUMBER(:P524_EXTENSION_ID) AND e.com_id = TO_NUMBER(:P524_COM_ID)
       AND EXISTS (SELECT 1 FROM users_company uc
                    WHERE uc.empid = TO_NUMBER(:USER_ID) AND uc.com_id = e.com_id);
    IF l_count <> 1 OR :P524_VERSION_NO IS NULL THEN
        RAISE_APPLICATION_ERROR(-20751, 'Draft was not found in your authorized company.');
    END IF;
    hrms.pkg_hr_contract_extension.lock_draft(
        TO_NUMBER(:P524_EXTENSION_ID), TO_NUMBER(:USER_ID), TO_NUMBER(:P524_VERSION_NO));
END;

/* Salary Interactive Grid DML process, Sequence 10, Target Type PL/SQL Code,
   Editable Region extension_salary; condition SAVE_DRAFT/FINAL_SUBMIT only.
   Custom code is called once per changed/new row. */
BEGIN
    IF :APEX$ROW_STATUS NOT IN ('C','U') THEN
        RAISE_APPLICATION_ERROR(-20710, 'Use a zero proposed amount instead of deleting salary rows.');
    END IF;
    hrms.pkg_hr_contract_extension.save_salary_row(
        p_extension_id => TO_NUMBER(:P524_EXTENSION_ID),
        p_salary_id => :EXTENSION_SALARY_ID, p_head_id => :SLNO,
        p_new_amount => :NEW_AMOUNT, p_include_in_letter => :INCLUDE_IN_LETTER,
        p_user_id => TO_NUMBER(:USER_ID));
END;

/* SAVE_HEADER process, Sequence 20, request SAVE_DRAFT/FINAL_SUBMIT only.
   No scale or benefit recalculation. */
BEGIN
    hrms.pkg_hr_contract_extension.save_draft(
        p_extension_id => TO_NUMBER(:P524_EXTENSION_ID),
        p_new_from_date => TO_DATE(:P524_NEW_FROM_DATE, 'DD-MON-YYYY'),
        p_new_to_date => TO_DATE(:P524_NEW_TO_DATE, 'DD-MON-YYYY'),
        p_reason => :P524_REASON, p_remarks => :P524_REMARKS,
        p_special_terms => :P524_SPECIAL_TERMS, p_signatory_id => TO_NUMBER(:P524_SIGNATORY_ID),
        p_user_id => TO_NUMBER(:USER_ID));
END;

/* FINAL_SUBMIT process, Sequence 30, request FINAL_SUBMIT only.
   Authorization CONTRACT_EXTEND_POST. Standard button confirmation:
   "Finalize this extension and apply the manually entered changes?" */
BEGIN
    hrms.pkg_hr_contract_extension.final_submit(
        p_extension_id => TO_NUMBER(:P524_EXTENSION_ID), p_user_id => TO_NUMBER(:USER_ID),
        p_action_id => :P524_ACTION_ID, p_letter_id => :P524_LETTER_ID);
END;
/* Branch to 525, clear 525:
   P525_EXTENSION_ID=&P524_EXTENSION_ID., P525_COM_ID=&P524_COM_ID. */

/* REFRESH_SALARY process, sequence 20, request REFRESH_SALARY only.
   Confirmation: "Discard proposed amounts and copy current salary again?" */
BEGIN
    hrms.pkg_hr_contract_extension.refresh_salary_snapshot(
        TO_NUMBER(:P524_EXTENSION_ID), TO_NUMBER(:USER_ID));
END;

/* DELETE_DRAFT process, sequence 20, request DELETE_DRAFT only. */
BEGIN
    hrms.pkg_hr_contract_extension.delete_draft(
        TO_NUMBER(:P524_EXTENSION_ID), TO_NUMBER(:USER_ID));
END;
/* SAVE/REFRESH branch back to 524, clear 524 with extension/company IDs.
   DELETE/BACK branch to 523 with company ID.
   VIEW_LETTER opens 525 with extension/company IDs, session checksum.
   Existing amounts can be set to 0; new heads require an explicit row.
   Non-payroll terms entered here are recorded in the letter only. */
