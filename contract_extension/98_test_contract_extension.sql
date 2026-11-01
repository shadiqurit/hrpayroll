/* Integration regression. Run ONLY in a disposable HRMS test database:
     @98_test_contract_extension.sql employee_internal_id authenticated_user_id
   Employee must be eligible, authorized, have recorded dates ending before
   today, and have no existing draft. All DML is rolled back on success/failure.
   Identity/sequence numbers are consumed. Do not run with concurrent activity. */
SET DEFINE ON;
SET SERVEROUTPUT ON;
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK;

DECLARE
    l_emp NUMBER := &1;
    l_user NUMBER := &2;
    l_from DATE;
    l_to DATE;
    l_type VARCHAR2(30);
    l_extension NUMBER;
    l_duplicate NUMBER;
    l_row NUMBER;
    l_head NUMBER;
    l_old NUMBER;
    l_new NUMBER;
    l_sign NUMBER;
    l_version NUMBER;
    l_action NUMBER;
    l_letter NUMBER;
    l_count PLS_INTEGER;
    l_hist_before PLS_INTEGER;
    l_hist_after PLS_INTEGER;
    l_body CLOB;
    l_renewal_count PLS_INTEGER;
    l_renewal_version NUMBER;
    l_latest_renewal NUMBER;
    l_renewal_en CLOB;
    l_renewal_bn CLOB;
    l_current_template CLOB;

    PROCEDURE check_that(p_true BOOLEAN,p_message VARCHAR2) IS
    BEGIN
        IF p_true IS NULL OR NOT p_true THEN
            RAISE_APPLICATION_ERROR(-20800,p_message);
        END IF;
    END;
    PROCEDURE save_header IS
    BEGIN
        hrms.pkg_hr_contract_extension.save_draft(l_extension,TRUNC(l_to)+1,
            ADD_MONTHS(TRUNC(l_to)+1,12)-1,'Regression test',NULL,
            TO_CLOB('<manual terms>'),l_sign,l_user);
    END;
