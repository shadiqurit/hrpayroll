/* ============================================================================
   HRMS PROMOTION: FINAL SUBMIT, SALARY POSTING AND LETTER GENERATION

   The APEX page first saves HR_EMPLOYEE_PROMOTION and
   HR_PROMOTION_SALARY_DTL as DRAFT data. The final Submit button calls
   SUBMIT_AND_POST once.

   EMP_SALARY_STRUCTURE is a current-state table, not an effective-dated table.
   Therefore a future-dated promotion is rejected. Old/new values are written
   to EMP_SALARY_STRUCTURE_HIST before the live structure is changed.

   There is deliberately no COMMIT or full ROLLBACK in this package. APEX owns
   the page transaction. The local savepoint only makes the routine atomic if a
   caller catches its exception.
   ============================================================================ */

CREATE OR REPLACE PACKAGE HRMS.pkg_hr_promotion AS
    PROCEDURE submit_and_post (
        p_promotion_id IN  NUMBER,
        p_user_id      IN  NUMBER,
        p_template_id  IN  NUMBER,
        p_action_id    OUT NUMBER,
        p_letter_id    OUT NUMBER
    );
END pkg_hr_promotion;
/

CREATE OR REPLACE PACKAGE BODY HRMS.pkg_hr_promotion AS

    FUNCTION money (p_amount IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(
            NVL(p_amount, 0),
            'FM999G999G999G990D00',
            'NLS_NUMERIC_CHARACTERS=''.,'''
        );
    END money;

    FUNCTION html (p_value IN VARCHAR2) RETURN VARCHAR2 IS
        l_value VARCHAR2(32767) := NVL(p_value, '');
    BEGIN
        l_value := REPLACE(l_value, '&', '&amp;');
        l_value := REPLACE(l_value, '<', '&lt;');
        l_value := REPLACE(l_value, '>', '&gt;');
        l_value := REPLACE(l_value, '"', '&quot;');
        l_value := REPLACE(l_value, '''', '&#39;');
        RETURN l_value;
    END html;

    PROCEDURE submit_and_post (
        p_promotion_id IN  NUMBER,
        p_user_id      IN  NUMBER,
        p_template_id  IN  NUMBER,
        p_action_id    OUT NUMBER,
        p_letter_id    OUT NUMBER
    ) IS
        l_promotion_no       hr_employee_promotion.promotion_no%TYPE;
        l_existing_action_id hr_employee_promotion.action_id%TYPE;
        l_emp_id             hr_employee_promotion.emp_id%TYPE;
        l_promotion_type     hr_employee_promotion.promotion_type%TYPE;
        l_accelerated_count  hr_employee_promotion.accelerated_count%TYPE;
        l_effective_date     hr_employee_promotion.effective_date%TYPE;
        l_old_emp_type_id    hr_employee_promotion.old_emp_type_id%TYPE;
        l_new_emp_type_id    hr_employee_promotion.new_emp_type_id%TYPE;
        l_old_job_id         hr_employee_promotion.old_job_id%TYPE;
        l_new_job_id         hr_employee_promotion.new_job_id%TYPE;
        l_old_desig_id       hr_employee_promotion.old_desig_id%TYPE;
        l_new_desig_id       hr_employee_promotion.new_desig_id%TYPE;
        l_old_dept_id        hr_employee_promotion.old_dept_id%TYPE;
        l_new_dept_id        hr_employee_promotion.new_dept_id%TYPE;
        l_header_old_basic   hr_employee_promotion.old_basic%TYPE;
        l_header_new_basic   hr_employee_promotion.new_basic%TYPE;
        l_header_old_gross   hr_employee_promotion.old_gross%TYPE;
        l_reason             hr_employee_promotion.reason%TYPE;
        l_remarks            hr_employee_promotion.remarks%TYPE;
        l_status             hr_employee_promotion.approval_status%TYPE;

        l_emp_code           employees.emp_id%TYPE;
        l_emp_name           VARCHAR2(200);
        l_current_emp_type   employees.emp_type%TYPE;
        l_current_job_id     employees.job_id%TYPE;
        l_current_desig_id   employees.desig_id%TYPE;
        l_current_dept_id    employees.dept_id%TYPE;

        l_old_basic          NUMBER := 0;
        l_new_basic          NUMBER := 0;
        l_old_gross          NUMBER := 0;
        l_new_gross          NUMBER := 0;
        l_increase_amount    NUMBER := 0;
        l_increase_percent   NUMBER := 0;
        l_detail_count       PLS_INTEGER;
        l_bad_count          PLS_INTEGER;

        l_sals_id            emp_salary_structure.sals_id%TYPE;
        l_old_amount         emp_salary_structure.amount%TYPE;

        l_template_id        hr_letter_template.template_id%TYPE;
        l_subject_template   hr_letter_template.subject_template%TYPE;
        l_body_template      hr_letter_template.body_template%TYPE;
        l_subject            hr_employee_letter.subject_text%TYPE;
        l_body               CLOB;
        l_letter_no          hr_employee_letter.letter_no%TYPE;
        l_salary_table       VARCHAR2(32767);
        l_old_designation    designations.designation%TYPE;
        l_new_designation    designations.designation%TYPE;
        l_department         departments.dept_name%TYPE;

        l_error_code         NUMBER;
        l_error_message      VARCHAR2(2000);
    BEGIN
        SAVEPOINT before_promotion_submit;
        p_action_id := NULL;
        p_letter_id := NULL;

        IF p_promotion_id IS NULL THEN
            RAISE_APPLICATION_ERROR(-20600, 'Promotion ID is required.');
        END IF;

        IF p_user_id IS NULL THEN
            RAISE_APPLICATION_ERROR(-20601, 'Numeric application user ID is required.');
        END IF;

        /* Lock the header. This serializes double-clicks and concurrent users. */
        BEGIN
            SELECT promotion_no,
                   action_id,
                   emp_id,
                   promotion_type,
                   accelerated_count,
                   effective_date,
                   old_emp_type_id,
                   new_emp_type_id,
                   old_job_id,
                   new_job_id,
                   old_desig_id,
                   new_desig_id,
                   old_dept_id,
                   new_dept_id,
                   old_basic,
                   new_basic,
                   old_gross,
                   reason,
                   remarks,
                   approval_status
              INTO l_promotion_no,
                   l_existing_action_id,
                   l_emp_id,
                   l_promotion_type,
                   l_accelerated_count,
                   l_effective_date,
                   l_old_emp_type_id,
                   l_new_emp_type_id,
                   l_old_job_id,
                   l_new_job_id,
                   l_old_desig_id,
                   l_new_desig_id,
                   l_old_dept_id,
                   l_new_dept_id,
                   l_header_old_basic,
                   l_header_new_basic,
                   l_header_old_gross,
                   l_reason,
                   l_remarks,
                   l_status
              FROM hr_employee_promotion
             WHERE promotion_id = p_promotion_id
               FOR UPDATE NOWAIT;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20602, 'Promotion was not found.');
        END;

        IF l_status = 'POSTED' THEN
            RAISE_APPLICATION_ERROR(-20603, 'This promotion has already been posted.');
        ELSIF NVL(l_status, '?') <> 'DRAFT' THEN
            RAISE_APPLICATION_ERROR(
                -20604,
                'Only a DRAFT promotion can be finally submitted. Current status: '
                || NVL(l_status, 'NULL') || '.'
            );
        END IF;

        IF l_existing_action_id IS NOT NULL THEN
            RAISE_APPLICATION_ERROR(
                -20621,
                'This DRAFT promotion is already linked to an employee action. Correct its status before posting.'
            );
        END IF;

        IF l_effective_date IS NULL THEN
            RAISE_APPLICATION_ERROR(-20605, 'Promotion effective date is required.');
        ELSIF TRUNC(l_effective_date) > TRUNC(SYSDATE) THEN
            RAISE_APPLICATION_ERROR(
                -20606,
                'Future-dated promotion cannot update the current salary structure. '
                || 'Submit it on or after the effective date.'
            );
        END IF;

        /* Lock the employee and read the true current career values. */
        BEGIN
            SELECT emp_id,
                   TRIM(f_name || ' ' || l_name),
                   emp_type,
                   job_id,
                   desig_id,
                   dept_id
              INTO l_emp_code,
                   l_emp_name,
                   l_current_emp_type,
                   l_current_job_id,
                   l_current_desig_id,
                   l_current_dept_id
              FROM employees
             WHERE id = l_emp_id
               FOR UPDATE NOWAIT;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20607, 'Promotion employee was not found.');
        END;

        IF l_current_emp_type IS NULL
           OR NOT REGEXP_LIKE(TRIM(l_current_emp_type), '^[0-9]+$')
        THEN
            RAISE_APPLICATION_ERROR(
                -20620,
                'Employee type must contain the numeric employee-type ID before promotion can be posted.'
            );
        END IF;

        /* A stale draft must not overwrite a later employee transfer/change. */
        IF (l_old_emp_type_id IS NOT NULL
            AND TO_CHAR(l_old_emp_type_id) <> TRIM(l_current_emp_type))
           OR NVL(l_old_job_id, NVL(l_current_job_id, -1)) <> NVL(l_current_job_id, -1)
           OR NVL(l_old_desig_id, NVL(l_current_desig_id, -1)) <> NVL(l_current_desig_id, -1)
           OR NVL(l_old_dept_id, NVL(l_current_dept_id, -1)) <> NVL(l_current_dept_id, -1)
        THEN
            RAISE_APPLICATION_ERROR(
                -20608,
                'Employee job, designation, department or type changed after this draft was generated. '
                || 'Regenerate the promotion.'
            );
        END IF;

        SELECT COUNT(*)
          INTO l_detail_count
          FROM hr_promotion_salary_dtl
         WHERE promotion_id = p_promotion_id;

        IF l_detail_count = 0 THEN
            RAISE_APPLICATION_ERROR(-20609, 'Promotion salary details are required.');
        END IF;

        SELECT COUNT(*)
          INTO l_bad_count
          FROM hr_promotion_salary_dtl
         WHERE promotion_id = p_promotion_id
           AND (emp_id <> l_emp_id
                OR amount IS NULL
                OR amount < 0
                OR slno IS NULL
                OR headcode IS NULL
                OR NVL(is_posted, 'N') <> 'N');

        IF l_bad_count > 0 THEN
            RAISE_APPLICATION_ERROR(
                -20610,
                'Promotion salary details contain another employee, a missing head, or an invalid amount.'
            );
        END IF;

        SELECT COUNT(*)
          INTO l_bad_count
          FROM (
                SELECT slno
                  FROM hr_promotion_salary_dtl
                 WHERE promotion_id = p_promotion_id
                 GROUP BY slno
                HAVING COUNT(*) > 1

                UNION ALL

                SELECT MIN(slno)
                  FROM hr_promotion_salary_dtl
                 WHERE promotion_id = p_promotion_id
                 GROUP BY LPAD(TRIM(headcode), 3, '0')
                HAVING COUNT(*) > 1
          );

        IF l_bad_count > 0 THEN
            RAISE_APPLICATION_ERROR(-20611, 'A salary head appears more than once in this promotion.');
        END IF;

        /* Lock all existing structure rows before taking the salary snapshot. */
        FOR x IN (
            SELECT sals_id
              FROM emp_salary_structure
             WHERE employee_id = l_emp_id
               FOR UPDATE NOWAIT
        ) LOOP
            NULL;
        END LOOP;

        SELECT NVL(MAX(
                   CASE
                       WHEN LPAD(TRIM(s.headcode), 3, '0') = '001' OR s.slno = 1
                       THEN NVL(s.amount, 0)
                   END
               ), 0),
               NVL(SUM(
                   CASE
                       WHEN ah.head_type = 'EARNING'
                        AND LPAD(TRIM(s.headcode), 3, '0') NOT IN ('025', '026')
                       THEN NVL(s.amount, 0)
                       ELSE 0
                   END
               ), 0)
          INTO l_old_basic,
               l_old_gross
          FROM emp_salary_structure s
               LEFT JOIN allowance_head ah ON ah.head_id = s.slno
         WHERE s.employee_id = l_emp_id
           AND NVL(s.is_active, 'Y') = 'Y';

        SELECT NVL(MAX(
                   CASE
                       WHEN LPAD(TRIM(headcode), 3, '0') = '001' OR slno = 1
                       THEN amount
                   END
               ), 0),
               COUNT(
                   CASE
                       WHEN LPAD(TRIM(headcode), 3, '0') = '001' OR slno = 1
                       THEN 1
                   END
               )
          INTO l_new_basic,
               l_bad_count
          FROM hr_promotion_salary_dtl
         WHERE promotion_id = p_promotion_id;

        IF l_bad_count <> 1 OR l_new_basic <= 0 THEN
            RAISE_APPLICATION_ERROR(
                -20612,
                'Promotion salary details must contain exactly one positive Basic Salary head.'
            );
        END IF;

        IF l_new_basic <= l_old_basic THEN
            RAISE_APPLICATION_ERROR(
                -20613,
                'Promotion Basic Salary must be greater than the current Basic Salary.'
            );
        END IF;

        IF l_header_old_basic IS NOT NULL
           AND ABS(l_header_old_basic - l_old_basic) > 0.005
        THEN
            RAISE_APPLICATION_ERROR(
                -20614,
                'Current Basic Salary changed after the promotion draft was generated. '
                || 'Regenerate the salary details.'
            );
        END IF;

        IF l_header_old_gross IS NOT NULL
           AND ABS(l_header_old_gross - l_old_gross) > 0.005
        THEN
            RAISE_APPLICATION_ERROR(
                -20615,
                'Current Gross Salary changed after the promotion draft was generated. '
                || 'Regenerate the salary details.'
            );
        END IF;

        IF l_header_new_basic IS NOT NULL
           AND ABS(l_header_new_basic - l_new_basic) > 0.005
        THEN
            RAISE_APPLICATION_ERROR(
                -20616,
                'Header New Basic does not match the promotion salary details.'
            );
        END IF;

        l_increase_amount := l_new_basic - l_old_basic;
        l_increase_percent := CASE
            WHEN l_old_basic = 0 THEN NULL
            ELSE ROUND((l_increase_amount / l_old_basic) * 100, 2)
        END;

        INSERT INTO hr_employee_action (
            emp_id,
            action_type,
            action_date,
            effective_date,
            old_emp_type_id,
            new_emp_type_id,
            old_job_id,
            new_job_id,
            old_desig_id,
            new_desig_id,
            old_dept_id,
            new_dept_id,
            old_basic,
            new_basic,
            old_gross,
            new_gross,
            increment_amount,
            increment_percent,
            reason,
            remarks,
            approval_status,
            promotion_type,
            accelerated_count,
            ent_by,
            approved_by,
            approved_date
        ) VALUES (
            l_emp_id,
            'PROMOTION',
            SYSDATE,
            l_effective_date,
            TO_NUMBER(l_current_emp_type),
            NVL(l_new_emp_type_id, TO_NUMBER(l_current_emp_type)),
            l_current_job_id,
            NVL(l_new_job_id, l_current_job_id),
            l_current_desig_id,
            NVL(l_new_desig_id, l_current_desig_id),
            l_current_dept_id,
            NVL(l_new_dept_id, l_current_dept_id),
            l_old_basic,
            l_new_basic,
            l_old_gross,
            0,
            l_increase_amount,
            l_increase_percent,
            NVL(l_reason, 'Employee promotion'),
            l_remarks,
            'APPROVED',
            l_promotion_type,
            l_accelerated_count,
            p_user_id,
            p_user_id,
            SYSDATE
        ) RETURNING action_id INTO p_action_id;

        INSERT INTO hr_employee_career_hist (
            emp_id,
            action_id,
            action_type,
            effective_date,
            old_emp_type_id,
            new_emp_type_id,
            old_job_id,
            new_job_id,
            old_desig_id,
            new_desig_id,
            old_dept_id,
            new_dept_id,
            remarks,
            ent_by
        ) VALUES (
            l_emp_id,
            p_action_id,
            'PROMOTION',
            l_effective_date,
            TO_NUMBER(l_current_emp_type),
            NVL(l_new_emp_type_id, TO_NUMBER(l_current_emp_type)),
            l_current_job_id,
            NVL(l_new_job_id, l_current_job_id),
            l_current_desig_id,
            NVL(l_new_desig_id, l_current_desig_id),
            l_current_dept_id,
            NVL(l_new_dept_id, l_current_dept_id),
            l_remarks,
            p_user_id
        );

        l_salary_table :=
            '<table class="promotion-salary"><thead><tr>'
            || '<th>Salary head</th><th>Old salary</th>'
            || '<th>Promotion increment</th><th>New salary</th>'
            || '</tr></thead><tbody>';

        /* Apply only the generated promotion heads. Unlisted heads remain
           unchanged, which prevents accidental loss of allowances. */
        FOR r IN (
            SELECT d.slno,
                   d.headcode,
                   NVL(d.head_name, ah.head_name) AS head_name,
                   d.amount
              FROM hr_promotion_salary_dtl d
                   LEFT JOIN allowance_head ah ON ah.head_id = d.slno
             WHERE d.promotion_id = p_promotion_id
             ORDER BY d.slno
        ) LOOP
            BEGIN
                SELECT sals_id,
                       CASE WHEN NVL(is_active, 'Y') = 'Y' THEN NVL(amount, 0) ELSE 0 END
                  INTO l_sals_id,
                       l_old_amount
                  FROM emp_salary_structure
                 WHERE employee_id = l_emp_id
                   AND slno = r.slno
                   FOR UPDATE NOWAIT;

                INSERT INTO emp_salary_structure_hist (
                    action_id,
                    emp_id,
                    sals_id,
                    slno,
                    headcode,
                    old_amount,
                    new_amount,
                    revision_type,
                    effective_date,
                    remarks,
                    ent_by
                ) VALUES (
                    p_action_id,
                    l_emp_id,
                    l_sals_id,
                    r.slno,
                    r.headcode,
                    l_old_amount,
                    r.amount,
                    'P',
                    l_effective_date,
                    l_remarks,
                    p_user_id
                );

                UPDATE emp_salary_structure
                   SET headcode      = r.headcode,
                       amount        = r.amount,
                       revision_type = 'P',
                       is_active     = 'Y',
                       updated_by    = p_user_id,
                       updated_date  = SYSDATE
                 WHERE sals_id = l_sals_id;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    l_old_amount := 0;

                    INSERT INTO emp_salary_structure (
                        employee_id,
                        slno,
                        headcode,
                        amount,
                        revision_type,
                        is_active,
                        created_by,
                        created_date
                    ) VALUES (
                        l_emp_id,
                        r.slno,
                        r.headcode,
                        r.amount,
                        'P',
                        'Y',
                        p_user_id,
                        SYSDATE
                    ) RETURNING sals_id INTO l_sals_id;

                    INSERT INTO emp_salary_structure_hist (
                        action_id,
                        emp_id,
                        sals_id,
                        slno,
                        headcode,
                        old_amount,
                        new_amount,
                        revision_type,
                        effective_date,
                        remarks,
                        ent_by
                    ) VALUES (
                        p_action_id,
                        l_emp_id,
                        l_sals_id,
                        r.slno,
                        r.headcode,
                        0,
                        r.amount,
                        'P',
                        l_effective_date,
                        l_remarks,
                        p_user_id
                    );
            END;

            l_salary_table := l_salary_table
                || '<tr><td>' || html(NVL(r.head_name, r.headcode)) || '</td>'
                || '<td class="amount">' || money(l_old_amount) || '</td>'
                || '<td class="amount">' || money(r.amount - l_old_amount) || '</td>'
                || '<td class="amount">' || money(r.amount) || '</td></tr>';
        END LOOP;

        SELECT NVL(SUM(
                   CASE
                       WHEN ah.head_type = 'EARNING'
                        AND LPAD(TRIM(s.headcode), 3, '0') NOT IN ('025', '026')
                       THEN NVL(s.amount, 0)
                       ELSE 0
                   END
               ), 0)
          INTO l_new_gross
          FROM emp_salary_structure s
               LEFT JOIN allowance_head ah ON ah.head_id = s.slno
         WHERE s.employee_id = l_emp_id
           AND NVL(s.is_active, 'Y') = 'Y';

        l_salary_table := l_salary_table
            || '<tr class="total"><th>Total gross salary</th>'
            || '<th class="amount">' || money(l_old_gross) || '</th>'
            || '<th class="amount">' || money(l_new_gross - l_old_gross) || '</th>'
            || '<th class="amount">' || money(l_new_gross) || '</th>'
            || '</tr></tbody></table>';

        UPDATE employees
           SET emp_type = NVL(TO_CHAR(l_new_emp_type_id), l_current_emp_type),
               job_id   = NVL(l_new_job_id, l_current_job_id),
               desig_id = NVL(l_new_desig_id, l_current_desig_id),
               dept_id  = NVL(l_new_dept_id, l_current_dept_id),
               upd_by   = p_user_id,
               upd_date = SYSDATE
         WHERE id = l_emp_id;

        UPDATE hr_employee_action
           SET new_gross = l_new_gross
         WHERE action_id = p_action_id;

        UPDATE hr_employee_promotion
           SET action_id        = p_action_id,
               old_emp_type_id  = TO_NUMBER(l_current_emp_type),
               new_emp_type_id  = NVL(l_new_emp_type_id, TO_NUMBER(l_current_emp_type)),
               old_job_id       = l_current_job_id,
               new_job_id       = NVL(l_new_job_id, l_current_job_id),
               old_desig_id     = l_current_desig_id,
               new_desig_id     = NVL(l_new_desig_id, l_current_desig_id),
               old_dept_id      = l_current_dept_id,
               new_dept_id      = NVL(l_new_dept_id, l_current_dept_id),
               old_basic        = l_old_basic,
               new_basic        = l_new_basic,
               old_gross        = l_old_gross,
               new_gross        = l_new_gross,
               increase_amount  = l_increase_amount,
               increase_percent = l_increase_percent,
               approval_status  = 'POSTED',
               proposed_by      = NVL(proposed_by, p_user_id),
               proposed_date    = NVL(proposed_date, SYSDATE),
               checked_by       = p_user_id,
               checked_date     = SYSDATE,
               approved_by      = p_user_id,
               approved_date    = SYSDATE,
               posted_by        = p_user_id,
               posted_date      = SYSDATE,
               upd_by           = p_user_id,
               upd_date         = SYSDATE
         WHERE promotion_id = p_promotion_id;

        UPDATE hr_promotion_salary_dtl
           SET revision_type = 'P',
               is_posted     = 'Y',
               posted_by     = TO_CHAR(p_user_id),
               posted_date   = SYSDATE
         WHERE promotion_id = p_promotion_id;

        BEGIN
            SELECT designation
              INTO l_old_designation
              FROM designations
             WHERE id = l_current_desig_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                l_old_designation := 'Current designation';
        END;

        BEGIN
            SELECT designation
              INTO l_new_designation
              FROM designations
             WHERE id = NVL(l_new_desig_id, l_current_desig_id);
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                l_new_designation := 'New designation';
        END;

        BEGIN
            SELECT dept_name
              INTO l_department
              FROM departments
             WHERE id = NVL(l_new_dept_id, l_current_dept_id);
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                l_department := NULL;
        END;

        BEGIN
            SELECT template_id,
                   subject_template,
                   body_template
              INTO l_template_id,
                   l_subject_template,
                   l_body_template
              FROM hr_letter_template
             WHERE is_active = 'Y'
               AND action_type = 'PROMOTION'
               AND ((p_template_id IS NOT NULL AND template_id = p_template_id)
                    OR (p_template_id IS NULL AND template_code = 'PROMOTION_DEFAULT'))
             ORDER BY CASE WHEN template_id = p_template_id THEN 1 ELSE 2 END
             FETCH FIRST 1 ROW ONLY;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20617, 'Active promotion letter template was not found.');
        END;

        l_subject := l_subject_template;
        l_subject := REPLACE(l_subject, '#PROMOTION_TYPE#', INITCAP(l_promotion_type));
        l_subject := REPLACE(l_subject, '#EMP_NAME#', l_emp_name);
        l_subject := REPLACE(l_subject, '#EMP_CODE#', l_emp_code);

        l_body := l_body_template;
        l_body := REPLACE(l_body, '#PROMOTION_TYPE#', html(INITCAP(l_promotion_type)));
        l_body := REPLACE(l_body, '#EMP_NAME#', html(l_emp_name));
        l_body := REPLACE(l_body, '#EMP_CODE#', html(l_emp_code));
        l_body := REPLACE(l_body, '#OLD_DESIGNATION#', html(l_old_designation));
        l_body := REPLACE(l_body, '#NEW_DESIGNATION#', html(l_new_designation));
        l_body := REPLACE(l_body, '#DEPARTMENT#', html(l_department));
        l_body := REPLACE(l_body, '#EFFECTIVE_DATE#', TO_CHAR(l_effective_date, 'DD-Mon-YYYY'));
        l_body := REPLACE(l_body, '#LETTER_DATE#', TO_CHAR(SYSDATE, 'DD-Mon-YYYY'));
        l_body := REPLACE(l_body, '#OLD_BASIC#', money(l_old_basic));
        l_body := REPLACE(l_body, '#NEW_BASIC#', money(l_new_basic));
        l_body := REPLACE(l_body, '#INCREMENT_AMOUNT#', money(l_increase_amount));
        l_body := REPLACE(l_body, '#INCREMENT_PERCENT#', money(l_increase_percent));
        l_body := REPLACE(l_body, '#OLD_GROSS#', money(l_old_gross));
        l_body := REPLACE(l_body, '#NEW_GROSS#', money(l_new_gross));

        IF DBMS_LOB.INSTR(l_body, '#SALARY_DETAILS#') > 0 THEN
            l_body := REPLACE(l_body, '#SALARY_DETAILS#', l_salary_table);
        ELSE
            l_body := l_body || '<h3>Salary revision</h3>' || l_salary_table;
        END IF;

        /* PROMOTION_NO is already generated by a sequence and is unique. It is
           also the most useful reference number for the related letter. */
        l_letter_no := l_promotion_no;

        INSERT INTO hr_employee_letter (
            emp_id,
            action_id,
            promotion_id,
            template_id,
            letter_no,
            letter_date,
            subject_text,
            body_html,
            status,
            generated_by,
            generated_date
        ) VALUES (
            l_emp_id,
            p_action_id,
            p_promotion_id,
            l_template_id,
            l_letter_no,
            SYSDATE,
            l_subject,
            l_body,
            'DRAFT',
            p_user_id,
            SYSDATE
        ) RETURNING letter_id INTO p_letter_id;

    EXCEPTION
        WHEN OTHERS THEN
            l_error_code := SQLCODE;
            l_error_message := SQLERRM;
            ROLLBACK TO before_promotion_submit;

            IF l_error_code = -54 THEN
                RAISE_APPLICATION_ERROR(
                    -20618,
                    'Another user is changing this promotion, employee or salary. Please try again.'
                );
            ELSIF l_error_code BETWEEN -20999 AND -20000 THEN
                RAISE;
            ELSE
                RAISE_APPLICATION_ERROR(
                    -20619,
                    'Promotion submission failed. No salary change was saved. Cause: '
                    || SUBSTR(l_error_message, 1, 1200)
                );
            END IF;
    END submit_and_post;

END pkg_hr_promotion;
/
