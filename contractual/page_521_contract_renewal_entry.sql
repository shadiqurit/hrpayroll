/* ============================================================================
   PAGE 521 - CONTRACT RENEWAL ENTRY AND APPROVAL

   This file contains APEX sources/process calls. README.md gives the exact
   component order, conditions, authorizations, and branching.
   ============================================================================ */

/* --------------------------------------------------------------------------
   Form initialization query for an existing renewal.
   Use it as a Before Header process when P521_RENEWAL_ID is not null.
   -------------------------------------------------------------------------- */
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
           r.old_basic,
           r.new_basic,
           r.old_gross,
           r.new_gross,
           r.reason,
           r.remarks,
           r.special_terms,
           r.signatory_id,
           r.template_id,
           r.approval_status,
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
           :P521_OLD_BASIC,
           :P521_NEW_BASIC,
           :P521_OLD_GROSS,
           :P521_NEW_GROSS,
           :P521_REASON,
           :P521_REMARKS,
           :P521_SPECIAL_TERMS,
           :P521_SIGNATORY_ID,
           :P521_TEMPLATE_ID,
           :P521_APPROVAL_STATUS,
           :P521_VERSION_NO,
           :P521_LETTER_ID,
           :P521_ACTION_ID,
           :P521_COM_ID
      FROM hr_contract_renewal r
      JOIN employees e ON e.id = r.emp_id
     WHERE r.renewal_id = :P521_RENEWAL_ID
       AND e.com_id = :P521_COM_ID;
END;


/* Employee LOV. If EMP_TYPE codes are configured in your installation, add
   that filter here. The package itself does not guess a contractual type ID. */
SELECT e.emp_id || ' - ' || TRIM(e.f_name || ' ' || e.l_name) d,
       e.id r
  FROM employees e
 WHERE e.com_id = :P521_COM_ID
   AND NVL(e.status, 1) <> 0
   AND (
       EXISTS (
           SELECT 1
             FROM hr_employee_contract c
            WHERE c.emp_id = e.id
              AND c.contract_status = 'ACTIVE'
       )
       OR :P521_ALLOW_BASELINE = 'Y'
   )
 ORDER BY e.emp_id;

/* Before Header, before LOV evaluation. P521_ALLOW_BASELINE is Hidden and
   Value Protected = Yes. */
BEGIN
    IF apex_authorization.is_authorized('CONTRACT_BASELINE_ADMIN') THEN
        :P521_ALLOW_BASELINE := 'Y';
    ELSE
        :P521_ALLOW_BASELINE := 'N';
    END IF;
END;

/* Grade LOV */
SELECT NVL(grade_code || ' - ', '') || grade_name d, id r
  FROM job_grades
 ORDER BY NVL(grade_order, 999), grade_name;

/* Scale LOV - cascading parent item P521_NEW_GRADE_ID */
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

/* Step LOV - cascading parent item P521_NEW_SCALE_ID */
SELECT 'Step ' || step_no || ' - ' ||
       TO_CHAR(basic_amount, 'FM999G999G990D00') d,
       step_no r
  FROM pay_scale_detail
 WHERE scale_id = :P521_NEW_SCALE_ID
 ORDER BY step_no;

/* Signatory LOV */
SELECT name_bn || ' - ' || title_bn d, signatory_id r
  FROM hr_letter_signatory
 WHERE is_active = 'Y'
 ORDER BY display_order, name_bn;

/* Template LOV */
SELECT template_name d, template_id r
  FROM hr_letter_template
 WHERE action_type = 'CONTRACT_RENEWAL'
   AND is_active = 'Y'
 ORDER BY template_name;


/* --------------------------------------------------------------------------
   Dynamic Action: Fetch Current Contract
   Event: Change on P521_EMP_ID, create mode only
   Action: Execute Server-side Code
   Items to Submit: P521_EMP_ID
   Items to Return: P521_CURRENT_FROM_DATE,P521_CURRENT_TO_DATE,
                    P521_OLD_GRADE_ID,P521_OLD_SCALE_ID,P521_OLD_STEP_NO,
                    P521_NEW_FROM_DATE,P521_NEW_TO_DATE,
                    P521_NEW_GRADE_ID,P521_NEW_SCALE_ID,P521_NEW_STEP_NO
   -------------------------------------------------------------------------- */