BEGIN
    SAVEPOINT TEST_MANUAL_EXTENSION;
    SELECT current_from_date,current_to_date,emp_type INTO l_from,l_to,l_type
      FROM v_hr_contract_ext_eligible WHERE emp_id=l_emp;
    check_that(l_from IS NOT NULL AND l_to IS NOT NULL AND TRUNC(l_to)<TRUNC(SYSDATE),
        'Choose an employee with recorded dates ending before today.');
    SELECT COUNT(*) INTO l_count FROM hr_contract_extension WHERE emp_id=l_emp AND status='DRAFT';
    check_that(l_count=0,'Choose an employee without a draft.');
    SELECT COUNT(*), NVL(SUM(version_no),0) INTO l_renewal_count,l_renewal_version
      FROM hr_contract_renewal WHERE emp_id=l_emp;
    SELECT MAX(latest_renewal_id) INTO l_latest_renewal FROM hr_employee_contract WHERE emp_id=l_emp;
    SELECT body_template INTO l_renewal_en FROM hr_letter_template WHERE template_code='CONTRACT_RENEWAL_EN';
    SELECT body_template INTO l_renewal_bn FROM hr_letter_template WHERE template_code='CONTRACT_RENEWAL_BN';

    /* Demonstrate non-grade eligibility without altering committed data. */
    UPDATE employees SET grade=NULL WHERE id=l_emp;
    UPDATE hr_employee_contract SET grade_id=NULL,scale_id=NULL,step_no=NULL WHERE emp_id=l_emp;
    hrms.pkg_hr_contract_extension.create_due_extension(l_emp,'MANUAL',12,l_user,l_extension);
    SELECT COUNT(*) INTO l_count FROM hr_contract_extension
     WHERE extension_id=l_extension AND new_grade_id IS NULL AND new_scale_id IS NULL
       AND new_step_no IS NULL AND salary_mode='MANUAL' AND emp_type_snapshot=l_type;
    check_that(l_count=1,'Non-grade draft should not require scale or step.');
    SELECT COUNT(*) INTO l_count FROM hr_contract_extension_salary
     WHERE extension_id=l_extension AND new_amount<>old_amount;
    check_that(l_count=0,'Preparation must copy all amounts unchanged.');
    SELECT COUNT(*) INTO l_count FROM emp_salary_structure s
     WHERE s.employee_id=l_emp AND NVL(s.is_active,'Y')='Y'
       AND NOT EXISTS (SELECT 1 FROM hr_contract_extension_salary d
            WHERE d.extension_id=l_extension AND d.sals_id=s.sals_id
              AND d.old_amount=NVL(s.amount,0) AND d.new_amount=NVL(s.amount,0));
    check_that(l_count=0,'All active salary rows must be copied.');

    BEGIN
        hrms.pkg_hr_contract_extension.create_due_extension(l_emp,'MANUAL',12,l_user,l_duplicate);
        RAISE_APPLICATION_ERROR(-20800,'Duplicate draft was accepted.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE<>-20714 THEN RAISE; END IF;
    END;
    BEGIN
        hrms.pkg_hr_contract_extension.create_due_extension(l_emp,'AUTO',12,l_user,l_duplicate);
        RAISE_APPLICATION_ERROR(-20800,'Automatic mode was accepted.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE<>-20740 THEN RAISE; END IF;
    END;

    SELECT signatory_id,version_no INTO l_sign,l_version FROM hr_contract_extension WHERE extension_id=l_extension;
    check_that(l_sign IS NOT NULL,'Activate a real signatory before running this test.');
    /* Basic, or the first available head if there is no Basic, is manual. */
    SELECT MIN(extension_salary_id) KEEP (DENSE_RANK FIRST ORDER BY
        CASE WHEN LPAD(TRIM(headcode),3,'0')='001' THEN 0 ELSE 1 END,slno)
      INTO l_row FROM hr_contract_extension_salary WHERE extension_id=l_extension;
    IF l_row IS NOT NULL THEN
        SELECT slno,old_amount INTO l_head,l_old FROM hr_contract_extension_salary WHERE extension_salary_id=l_row;
        SAVEPOINT TEST_BEFORE_MANUAL;
        hrms.pkg_hr_contract_extension.save_salary_row(l_extension,l_row,l_head,l_old+12.34,'Y',l_user);
        save_header;
        SELECT new_amount INTO l_new FROM hr_contract_extension_salary WHERE extension_salary_id=l_row;
        check_that(l_new=l_old+12.34,'Save must retain the exact manual amount, including Basic.');
        BEGIN
            hrms.pkg_hr_contract_extension.lock_draft(l_extension,l_user,l_version);
            RAISE_APPLICATION_ERROR(-20800,'A stale master version was accepted.');
        EXCEPTION WHEN OTHERS THEN
            IF SQLCODE<>-20721 THEN RAISE; END IF;
        END;
        hrms.pkg_hr_contract_extension.final_submit(l_extension,l_user,l_action,l_letter);
        SELECT COUNT(*) INTO l_count FROM emp_salary_structure
         WHERE employee_id=l_emp AND slno=l_head AND amount=l_old+12.34;
        check_that(l_count=1,'Posting must apply the exact entered amount.');
        SELECT COUNT(*) INTO l_count FROM hr_contract_extension_salary d
          JOIN emp_salary_structure s ON s.sals_id=d.sals_id
         WHERE d.extension_id=l_extension AND d.slno<>l_head AND NVL(s.amount,0)<>d.old_amount;
        check_that(l_count=0,'Changing Basic must not recalculate other benefits.');
        ROLLBACK TO TEST_BEFORE_MANUAL;
        hrms.pkg_hr_contract_extension.refresh_salary_snapshot(l_extension,l_user);
    END IF;
    save_header;
    SELECT COUNT(*) INTO l_hist_before FROM emp_salary_structure_hist WHERE emp_id=l_emp;
    SAVEPOINT TEST_BEFORE_POST;
    hrms.pkg_hr_contract_extension.final_submit(l_extension,l_user,l_action,l_letter);
    check_that(l_action IS NOT NULL AND l_letter IS NOT NULL,'Post must produce action and letter.');
    SELECT COUNT(*) INTO l_count FROM hr_employee_action
     WHERE action_id=l_action AND action_type='CONTRACT_EXTENSION';
    check_that(l_count=1,'Extension must use its own action type.');
    SELECT COUNT(*) INTO l_count FROM hr_employee_letter l JOIN hr_letter_template t ON t.template_id=l.template_id
     WHERE l.letter_id=l_letter AND l.contract_extension_id=l_extension
       AND l.contract_renewal_id IS NULL AND t.template_code='CONTRACT_EXTENSION_EN';
    check_that(l_count=1,'Extension letter must have an extension link and template only.');
    SELECT COUNT(*) INTO l_count FROM hr_contract_renewal WHERE emp_id=l_emp;
    check_that(l_count=l_renewal_count,'Extension must not create renewal rows.');
    SELECT NVL(SUM(version_no),0) INTO l_version FROM hr_contract_renewal WHERE emp_id=l_emp;
    check_that(l_version=l_renewal_version,'Extension must not revise renewal rows.');
    SELECT latest_renewal_id INTO l_version FROM hr_employee_contract WHERE emp_id=l_emp;
    check_that(NVL(l_version,-1)=NVL(l_latest_renewal,-1),'Extension must preserve the renewal pointer.');
    SELECT body_template INTO l_current_template FROM hr_letter_template WHERE template_code='CONTRACT_RENEWAL_EN';
    check_that(DBMS_LOB.COMPARE(l_renewal_en,l_current_template)=0,'English renewal template must be preserved.');
    SELECT body_template INTO l_current_template FROM hr_letter_template WHERE template_code='CONTRACT_RENEWAL_BN';
    check_that(DBMS_LOB.COMPARE(l_renewal_bn,l_current_template)=0,'Bengali renewal template must be preserved.');
    SELECT COUNT(*) INTO l_count FROM hr_contract_extension
     WHERE extension_id=l_extension AND status='POSTED' AND new_grade_id IS NULL;
    check_that(l_count=1,'Non-grade draft must post.');
    SELECT COUNT(*) INTO l_hist_after FROM emp_salary_structure_hist WHERE emp_id=l_emp;
    check_that(l_hist_after=l_hist_before,'Unchanged salary must not create salary revisions.');
    SELECT COUNT(*) INTO l_count FROM hr_contract_extension_salary d JOIN emp_salary_structure s ON s.sals_id=d.sals_id
     WHERE d.extension_id=l_extension AND NVL(s.amount,0)<>d.old_amount;
    check_that(l_count=0,'Dates-only posting must preserve live amounts.');
    SELECT body_html INTO l_body FROM hr_employee_letter WHERE letter_id=l_letter AND status='ISSUED';
    check_that(DBMS_LOB.INSTR(l_body,'&lt;manual terms&gt;')>0,'Additional terms must be escaped.');
    check_that(DBMS_LOB.INSTR(l_body,'does not automatically grant')>0,'Letter must not promise automatic benefits.');
    SELECT COUNT(*) INTO l_count FROM employees WHERE id=l_emp AND TRIM(emp_type)=l_type
      AND (l_type<>'1' OR confirmation_due_date=ADD_MONTHS(TRUNC(l_to)+1,12)-1);
    check_that(l_count=1,'Type must be retained; probation end date must extend.');

    BEGIN
        hrms.pkg_hr_contract_extension.delete_draft(l_extension,l_user);
        RAISE_APPLICATION_ERROR(-20800,'Posted extension was deleted.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE<>-20719 THEN RAISE; END IF;
    END;
    BEGIN
        hrms.pkg_hr_contract_extension.final_submit(l_extension,l_user,l_action,l_letter);
        RAISE_APPLICATION_ERROR(-20800,'Posted extension was posted twice.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE<>-20719 THEN RAISE; END IF;
    END;
    ROLLBACK TO TEST_BEFORE_POST;

    /* No grade, salary or Basic is required for a dates-only extension. */
    SAVEPOINT TEST_BEFORE_EMPTY;
    UPDATE emp_salary_structure SET is_active='N' WHERE employee_id=l_emp;
    hrms.pkg_hr_contract_extension.refresh_salary_snapshot(l_extension,l_user);
    save_header;
    hrms.pkg_hr_contract_extension.final_submit(l_extension,l_user,l_action,l_letter);
    SELECT COUNT(*) INTO l_count FROM hr_contract_extension_salary WHERE extension_id=l_extension;
    check_that(l_count=0,'An empty live salary structure must remain empty.');
    SELECT COUNT(*) INTO l_count FROM hr_contract_extension
     WHERE extension_id=l_extension AND status='POSTED' AND new_basic=0 AND new_gross=0;
    check_that(l_count=1,'An employee without salary or Basic must be able to extend.');
    ROLLBACK TO TEST_BEFORE_EMPTY;

    /* A new benefit must come from an explicitly entered head and amount. */
    SELECT MIN(h.head_id) INTO l_head FROM allowance_head h
     WHERE h.is_active='Y' AND NOT EXISTS (SELECT 1 FROM emp_salary_structure s
            WHERE s.employee_id=l_emp AND s.slno=h.head_id);
    IF l_head IS NOT NULL THEN
        SAVEPOINT TEST_BEFORE_NEW_HEAD;
        l_row := NULL;
        hrms.pkg_hr_contract_extension.save_salary_row(l_extension,l_row,l_head,42.50,'Y',l_user);
        save_header;
        hrms.pkg_hr_contract_extension.final_submit(l_extension,l_user,l_action,l_letter);
        SELECT COUNT(*) INTO l_count FROM emp_salary_structure
         WHERE employee_id=l_emp AND slno=l_head AND amount=42.50 AND is_active='Y';
        check_that(l_count=1,'Explicit new head must post exactly the entered amount.');
        ROLLBACK TO TEST_BEFORE_NEW_HEAD;
    END IF;

    /* A changed live amount must invalidate the draft. */
    SELECT MIN(sals_id) INTO l_row FROM emp_salary_structure
     WHERE employee_id=l_emp AND NVL(is_active,'Y')='Y';
    IF l_row IS NOT NULL THEN
        SAVEPOINT TEST_BEFORE_STALE;
        UPDATE emp_salary_structure SET amount=NVL(amount,0)+1 WHERE sals_id=l_row;
        BEGIN
            hrms.pkg_hr_contract_extension.final_submit(l_extension,l_user,l_action,l_letter);
            RAISE_APPLICATION_ERROR(-20800,'Changed live salary was accepted.');
        EXCEPTION WHEN OTHERS THEN
            IF SQLCODE<>-20730 THEN RAISE; END IF;
        END;
        ROLLBACK TO TEST_BEFORE_STALE;
    END IF;

    UPDATE employees SET emp_type='2' WHERE id=l_emp;
    BEGIN
        hrms.pkg_hr_contract_extension.final_submit(l_extension,l_user,l_action,l_letter);
        RAISE_APPLICATION_ERROR(-20800,'Confirmed employee was allowed to extend.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE<>-20713 THEN RAISE; END IF;
    END;

    ROLLBACK TO TEST_MANUAL_EXTENSION;
    DBMS_OUTPUT.PUT_LINE('PASS: manual extension regression; all test DML rolled back.');
EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO TEST_MANUAL_EXTENSION;
    RAISE;
END;
/
UNDEFINE 1;
UNDEFINE 2;
SET DEFINE OFF;
