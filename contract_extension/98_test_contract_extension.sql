/* Run ONLY in a disposable HRMS test database:
     @98_test_contract_extension.sql employee_internal_id authenticated_user_id
   Employee must be eligible/authorized, with an existing confirmation due date, no open draft,
   an active signatory and no concurrent activity. All test DML rolls back.
   Identity/sequence values are consumed. */
SET DEFINE ON;
SET SERVEROUTPUT ON;
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK;

DECLARE
    l_emp NUMBER := &1;
    l_user NUMBER := &2;
    l_from DATE;
    l_to DATE;
    l_contract_before CLOB;
    l_contract_after CLOB;
    l_type VARCHAR2(30);
    l_extension NUMBER;
    l_duplicate NUMBER;
    l_salary_id NUMBER;
    l_sign NUMBER;
    l_version NUMBER;
    l_action NUMBER;
    l_letter NUMBER;
    l_count PLS_INTEGER;
    l_hist_before PLS_INTEGER;
    l_extension_count PLS_INTEGER;
    l_action_count PLS_INTEGER;
    l_letter_count PLS_INTEGER;
    l_body CLOB;
    l_salary_before CLOB;
    l_salary_after CLOB;
    l_renewal_count PLS_INTEGER;
    l_renewal_version NUMBER;
    l_renewal_en CLOB;
    l_renewal_bn CLOB;
    l_current_template CLOB;
    l_employee employees%ROWTYPE;

    PROCEDURE check_that(p_true BOOLEAN,p_message VARCHAR2) IS
    BEGIN
        IF p_true IS NULL OR NOT p_true THEN
            RAISE_APPLICATION_ERROR(-20800,p_message);
        END IF;
    END;

    /* Compare every live salary column, including inactive heads and audit fields. */
    FUNCTION salary_snapshot RETURN CLOB IS
        l_result CLOB;
    BEGIN
        SELECT JSON_ARRAYAGG(JSON_OBJECT(
            'id' VALUE sals_id, 'employee' VALUE employee_id, 'head' VALUE slno,
            'code' VALUE headcode, 'amount' VALUE amount, 'revision' VALUE revision_type,
            'active' VALUE is_active, 'created_by' VALUE created_by,
            'created_date' VALUE created_date, 'updated_by' VALUE updated_by,
            'updated_date' VALUE updated_date RETURNING CLOB)
            ORDER BY sals_id RETURNING CLOB)
          INTO l_result FROM emp_salary_structure WHERE employee_id=l_emp;
        RETURN l_result;
    END;

    FUNCTION contract_snapshot RETURN CLOB IS
        l_result CLOB;
    BEGIN
        SELECT JSON_ARRAYAGG(JSON_OBJECT(
            'emp_id' VALUE emp_id,
            'contract_from_date' VALUE contract_from_date,
            'contract_to_date' VALUE contract_to_date,
            'grade_id' VALUE grade_id,
            'scale_id' VALUE scale_id,
            'step_no' VALUE step_no,
            'latest_renewal_id' VALUE latest_renewal_id,
            'contract_status' VALUE contract_status,
            'created_by' VALUE created_by,
            'created_date' VALUE created_date,
            'updated_by' VALUE updated_by,
            'updated_date' VALUE updated_date RETURNING CLOB)
            ORDER BY emp_id RETURNING CLOB)
          INTO l_result FROM hr_employee_contract WHERE emp_id=l_emp;
        RETURN l_result;
    END;

    PROCEDURE save_header IS
    BEGIN
        hrms.pkg_hr_contract_extension.save_draft(l_extension,TRUNC(l_to)+1,
            ADD_MONTHS(TRUNC(l_to)+1,3)-1,'Probation/contract extension test',
            'Internal history note',NULL,l_sign,l_user);
    END;

    PROCEDURE prepare IS
    BEGIN
        hrms.pkg_hr_contract_extension.create_due_extension(
            p_emp_id=>l_emp,p_term_months=>3,p_user_id=>l_user,p_extension_id=>l_extension);
        SELECT signatory_id INTO l_sign FROM hr_contract_extension WHERE extension_id=l_extension;
        check_that(l_sign IS NOT NULL,'Activate a real signatory before running the test.');
        save_header;
    END;