BEGIN
    SELECT c.contract_from_date,
           c.contract_to_date,
           c.grade_id,
           c.scale_id,
           c.step_no,
           c.contract_to_date + 1,
           ADD_MONTHS(c.contract_to_date + 1, 12) - 1,
           c.grade_id,
           c.scale_id,
           c.step_no
      INTO :P521_CURRENT_FROM_DATE,
           :P521_CURRENT_TO_DATE,
           :P521_OLD_GRADE_ID,
           :P521_OLD_SCALE_ID,
           :P521_OLD_STEP_NO,
           :P521_NEW_FROM_DATE,
           :P521_NEW_TO_DATE,
           :P521_NEW_GRADE_ID,
           :P521_NEW_SCALE_ID,
           :P521_NEW_STEP_NO
      FROM hr_employee_contract c
      JOIN employees e ON e.id = c.emp_id
     WHERE c.emp_id = :P521_EMP_ID
       AND c.contract_status = 'ACTIVE'
       AND e.com_id = :P521_COM_ID;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        :P521_CURRENT_FROM_DATE := NULL;
        :P521_CURRENT_TO_DATE   := NULL;
        :P521_OLD_GRADE_ID      := NULL;
        :P521_OLD_SCALE_ID      := NULL;
        :P521_OLD_STEP_NO       := NULL;
        :P521_NEW_FROM_DATE     := NULL;
        :P521_NEW_TO_DATE       := NULL;
        :P521_NEW_GRADE_ID      := NULL;
        :P521_NEW_SCALE_ID      := NULL;
        :P521_NEW_STEP_NO       := NULL;
END;


/* --------------------------------------------------------------------------
   Region: Salary Structure
   Type: Editable Interactive Grid
   Primary key: RENEWAL_SALARY_ID
   Parent: P521_RENEWAL_ID
   -------------------------------------------------------------------------- */
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
 WHERE renewal_id = :P521_RENEWAL_ID
 ORDER BY NVL(print_order, slno), slno;

/* Grid rules:
   - OLD_AMOUNT, CHANGE_AMOUNT, HEAD_TYPE, IS_POSTED are read only.
   - NEW_AMOUNT and INCLUDE_IN_LETTER are editable only for DRAFT.
   - Basic (normalized HEADCODE 001 or SLNO 1) is display-only; SAVE_DRAFT
     derives it from the selected grade/scale/step.
   - Use an Allowance Head LOV for new SLNO rows; populate HEADCODE/HEAD_NAME/
     HEAD_TYPE/PRINT_ORDER from ALLOWANCE_HEAD in a validation/process.
   - Do not allow row deletion. A missing captured live row deliberately blocks
     final submit as a stale/incomplete salary snapshot.
*/


/* --------------------------------------------------------------------------
   Region: Letter Recipients
   Type: Editable Interactive Grid
   -------------------------------------------------------------------------- */
SELECT x.recipient_id,
       x.renewal_id,
       x.section_type,
       x.letter_recipient_id,
       NVL(m.recipient_name_bn, x.line_text) AS recipient_text,
       x.line_text,
       x.display_order,
       x.is_active
  FROM hr_contract_renew_recipient x
  LEFT JOIN hr_letter_recipient m
    ON m.letter_recipient_id = x.letter_recipient_id
 WHERE x.renewal_id = :P521_RENEWAL_ID
 ORDER BY CASE x.section_type WHEN 'TO' THEN 1 ELSE 2 END,
          x.display_order,
          x.recipient_id;

/* Recipient master LOV */
SELECT NVL(recipient_name_bn, recipient_name_en) d,
       letter_recipient_id r
  FROM hr_letter_recipient
 WHERE is_active = 'Y'
 ORDER BY display_order, recipient_name_en;


/* --------------------------------------------------------------------------
   CREATE DRAFT process - button CREATE_DRAFT, when P521_RENEWAL_ID is null.
   -------------------------------------------------------------------------- */
