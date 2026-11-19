/* ONE TEMPORARY PRINT SAMPLE for existing EMPLOYEES.ID = 155008361.
   Run as HRMS in APEX SQL Workshop > SQL Scripts, or SQLcl/SQL*Plus.
   Requires the extension tables, English template, and an active signatory.
   Use a fresh SQL session: this script commits its sample inserts for printing.

   This is a print fixture, not a real employee extension. It never updates
   EMPLOYEES, payroll or contracts. It inserts a clearly marked sample action,
   extension and issued letter. COMMIT makes them visible to APEX Page 523/525.
   Re-running reuses the same sample instead of inserting another one.
   Remove it after printing with 97_remove_temp_print_sample_155008361.sql.
*/
SET SERVEROUTPUT ON;
SET DEFINE OFF;

DECLARE
    c_emp_id       CONSTANT NUMBER := 155008361;
    c_reference    CONSTANT VARCHAR2(30) := 'TMP-CEX-155008361';
    c_marker       CONSTANT VARCHAR2(100) := 'TEMP_PRINT_SAMPLE_155008361';
    c_subject      CONSTANT VARCHAR2(500) := 'SAMPLE - Extension of Confirmation Due Date';

    /* Optional: set to your own numeric HR USER_ID for sample audit columns.
       NULL leaves the sample audit user blank; no user is impersonated. */
    c_user_id      CONSTANT NUMBER := NULL;

    l_extension_id NUMBER;
    l_letter_id    NUMBER;
    l_action_id    NUMBER;
    l_company_id   NUMBER;
    l_signatory_id NUMBER;
    l_template_id  NUMBER;
    l_old_due      DATE;
    l_new_due      DATE;
    l_company      VARCHAR2(200);
    l_employee     VARCHAR2(200);
    l_employee_type VARCHAR2(30);
    l_body         CLOB;
    l_count        PLS_INTEGER;
    l_reason       VARCHAR2(1000);
    l_status       VARCHAR2(20);
    l_created      BOOLEAN := FALSE;
