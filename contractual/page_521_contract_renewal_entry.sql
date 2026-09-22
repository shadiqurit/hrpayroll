/* ============================================================================
   PAGE 521 - GENERATED RENEWAL MASTER/DETAIL

   Page 520 creates the renewal before this page opens. Page 521 only:
     - reviews the generated employee/contract information;
     - optionally adjusts the new contract and proposed salary;
     - saves or final submits the renewal.

   No employee picker and no Create Draft button are required on this page.
   ============================================================================ */

/* Page access
   -----------------------------------------------------------------------------
   Authorization: CONTRACT_VIEW
   P521_RENEWAL_ID must not be null.

   Page items:
     Hidden, Protected:
       P521_RENEWAL_ID, P521_COM_ID, P521_EMP_ID, P521_VERSION_NO,
       P521_LETTER_ID, P521_ACTION_ID

     Display Only:
       P521_RENEWAL_NO, P521_EMP_CODE_SNAPSHOT,
       P521_EMP_NAME_SNAPSHOT, P521_DESIGNATION_SNAPSHOT,
       P521_DEPARTMENT_SNAPSHOT, P521_LOCATION_SNAPSHOT,
       P521_CURRENT_FROM_DATE, P521_CURRENT_TO_DATE,
       P521_OLD_GRADE_ID, P521_OLD_SCALE_ID, P521_OLD_STEP_NO,
       P521_NEW_FROM_DATE,
       P521_OLD_BASIC, P521_OLD_GROSS, P521_NEW_BASIC, P521_NEW_GROSS,
       P521_SALARY_MODE, P521_STATUS

     Editable while status is DRAFT:
       P521_NEW_TO_DATE, P521_NEW_GRADE_ID, P521_NEW_SCALE_ID,
       P521_NEW_STEP_NO,
       P521_REASON, P521_REMARKS, P521_SPECIAL_TERMS,
       P521_SIGNATORY_ID

     Automatically selected from P521_NEW_GRADE_ID and display-only:
       P521_TEMPLATE_ID

     Final confirmation:
       P521_FINAL_CONFIRM
*/


/* Before Header process: Load Renewal
   Sequence: 10
*/
BEGIN
    SELECT r.renewal_no,
           r.emp_id,
           r.emp_code_snapshot,
           r.emp_name_snapshot,
           r.designation_snapshot,
           r.department_snapshot,
           r.location_snapshot,
           r.current_from_date,
           r.current_to_date,
           r.old_grade_id,
           r.old_scale_id,
           r.old_step_no,
           r.new_from_date,
           r.new_to_date,
           r.new_grade_id,
           r.new_scale_id,
           r.new_step_no,
           r.salary_mode,
           r.old_basic,
           r.new_basic,
           r.old_gross,
           r.new_gross,
           r.reason,
           r.remarks,
           r.special_terms,
           r.signatory_id,
           r.template_id,
           r.status,
           r.version_no,
           r.letter_id,
           r.action_id,
           e.com_id
      INTO :P521_RENEWAL_NO,
           :P521_EMP_ID,
           :P521_EMP_CODE_SNAPSHOT,
           :P521_EMP_NAME_SNAPSHOT,
           :P521_DESIGNATION_SNAPSHOT,
           :P521_DEPARTMENT_SNAPSHOT,
           :P521_LOCATION_SNAPSHOT,
           :P521_CURRENT_FROM_DATE,
           :P521_CURRENT_TO_DATE,
           :P521_OLD_GRADE_ID,
           :P521_OLD_SCALE_ID,
           :P521_OLD_STEP_NO,
           :P521_NEW_FROM_DATE,
           :P521_NEW_TO_DATE,
           :P521_NEW_GRADE_ID,
           :P521_NEW_SCALE_ID,
           :P521_NEW_STEP_NO,
           :P521_SALARY_MODE,
           :P521_OLD_BASIC,
           :P521_NEW_BASIC,
           :P521_OLD_GROSS,
           :P521_NEW_GROSS,
           :P521_REASON,
           :P521_REMARKS,
           :P521_SPECIAL_TERMS,
           :P521_SIGNATORY_ID,
           :P521_TEMPLATE_ID,
           :P521_STATUS,
           :P521_VERSION_NO,
           :P521_LETTER_ID,
           :P521_ACTION_ID,
           :P521_COM_ID
      FROM hr_contract_renewal r
      JOIN employees e ON e.id = r.emp_id
     WHERE r.renewal_id = TO_NUMBER(:P521_RENEWAL_ID)
       AND e.com_id = TO_NUMBER(:P521_COM_ID);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20751, 'Renewal was not found for this company.');