BEGIN
    SAVEPOINT TEST_DATES_EXTENSION;
    SELECT current_from_date,current_to_date,emp_type INTO l_from,l_to,l_type
      FROM v_hr_contract_ext_eligible WHERE emp_id=l_emp;
    check_that(l_to IS NOT NULL,'Choose an employee with an existing confirmation due date.');
    SELECT COUNT(*) INTO l_count FROM hr_contract_extension WHERE emp_id=l_emp AND status='DRAFT';
    check_that(l_count=0,'Choose an employee without a draft.');
    SELECT * INTO l_employee FROM employees WHERE id=l_emp;
    SELECT COUNT(*),NVL(SUM(version_no),0) INTO l_renewal_count,l_renewal_version
      FROM hr_contract_renewal WHERE emp_id=l_emp;
    l_contract_before := contract_snapshot;
    SELECT body_template INTO l_renewal_en FROM hr_letter_template WHERE template_code='CONTRACT_RENEWAL_EN';
    SELECT body_template INTO l_renewal_bn FROM hr_letter_template WHERE template_code='CONTRACT_RENEWAL_BN';
    SELECT COUNT(*) INTO l_hist_before FROM emp_salary_structure_hist WHERE emp_id=l_emp;
    l_salary_before := salary_snapshot;
    prepare;
    SELECT COUNT(*) INTO l_count FROM hr_contract_extension_salary WHERE extension_id=l_extension;
    check_that(l_count=0,'New extensions must not create salary snapshots.');

    BEGIN
        hrms.pkg_hr_contract_extension.create_due_extension(l_emp,'MANUAL',3,l_user,l_duplicate);
        RAISE_APPLICATION_ERROR(-20800,'Duplicate draft was accepted.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE<>-20714 THEN RAISE; END IF;
    END;
    BEGIN
        hrms.pkg_hr_contract_extension.save_salary_row(l_extension,l_salary_id,NULL,100,'Y',l_user);
        RAISE_APPLICATION_ERROR(-20800,'Salary editing was accepted.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE<>-20740 THEN RAISE; END IF;
    END;
    BEGIN
        hrms.pkg_hr_contract_extension.refresh_salary_snapshot(l_extension,l_user);
        RAISE_APPLICATION_ERROR(-20800,'Salary refresh was accepted.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE<>-20740 THEN RAISE; END IF;
    END;
    BEGIN
        hrms.pkg_hr_contract_extension.save_draft(l_extension,TRUNC(l_to)+1,
            ADD_MONTHS(TRUNC(l_to)+1,3)-1,' ',NULL,NULL,l_sign,l_user);
        RAISE_APPLICATION_ERROR(-20800,'Missing history reason was accepted.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE<>-20710 THEN RAISE; END IF;
    END;
    BEGIN
        hrms.pkg_hr_contract_extension.save_draft(l_extension,TRUNC(l_to)+1,
            ADD_MONTHS(TRUNC(l_to)+1,3)-1,'Reason',NULL,TO_CLOB('Change benefits'),l_sign,l_user);
        RAISE_APPLICATION_ERROR(-20800,'Changed employment terms were accepted.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE<>-20740 THEN RAISE; END IF;
    END;
    SELECT version_no INTO l_version FROM hr_contract_extension WHERE extension_id=l_extension;
    save_header;
    BEGIN
        hrms.pkg_hr_contract_extension.lock_draft(l_extension,l_user,l_version);
        RAISE_APPLICATION_ERROR(-20800,'Stale draft version was accepted.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE<>-20721 THEN RAISE; END IF;
    END;

    /* Simulate an old draft containing proposed pay changes. They must be ignored. */
    INSERT INTO hr_contract_extension_salary (
        extension_id,emp_id,sals_id,slno,headcode,old_amount,new_amount,created_by)
    SELECT l_extension,l_emp,sals_id,slno,headcode,NVL(amount,0),NVL(amount,0)+10,l_user
      FROM emp_salary_structure
     WHERE employee_id=l_emp AND NVL(is_active,'Y')='Y' AND NVL(amount,0)>=0
       AND slno IS NOT NULL AND headcode IS NOT NULL;
    UPDATE hr_contract_extension SET old_basic=0,new_basic=100,old_gross=0,new_gross=100
     WHERE extension_id=l_extension;
    SAVEPOINT BEFORE_TEST_POST;
    hrms.pkg_hr_contract_extension.final_submit(l_extension,l_user,l_action,l_letter);
    check_that(l_action IS NOT NULL AND l_letter IS NOT NULL,'Post must produce history and letter.');
    SELECT COUNT(*) INTO l_count FROM hr_employee_action
     WHERE action_id=l_action AND emp_id=l_emp AND action_type='CONTRACT_EXTENSION'
       AND old_effective_date=TRUNC(l_to) AND new_effective_date=ADD_MONTHS(TRUNC(l_to)+1,3)-1
       AND reason='Probation/contract extension test' AND remarks='Internal history note'
       AND ent_by=l_user AND ent_date IS NOT NULL
       AND old_basic IS NULL AND new_basic IS NULL AND old_gross IS NULL AND new_gross IS NULL;
    check_that(l_count=1,'History must record old/new dates, reason, user/time and no salary changes.');
    SELECT COUNT(*) INTO l_count FROM hr_contract_extension
     WHERE extension_id=l_extension AND status='POSTED' AND posted_by=l_user AND posted_date IS NOT NULL;
    check_that(l_count=1,'Extension history must be posted with authenticated user/time.');
    l_contract_after := contract_snapshot;
    check_that((l_contract_before IS NULL AND l_contract_after IS NULL)
        OR DBMS_LOB.COMPARE(l_contract_before,l_contract_after)=0,
        'Every contract column must remain unchanged; absent contract rows must stay absent.');
    SELECT COUNT(*) INTO l_count FROM hr_employee_letter l JOIN hr_letter_template t ON t.template_id=l.template_id
     WHERE l.letter_id=l_letter AND l.contract_extension_id=l_extension AND l.status='ISSUED'
       AND l.contract_renewal_id IS NULL AND t.template_code='CONTRACT_EXTENSION_EN';
    check_that(l_count=1,'Letter must link to its extension and use the extension template.');
    SELECT body_html INTO l_body FROM hr_employee_letter WHERE letter_id=l_letter;
    check_that(DBMS_LOB.INSTR(l_body,'Your salary and other benefits will remain unchanged')>0,
        'Letter must preserve existing salary and benefits.');
    check_that(DBMS_LOB.INSTR(l_body,'#SALARY_DETAILS#')=0 AND DBMS_LOB.INSTR(l_body,'#NEW_TO_DATE#')=0
        AND DBMS_LOB.INSTR(l_body,'Internal history note')=0,'Letter must resolve dates and keep history notes internal.');
    l_salary_after := salary_snapshot;
    check_that((l_salary_before IS NULL AND l_salary_after IS NULL)
        OR DBMS_LOB.COMPARE(l_salary_before,l_salary_after)=0,'All live salary columns must remain exactly unchanged.');
    SELECT COUNT(*) INTO l_count FROM emp_salary_structure_hist WHERE emp_id=l_emp;
    check_that(l_count=l_hist_before,'Extension must not create salary revisions.');
    /* Every other employee column, including audit fields and photo, is unchanged. */
    SELECT COUNT(*) INTO l_count FROM employees e WHERE e.id=l_emp
       AND DECODE(e.id,l_employee.id,1,0)=1
       AND DECODE(e.emp_id,l_employee.emp_id,1,0)=1
       AND DECODE(e.f_name,l_employee.f_name,1,0)=1
       AND DECODE(e.l_name,l_employee.l_name,1,0)=1
       AND DECODE(e.dob,l_employee.dob,1,0)=1
       AND DECODE(e.mobile,l_employee.mobile,1,0)=1
       AND DECODE(e.email,l_employee.email,1,0)=1
       AND DECODE(e.father,l_employee.father,1,0)=1
       AND DECODE(e.mother,l_employee.mother,1,0)=1
       AND DECODE(e.gender,l_employee.gender,1,0)=1
       AND DECODE(e.height,l_employee.height,1,0)=1
       AND DECODE(e.weight,l_employee.weight,1,0)=1
       AND DECODE(e.blood,l_employee.blood,1,0)=1
       AND DECODE(e.nid,l_employee.nid,1,0)=1
       AND DECODE(e.address,l_employee.address,1,0)=1
       AND DECODE(e.c_post,l_employee.c_post,1,0)=1
       AND DECODE(e.c_thana,l_employee.c_thana,1,0)=1
       AND DECODE(e.c_district,l_employee.c_district,1,0)=1
       AND DECODE(e.c_division,l_employee.c_division,1,0)=1
       AND DECODE(e.p_address,l_employee.p_address,1,0)=1
       AND DECODE(e.p_post,l_employee.p_post,1,0)=1
       AND DECODE(e.p_thana,l_employee.p_thana,1,0)=1
       AND DECODE(e.p_district,l_employee.p_district,1,0)=1
       AND DECODE(e.p_division,l_employee.p_division,1,0)=1
       AND DECODE(e.join_date,l_employee.join_date,1,0)=1
       AND DECODE(e.marital_status,l_employee.marital_status,1,0)=1
       AND DECODE(e.emp_type,l_employee.emp_type,1,0)=1
       AND DECODE(e.dept_id,l_employee.dept_id,1,0)=1
       AND DECODE(e.loc_id,l_employee.loc_id,1,0)=1
       AND DECODE(e.branch_id,l_employee.branch_id,1,0)=1
       AND DECODE(e.desig_id,l_employee.desig_id,1,0)=1
       AND DECODE(e.com_id,l_employee.com_id,1,0)=1
       AND DECODE(e.job_id,l_employee.job_id,1,0)=1
       AND DECODE(e.user_grp,l_employee.user_grp,1,0)=1
       AND DECODE(e.passw,l_employee.passw,1,0)=1
       AND DECODE(e.ent_by,l_employee.ent_by,1,0)=1
       AND DECODE(e.ent_date,l_employee.ent_date,1,0)=1
       AND DECODE(e.upd_by,l_employee.upd_by,1,0)=1
       AND DECODE(e.upd_date,l_employee.upd_date,1,0)=1
       AND DECODE(e.status,l_employee.status,1,0)=1
       AND DECODE(e.mime_type,l_employee.mime_type,1,0)=1
       AND DECODE(e.file_name,l_employee.file_name,1,0)=1
       AND DECODE(e.empno,l_employee.empno,1,0)=1
       AND DECODE(e.religion,l_employee.religion,1,0)=1
       AND DECODE(e.att_dev_id,l_employee.att_dev_id,1,0)=1
       AND DECODE(e.section_id,l_employee.section_id,1,0)=1
       AND DECODE(e.mc_id,l_employee.mc_id,1,0)=1
       AND DECODE(e.str_id,l_employee.str_id,1,0)=1
       AND DECODE(e.empid,l_employee.empid,1,0)=1
       AND DECODE(e.retirement_date,l_employee.retirement_date,1,0)=1
       AND DECODE(e.resp,l_employee.resp,1,0)=1
       AND DECODE(e.sep_date,l_employee.sep_date,1,0)=1
       AND DECODE(e.is_same_add,l_employee.is_same_add,1,0)=1
       AND DECODE(e.conf_date,l_employee.conf_date,1,0)=1
       AND DECODE(e.spouse,l_employee.spouse,1,0)=1
       AND DECODE(e.passport,l_employee.passport,1,0)=1
       AND DECODE(e.father_c,l_employee.father_c,1,0)=1
       AND DECODE(e.mother_c,l_employee.mother_c,1,0)=1
       AND DECODE(e.spouse_c,l_employee.spouse_c,1,0)=1
       AND DECODE(e.field_force,l_employee.field_force,1,0)=1
       AND DECODE(e.probation_period_months,l_employee.probation_period_months,1,0)=1
       AND DECODE(e.increment_cycle_months,l_employee.increment_cycle_months,1,0)=1
       AND DECODE(e.last_increment_date,l_employee.last_increment_date,1,0)=1
       AND DECODE(e.next_increment_date,l_employee.next_increment_date,1,0)=1
       AND DECODE(e.increment_hold_status,l_employee.increment_hold_status,1,0)=1
       AND DECODE(e.increment_hold_reason,l_employee.increment_hold_reason,1,0)=1
       AND DECODE(e.increment_hold_date,l_employee.increment_hold_date,1,0)=1
       AND DECODE(e.eb_status,l_employee.eb_status,1,0)=1
       AND DECODE(e.grade,l_employee.grade,1,0)=1
       AND ((e.photo IS NULL AND l_employee.photo IS NULL)
         OR DBMS_LOB.COMPARE(e.photo,l_employee.photo)=0)
       AND e.confirmation_due_date=ADD_MONTHS(TRUNC(l_to)+1,3)-1;
    check_that(l_count=1,'Only confirmation due date may change on the employee.');
    SELECT COUNT(*) INTO l_count FROM hr_contract_renewal WHERE emp_id=l_emp;
    check_that(l_count=l_renewal_count,'No renewal rows may be created.');
    SELECT NVL(SUM(version_no),0) INTO l_version FROM hr_contract_renewal WHERE emp_id=l_emp;
    check_that(l_version=l_renewal_version,'Renewal rows must remain unchanged.');
    SELECT body_template INTO l_current_template FROM hr_letter_template WHERE template_code='CONTRACT_RENEWAL_EN';
    check_that(DBMS_LOB.COMPARE(l_renewal_en,l_current_template)=0,'English renewal template must be retained.');
    SELECT body_template INTO l_current_template FROM hr_letter_template WHERE template_code='CONTRACT_RENEWAL_BN';
    check_that(DBMS_LOB.COMPARE(l_renewal_bn,l_current_template)=0,'Bengali renewal template must be retained.');
    BEGIN
        hrms.pkg_hr_contract_extension.final_submit(l_extension,l_user,l_action,l_letter);
        RAISE_APPLICATION_ERROR(-20800,'Duplicate posting was accepted.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE<>-20719 THEN RAISE; END IF;
    END;
    BEGIN
        hrms.pkg_hr_contract_extension.delete_draft(l_extension,l_user);
        RAISE_APPLICATION_ERROR(-20800,'Posted history was deleted.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE<>-20719 THEN RAISE; END IF;
    END;
    ROLLBACK TO BEFORE_TEST_POST;

    /* Unrelated payroll edits do not block a dates-only extension. */
    SAVEPOINT BEFORE_PAYROLL_CHANGE;
    UPDATE emp_salary_structure SET amount=NVL(amount,0)+1 WHERE employee_id=l_emp;
    l_salary_before := salary_snapshot;
    hrms.pkg_hr_contract_extension.final_submit(l_extension,l_user,l_action,l_letter);
    l_salary_after := salary_snapshot;
    check_that((l_salary_before IS NULL AND l_salary_after IS NULL)
        OR DBMS_LOB.COMPARE(l_salary_before,l_salary_after)=0,'Posting must preserve unrelated payroll edits.');
    ROLLBACK TO BEFORE_PAYROLL_CHANGE;

    /* Stale end/due dates cannot overwrite newer employee data. */
    SAVEPOINT BEFORE_STALE_DATE;
    UPDATE employees SET confirmation_due_date=confirmation_due_date+1 WHERE id=l_emp;
    BEGIN
        hrms.pkg_hr_contract_extension.final_submit(l_extension,l_user,l_action,l_letter);
        RAISE_APPLICATION_ERROR(-20800,'Stale dates were accepted.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE<>-20729 THEN RAISE; END IF;
    END;
    ROLLBACK TO BEFORE_STALE_DATE;
    SAVEPOINT BEFORE_TYPE_CHANGE;
    UPDATE employees SET emp_type='2' WHERE id=l_emp;
    BEGIN
        hrms.pkg_hr_contract_extension.final_submit(l_extension,l_user,l_action,l_letter);
        RAISE_APPLICATION_ERROR(-20800,'Confirmed employee was allowed to extend.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE<>-20713 THEN RAISE; END IF;
    END;
    ROLLBACK TO BEFORE_TYPE_CHANGE;

    /* Future confirmation due dates need no grade, salary or contract record. */
    hrms.pkg_hr_contract_extension.delete_draft(l_extension,l_user);
    l_to := GREATEST(ADD_MONTHS(TRUNC(SYSDATE),1),TRUNC(l_from));
    UPDATE employees SET grade=NULL,
        confirmation_due_date=l_to WHERE id=l_emp;
    UPDATE emp_salary_structure SET is_active='N' WHERE employee_id=l_emp;
    l_salary_before := salary_snapshot;
    prepare;
    hrms.pkg_hr_contract_extension.final_submit(l_extension,l_user,l_action,l_letter);
    SELECT COUNT(*) INTO l_count FROM hr_contract_extension
     WHERE extension_id=l_extension AND status='POSTED' AND new_from_date>TRUNC(SYSDATE);
    check_that(l_count=1,'Future, non-grade, no-active-salary extension must post.');
    l_salary_after := salary_snapshot;
    check_that((l_salary_before IS NULL AND l_salary_after IS NULL)
        OR DBMS_LOB.COMPARE(l_salary_before,l_salary_after)=0,'Inactive salary rows must also be preserved.');

    ROLLBACK TO TEST_DATES_EXTENSION;

    /* Simple Page 524 API: one Save, all-or-nothing, no leftover draft. */
    l_to := TRUNC(l_employee.confirmation_due_date);
    l_extension := NULL;
    l_letter := NULL;
    SELECT COUNT(*) INTO l_extension_count FROM hr_contract_extension WHERE emp_id=l_emp;
    SELECT COUNT(*) INTO l_action_count FROM hr_employee_action WHERE emp_id=l_emp;
    SELECT COUNT(*) INTO l_letter_count FROM hr_employee_letter WHERE emp_id=l_emp;
    l_salary_before := salary_snapshot;
    l_contract_before := contract_snapshot;
    BEGIN
        hrms.pkg_hr_contract_extension.extend_confirmation_date(
            l_emp,l_to-1,ADD_MONTHS(l_to+1,3)-1,'Simple save test',l_user,l_extension,l_letter);
        RAISE_APPLICATION_ERROR(-20800,'Simple Save accepted a stale displayed due date.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE<>-20729 THEN RAISE; END IF;
    END;
    BEGIN
        hrms.pkg_hr_contract_extension.extend_confirmation_date(
            l_emp,l_to,l_to,'Simple save test',l_user,l_extension,l_letter);
        RAISE_APPLICATION_ERROR(-20800,'Simple Save accepted a date that was not extended.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE<>-20702 THEN RAISE; END IF;
    END;

    /* Fail during letter creation, after posting has started; everything rolls back. */
    SAVEPOINT BEFORE_INVALID_SIGNATORY;
    SELECT MIN(signatory_id) INTO l_sign FROM hr_letter_signatory WHERE is_active='Y';
    check_that(l_sign IS NOT NULL,'An active signatory is required.');
    UPDATE hr_letter_signatory SET is_active='N' WHERE signatory_id=l_sign;
    BEGIN
        hrms.pkg_hr_contract_extension.extend_confirmation_date(
            l_emp,l_to,ADD_MONTHS(l_to+1,3)-1,'Simple save test',l_user,l_extension,l_letter,l_sign);
        RAISE_APPLICATION_ERROR(-20800,'Simple Save accepted an inactive signatory.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE<>-20722 THEN RAISE; END IF;
    END;
    SELECT COUNT(*) INTO l_count FROM employees WHERE id=l_emp AND confirmation_due_date=l_employee.confirmation_due_date;
    check_that(l_count=1,'Failed Save must restore the original confirmation due date.');
    SELECT COUNT(*) INTO l_count FROM hr_contract_extension WHERE emp_id=l_emp;
    check_that(l_count=l_extension_count,'Failed Save must leave no extension or draft.');
    SELECT COUNT(*) INTO l_count FROM hr_employee_action WHERE emp_id=l_emp;
    check_that(l_count=l_action_count,'Failed Save must leave no action record.');
    SELECT COUNT(*) INTO l_count FROM hr_employee_letter WHERE emp_id=l_emp;
    check_that(l_count=l_letter_count,'Failed Save must leave no letter record.');
    ROLLBACK TO BEFORE_INVALID_SIGNATORY;

    hrms.pkg_hr_contract_extension.extend_confirmation_date(
        l_emp,l_to,ADD_MONTHS(l_to+1,3)-1,'Simple save test',l_user,l_extension,l_letter);
    SELECT COUNT(*) INTO l_count FROM hr_contract_extension
     WHERE extension_id=l_extension AND status='POSTED' AND letter_id=l_letter;
    check_that(l_count=1,'One Save must create a posted, printable extension.');
    SELECT COUNT(*) INTO l_count FROM hr_contract_extension WHERE emp_id=l_emp AND status='DRAFT';
    check_that(l_count=0,'Successful simple Save must leave no draft.');
    SELECT COUNT(*) INTO l_count FROM employees
     WHERE id=l_emp AND confirmation_due_date=ADD_MONTHS(l_to+1,3)-1;
    check_that(l_count=1,'Simple Save must extend the confirmation due date.');
    l_salary_after := salary_snapshot;
    check_that((l_salary_before IS NULL AND l_salary_after IS NULL)
        OR DBMS_LOB.COMPARE(l_salary_before,l_salary_after)=0,'Simple Save must preserve payroll exactly.');
    l_contract_after := contract_snapshot;
    check_that((l_contract_before IS NULL AND l_contract_after IS NULL)
        OR DBMS_LOB.COMPARE(l_contract_before,l_contract_after)=0,'Simple Save must preserve all contract data.');

    ROLLBACK TO TEST_DATES_EXTENSION;
    DBMS_OUTPUT.PUT_LINE('PASS: confirmation-date-only extension regression; all test DML rolled back.');
EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO TEST_DATES_EXTENSION;
    RAISE;
END;
/
UNDEFINE 1;
UNDEFINE 2;
SET DEFINE OFF;