BEGIN
    SAVEPOINT BEFORE_TEMP_PRINT_SAMPLE;

    SELECT COUNT(*) INTO l_count FROM hrms.employees WHERE id = c_emp_id;
    IF l_count <> 1 THEN
        RAISE_APPLICATION_ERROR(-20810, 'Employee ID 155008361 was not found. This script needs that existing employee.');
    END IF;

    SELECT e.com_id, TRIM(e.f_name || ' ' || e.l_name), c.name,
           NVL(TRUNC(e.confirmation_due_date), TRUNC(SYSDATE)),
           CASE TRIM(e.emp_type) WHEN '1' THEN 'probationary' WHEN '3' THEN 'contractual' ELSE 'current' END
      INTO l_company_id, l_employee, l_company, l_old_due, l_employee_type
      FROM hrms.employees e
      LEFT JOIN hrms.company c ON c.id = e.com_id
     WHERE e.id = c_emp_id;
    IF l_company_id IS NULL THEN
        RAISE_APPLICATION_ERROR(-20810, 'Employee 155008361 needs an existing company to view the letter in APEX.');
    END IF;
    l_new_due := ADD_MONTHS(l_old_due, 3);

    SELECT COUNT(*) INTO l_count FROM hrms.hr_contract_extension
     WHERE extension_no = c_reference;
    IF l_count > 0 THEN
        SELECT extension_id, letter_id, reason, status
          INTO l_extension_id, l_letter_id, l_reason, l_status
          FROM hrms.hr_contract_extension
         WHERE extension_no = c_reference AND emp_id = c_emp_id;
        IF NVL(l_reason, '?') <> c_marker OR l_status <> 'POSTED' OR l_letter_id IS NULL THEN
            RAISE_APPLICATION_ERROR(-20810, 'The sample reference already exists with different data. Nothing was overwritten.');
        END IF;
        SELECT COUNT(*) INTO l_count FROM hrms.hr_employee_letter
         WHERE letter_id = l_letter_id AND contract_extension_id = l_extension_id
           AND status = 'ISSUED' AND subject_text = c_subject;
        IF l_count <> 1 THEN
            RAISE_APPLICATION_ERROR(-20810, 'Existing sample letter does not match. Review it before creating another sample.');
        END IF;
    ELSE
        SELECT MIN(signatory_id) KEEP (DENSE_RANK FIRST ORDER BY display_order, signatory_id)
          INTO l_signatory_id FROM hrms.hr_letter_signatory WHERE is_active = 'Y';
        IF l_signatory_id IS NULL THEN
            RAISE_APPLICATION_ERROR(-20810, 'Activate a letter signatory before creating the sample.');
        END IF;
        SELECT template_id, body_template INTO l_template_id, l_body
          FROM hrms.hr_letter_template
         WHERE template_code = 'CONTRACT_EXTENSION_EN'
           AND action_type = 'CONTRACT_EXTENSION' AND is_active = 'Y';

        INSERT INTO hrms.hr_employee_action (
            emp_id, action_type, action_date, effective_date,
            old_effective_date, new_effective_date, reason, remarks,
            approval_status, ent_by, ent_date, approved_by, approved_date)
        VALUES (
            c_emp_id, 'CONTRACT_EXTENSION', SYSDATE, l_old_due + 1,
            l_old_due, l_new_due, c_marker,
            'Temporary print preview only. Employee confirmation due date was NOT changed.',
            'APPROVED', c_user_id, SYSDATE, c_user_id, SYSDATE)
        RETURNING action_id INTO l_action_id;

        INSERT INTO hrms.hr_contract_extension (
            extension_no, emp_id, action_id,
            emp_code_snapshot, emp_name_snapshot, emp_type_snapshot,
            designation_snapshot, department_snapshot, location_snapshot,
            address_snapshot, company_snapshot, grade_snapshot,
            current_from_date, current_to_date, new_from_date, new_to_date,
            reason, remarks, signatory_id, template_id, status,
            posted_by, posted_date, created_by)
        SELECT c_reference, e.id, l_action_id,
               NVL(e.emp_id, TO_CHAR(e.id)),
               SUBSTR(TRIM(e.f_name || ' ' || e.l_name), 1, 180) || ' (SAMPLE)', TRIM(e.emp_type),
               d.designation, dp.dept_name, loc.name, e.address, c.name, e.grade,
               LEAST(NVL(TRUNC(e.join_date), l_old_due), l_old_due),
               l_old_due, l_old_due + 1, l_new_due,
               c_marker, 'Temporary print preview only. No employee dates or other data changed.',
               l_signatory_id, l_template_id, 'POSTED', c_user_id, SYSDATE, c_user_id
          FROM hrms.employees e
          LEFT JOIN hrms.designations d ON d.id = e.desig_id
          LEFT JOIN hrms.departments dp ON dp.id = e.dept_id
          LEFT JOIN hrms.locations loc ON loc.id = e.loc_id
          LEFT JOIN hrms.company c ON c.id = e.com_id
         WHERE e.id = c_emp_id;
        SELECT extension_id INTO l_extension_id FROM hrms.hr_contract_extension
         WHERE extension_no = c_reference;

        l_body := REPLACE(l_body, '#COMPANY_NAME#', apex_escape.html(l_company));
        l_body := REPLACE(l_body, '#EMP_NAME#', apex_escape.html(l_employee));
        l_body := REPLACE(l_body, '#EMPLOYMENT_TYPE#', l_employee_type);
        l_body := REPLACE(l_body, '#CURRENT_TO_DATE#',
            TO_CHAR(l_old_due, 'DD Month YYYY', 'NLS_DATE_LANGUAGE=English'));
        l_body := REPLACE(l_body, '#NEW_FROM_DATE#',
            TO_CHAR(l_old_due + 1, 'DD Month YYYY', 'NLS_DATE_LANGUAGE=English'));
        l_body := REPLACE(l_body, '#NEW_TO_DATE#',
            TO_CHAR(l_new_due, 'DD Month YYYY', 'NLS_DATE_LANGUAGE=English'));
        l_body := REPLACE(l_body, '#SALARY_DETAILS#', NULL);
        l_body := REPLACE(l_body, '#SPECIAL_TERMS#', NULL);
        l_body := TO_CLOB('<p><strong>SAMPLE FOR PRINT PREVIEW ONLY</strong></p>') || l_body;

        INSERT INTO hrms.hr_employee_letter (
            emp_id, action_id, contract_extension_id, template_id,
            letter_no, letter_date, subject_text, body_html, status,
            generated_by, generated_date, approved_by, approved_date, issued_by, issued_date)
        VALUES (
            c_emp_id, l_action_id, l_extension_id, l_template_id,
            c_reference, SYSDATE, c_subject, l_body, 'ISSUED',
            c_user_id, SYSDATE, c_user_id, SYSDATE, c_user_id, SYSDATE)
        RETURNING letter_id INTO l_letter_id;

        UPDATE hrms.hr_contract_extension SET letter_id = l_letter_id
         WHERE extension_id = l_extension_id;
        l_created := TRUE;
    END IF;

    DBMS_OUTPUT.PUT_LINE('Sample reference: ' || c_reference);
    DBMS_OUTPUT.PUT_LINE('P525_EXTENSION_ID = ' || l_extension_id);
    DBMS_OUTPUT.PUT_LINE('P525_COM_ID = ' || l_company_id);
    DBMS_OUTPUT.PUT_LINE('Open Page 523, select company ' || l_company_id
        || ', then Print Letter on ' || c_reference || '.');
    DBMS_OUTPUT.PUT_LINE('Employee 155008361 confirmation date, salary and other data remain unchanged.');
    /* APEX uses a separate session. Reusing an existing sample needs no commit. */
    IF l_created THEN
        COMMIT;
    END IF;
EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO BEFORE_TEMP_PRINT_SAMPLE;
    RAISE;
END;
/

/* These values also appear here if SQL Workshop hides DBMS_OUTPUT. */
SELECT r.extension_no, r.emp_code_snapshot AS employee_code,
       r.emp_name_snapshot AS employee_name,
       r.current_to_date AS previous_confirmation_due_date,
       r.new_to_date AS extended_confirmation_due_date,
       r.extension_id AS p525_extension_id, e.com_id AS p525_com_id,
       r.letter_id, r.status
  FROM hrms.hr_contract_extension r
  JOIN hrms.employees e ON e.id = r.emp_id
 WHERE r.emp_id = 155008361 AND r.extension_no = 'TMP-CEX-155008361'
   AND r.reason = 'TEMP_PRINT_SAMPLE_155008361';