END;


/* Display-only LOVs for old values and editable LOVs for new values. */

/* Grade LOV */
SELECT NVL(grade_code || ' - ', '') || grade_name d, id r
  FROM job_grades
 ORDER BY NVL(grade_order, 999), grade_name;

/* Scale LOV - cascading parents P521_NEW_GRADE_ID,P521_NEW_FROM_DATE */
SELECT revision_name || ' (' ||
       TO_CHAR(start_basic, 'FM999G999G990') || '-' ||
       TO_CHAR(increment_1, 'FM999G999G990') || '-' ||
       TO_CHAR(eb_basic, 'FM999G999G990') || '-EB-' ||
       TO_CHAR(increment_2, 'FM999G999G990') || '-' ||
       TO_CHAR(max_basic, 'FM999G999G990') || ')' d,
       scale_id r
  FROM pay_scale_master
 WHERE grade_id = :P521_NEW_GRADE_ID
   AND is_active = 'Y'
   AND (effective_from IS NULL
        OR effective_from <= TO_DATE(:P521_NEW_FROM_DATE, 'DD-MON-YYYY'))
   AND (effective_to IS NULL
        OR effective_to >= TO_DATE(:P521_NEW_FROM_DATE, 'DD-MON-YYYY'))
 ORDER BY revision_no DESC;

/* Step LOV - cascading parent P521_NEW_SCALE_ID */
SELECT 'Step ' || step_no || ' - ' ||
       TO_CHAR(basic_amount, 'FM999G999G990D00') d,
       step_no r
  FROM pay_scale_detail
 WHERE scale_id = :P521_NEW_SCALE_ID
 ORDER BY step_no;

/* Signatory LOV */
SELECT name_en || ' - ' || title_en
       || CASE WHEN name_bn IS NOT NULL
               THEN ' / ' || name_bn || ' - ' || title_bn END d,
       signatory_id r
  FROM hr_letter_signatory
 WHERE is_active = 'Y'
 ORDER BY display_order, name_en;

/* Template LOV - configure P521_TEMPLATE_ID as display-only. */
SELECT template_name d, template_id r
  FROM hr_letter_template
 WHERE action_type = 'CONTRACT_RENEWAL'
   AND is_active = 'Y'
   AND template_code = (
       SELECT CASE
                  WHEN grade_order BETWEEN 1 AND 14 THEN 'CONTRACT_RENEWAL_EN'
                  WHEN grade_order BETWEEN 16 AND 20 THEN 'CONTRACT_RENEWAL_BN'
              END
         FROM job_grades
        WHERE id = TO_NUMBER(:P521_NEW_GRADE_ID)
   )
 ORDER BY template_name;


/* Salary Detail - editable Interactive Grid
   -----------------------------------------------------------------------------
   Region Static ID: renewal_salary
   Page Items to Submit: P521_RENEWAL_ID,P521_STATUS,P521_SALARY_MODE
   Primary key: RENEWAL_SALARY_ID
   Allowed Operations: Update only
   Add Row: No
   Delete Row: No
*/
SELECT renewal_salary_id,
       renewal_id,
       emp_id,
       sals_id,
       slno,
       headcode,
       head_name,
       head_type,
       print_order,
       old_amount,
       new_amount,
       new_amount - old_amount AS change_amount,
       include_in_letter,
       is_posted,
       updated_by,
       updated_date
  FROM hr_contract_renewal_salary
 WHERE renewal_id = TO_NUMBER(:P521_RENEWAL_ID)
 ORDER BY NVL(print_order, slno), slno;

/* Grid column rules
   -----------------------------------------------------------------------------
   Show: HEAD_NAME, OLD_AMOUNT, NEW_AMOUNT, CHANGE_AMOUNT, INCLUDE_IN_LETTER
   OLD_AMOUNT and CHANGE_AMOUNT: always read-only

   NEW_AMOUNT read-only PL/SQL expression:

     :P521_STATUS <> 'DRAFT'
     OR LPAD(TRIM(:HEADCODE), 3, '0') = '001'
     OR (
          :P521_SALARY_MODE = 'AUTO'
          AND LPAD(TRIM(:HEADCODE), 3, '0') IN
              ('005', '007', '010', '013', '037', '057', '075')
        )

   Meaning:
     AUTO   - Basic and configured formula/fixed heads are package calculated.
     MANUAL - Basic is scale calculated; all other proposed amounts are editable.
*/