BEGIN
    hrms.pkg_hr_contract_renewal.create_draft(
        p_emp_id            => :P521_EMP_ID,
        p_current_from_date => TO_DATE(:P521_CURRENT_FROM_DATE, 'DD-MON-YYYY'),
        p_current_to_date   => TO_DATE(:P521_CURRENT_TO_DATE, 'DD-MON-YYYY'),
        p_old_grade_id      => :P521_OLD_GRADE_ID,
        p_old_scale_id      => :P521_OLD_SCALE_ID,
        p_old_step_no       => :P521_OLD_STEP_NO,
        p_new_from_date     => TO_DATE(:P521_NEW_FROM_DATE, 'DD-MON-YYYY'),
        p_new_to_date       => TO_DATE(:P521_NEW_TO_DATE, 'DD-MON-YYYY'),
        p_new_grade_id      => :P521_NEW_GRADE_ID,
        p_new_scale_id      => :P521_NEW_SCALE_ID,
        p_new_step_no       => :P521_NEW_STEP_NO,
        p_user_id           => :G_USER_ID,
        p_renewal_id        => :P521_RENEWAL_ID
    );
END;

/* Branch back to Page 521 with P521_RENEWAL_ID and clear cache 521. */


/* SAVE DRAFT process. Interactive Grid DML must run first. */
BEGIN
    hrms.pkg_hr_contract_renewal.save_draft(
        p_renewal_id    => :P521_RENEWAL_ID,
        p_new_from_date => TO_DATE(:P521_NEW_FROM_DATE, 'DD-MON-YYYY'),
        p_new_to_date   => TO_DATE(:P521_NEW_TO_DATE, 'DD-MON-YYYY'),
        p_new_grade_id  => :P521_NEW_GRADE_ID,
        p_new_scale_id  => :P521_NEW_SCALE_ID,
        p_new_step_no   => :P521_NEW_STEP_NO,
        p_reason        => :P521_REASON,
        p_remarks       => :P521_REMARKS,
        p_special_terms => :P521_SPECIAL_TERMS,
        p_signatory_id  => :P521_SIGNATORY_ID,
        p_template_id   => :P521_TEMPLATE_ID,
        p_user_id       => :G_USER_ID
    );
END;


/* REFRESH SALARY SNAPSHOT process */
BEGIN
    hrms.pkg_hr_contract_renewal.refresh_salary_snapshot(
        p_renewal_id => :P521_RENEWAL_ID,
        p_user_id    => :G_USER_ID
    );
END;


/* SUBMIT FOR APPROVAL process.
   For this button run, in order:
     10 Salary IG DML
     20 Recipient IG DML
     30 SAVE_DRAFT block above
     40 This block
*/
BEGIN
    hrms.pkg_hr_contract_renewal.submit_for_approval(
        p_renewal_id => :P521_RENEWAL_ID,
        p_user_id    => :G_USER_ID
    );
END;


/* RETURN TO DRAFT process */
BEGIN
    hrms.pkg_hr_contract_renewal.return_to_draft(
        p_renewal_id => :P521_RENEWAL_ID,
        p_reason     => :P521_ACTION_REMARKS,
        p_user_id    => :G_USER_ID
    );
END;


/* APPROVE process - letter is generated here; salary is not changed. */
BEGIN
    hrms.pkg_hr_contract_renewal.approve_renewal(
        p_renewal_id => :P521_RENEWAL_ID,
        p_user_id    => :G_USER_ID,
        p_letter_id  => :P521_LETTER_ID
    );
END;


/* FINAL SUBMIT process - approved salary is applied atomically here. */
BEGIN
    IF UPPER(TRIM(:P521_FINAL_CONFIRM)) <> UPPER(TRIM(:P521_RENEWAL_NO)) THEN
        RAISE_APPLICATION_ERROR(
            -20001,
            'Type the renewal number exactly to confirm final salary posting.'
        );
    END IF;

    hrms.pkg_hr_contract_renewal.final_submit(
        p_renewal_id => :P521_RENEWAL_ID,
        p_user_id    => :G_USER_ID,
        p_action_id  => :P521_ACTION_ID
    );
END;


/* CANCEL process */
BEGIN
    hrms.pkg_hr_contract_renewal.cancel_renewal(
        p_renewal_id => :P521_RENEWAL_ID,
        p_reason     => :P521_ACTION_REMARKS,
        p_user_id    => :G_USER_ID
    );
END;


/* Letter button target (show only for APPROVED or POSTED):
   Page 522, Clear Cache 522,
   Set P522_RENEWAL_ID = &P521_RENEWAL_ID.
   Set P522_COM_ID = &P521_COM_ID.
   Checksum = Session Level.
*/