/* Buttons
   -----------------------------------------------------------------------------
   SAVE_DRAFT      Submit; show when P521_STATUS = DRAFT
   REFRESH_SALARY  Submit; show when P521_STATUS = DRAFT
   FINAL_SUBMIT    Submit; show when P521_STATUS = DRAFT
   DELETE_DRAFT    Submit; show when P521_STATUS = DRAFT
   VIEW_LETTER     Redirect to Page 522; show when P521_STATUS = POSTED
   BACK            Redirect to Page 520

   Do not create CREATE_DRAFT or employee selection controls on Page 521.
*/


/* Editable IG Automatic Row Processing (DML)
   Sequence: 10
   Server-side condition, PL/SQL Expression:
     :REQUEST IN ('SAVE_DRAFT', 'FINAL_SUBMIT')
*/


/* Save header and recalculate salary
   Sequence: 20
   Server-side condition, PL/SQL Expression:
     :REQUEST IN ('SAVE_DRAFT', 'FINAL_SUBMIT')
*/
BEGIN
    hrms.pkg_hr_contract_renewal.save_draft(
        p_renewal_id    => TO_NUMBER(:P521_RENEWAL_ID),
        p_new_from_date => TO_DATE(:P521_NEW_FROM_DATE, 'DD-MON-YYYY'),
        p_new_to_date   => TO_DATE(:P521_NEW_TO_DATE, 'DD-MON-YYYY'),
        p_new_grade_id  => TO_NUMBER(:P521_NEW_GRADE_ID),
        p_new_scale_id  => TO_NUMBER(:P521_NEW_SCALE_ID),
        p_new_step_no   => TO_NUMBER(:P521_NEW_STEP_NO),
        p_reason        => :P521_REASON,
        p_remarks       => :P521_REMARKS,
        p_special_terms => :P521_SPECIAL_TERMS,
        p_signatory_id  => TO_NUMBER(:P521_SIGNATORY_ID),
        p_user_id       => TO_NUMBER(:USER_ID)
    );
END;

/* SAVE_DRAFT branch: return to Page 521 with renewal/company IDs.
   Reloading shows the recalculated Basic and gross values.
*/


/* REFRESH_SALARY process
   Sequence: 10
   When Button Pressed: REFRESH_SALARY

   Confirmation:
     Discard proposed amounts and copy the current live salary again?
*/
BEGIN
    hrms.pkg_hr_contract_renewal.refresh_salary_snapshot(
        p_renewal_id => TO_NUMBER(:P521_RENEWAL_ID),
        p_user_id    => TO_NUMBER(:USER_ID)
    );
END;

/* REFRESH_SALARY branch: return to Page 521. */


/* FINAL_SUBMIT process
   Sequence: 30
   When Button Pressed: FINAL_SUBMIT

   Button confirmation:
     Final Submit updates the live salary and current contract and creates the
     letter. This cannot be edited afterward. Continue?
*/
BEGIN
    IF UPPER(TRIM(:P521_FINAL_CONFIRM)) <> UPPER(TRIM(:P521_RENEWAL_NO)) THEN
        RAISE_APPLICATION_ERROR(
            -20001,
            'Type the renewal number exactly to confirm final submit.'
        );
    END IF;

    hrms.pkg_hr_contract_renewal.final_submit(
        p_renewal_id => TO_NUMBER(:P521_RENEWAL_ID),
        p_user_id    => TO_NUMBER(:USER_ID),
        p_action_id  => :P521_ACTION_ID,
        p_letter_id  => :P521_LETTER_ID
    );
END;

/* FINAL_SUBMIT branch:
     Page 522
     P522_RENEWAL_ID = &P521_RENEWAL_ID.
     P522_COM_ID     = &P521_COM_ID.
*/


/* DELETE_DRAFT process
   When Button Pressed: DELETE_DRAFT
*/
BEGIN
    hrms.pkg_hr_contract_renewal.delete_draft(
        p_renewal_id => TO_NUMBER(:P521_RENEWAL_ID),
        p_user_id    => TO_NUMBER(:USER_ID)
    );
END;

/* DELETE_DRAFT branch: Page 520. */


/* VIEW_LETTER target - POSTED only
   Page 522, clear cache 522
   P522_RENEWAL_ID = &P521_RENEWAL_ID.
   P522_COM_ID     = &P521_COM_ID.
   Checksum: Session Level
*/
