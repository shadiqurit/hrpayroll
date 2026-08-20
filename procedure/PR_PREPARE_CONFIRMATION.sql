CREATE OR REPLACE PROCEDURE HRMS.PR_PREPARE_CONFIRMATION
(
    p_emp_id         IN  NUMBER,
    p_confirm_date   IN  DATE,
    p_remarks        IN  VARCHAR2,
    p_user_id        IN  NUMBER,
    p_confirm_id     OUT NUMBER
)
IS
    /* Employee */
    v_old_emp_type          NUMBER;
    v_job_id                NUMBER;
    v_grade_order           NUMBER;
    v_desig_id              NUMBER;
    v_dept_id               NUMBER;
    v_eb_status             VARCHAR2(20);
    v_probation_months      NUMBER;

    /* Policy */
    v_special_6_month       VARCHAR2(1) := 'N';
    v_increment_eligible    VARCHAR2(1) := 'N';

    /* Scale */
    v_scale_id              NUMBER;
    v_start_basic           NUMBER := 0;
    v_increment_1           NUMBER := 0;
    v_eb_basic              NUMBER := 0;
    v_increment_2           NUMBER := 0;
    v_max_basic             NUMBER := 0;

    v_hr_pct                NUMBER := 0;

    /* CPF = Company PF */
    v_company_pf_pct        NUMBER := 0;

    /* PFCONT = Employee PF deduction */
    v_employee_pf_pct       NUMBER := 0;

    v_conv                  NUMBER := 0;
    v_medical               NUMBER := 0;
    v_allowance             NUMBER := 0;
    v_saf                   NUMBER := 0;

    /* Current */
    v_old_basic             NUMBER := 0;
    v_old_gross             NUMBER := 0;
    v_retained_earning      NUMBER := 0;

    /* New */
    v_base_basic            NUMBER := 0;
    v_new_basic             NUMBER := 0;
    v_increment_amount      NUMBER := 0;

    v_base_hr               NUMBER := 0;
    v_base_company_pf       NUMBER := 0;
    v_base_employee_pf      NUMBER := 0;
    v_base_package          NUMBER := 0;

    v_new_hr                NUMBER := 0;
    v_new_company_pf        NUMBER := 0;
    v_new_employee_pf       NUMBER := 0;

    v_new_others            NUMBER := 0;
    v_proposed_gross        NUMBER := 0;

    v_open_count            NUMBER := 0;

BEGIN
    /* =========================================================
       VALIDATION
       ========================================================= */

    IF p_emp_id IS NULL THEN
        RAISE_APPLICATION_ERROR(-20001, 'Employee ID is required.');
    END IF;

    IF p_confirm_date IS NULL THEN
        RAISE_APPLICATION_ERROR(-20002, 'Confirmation date is required.');
    END IF;


    /* Do not create duplicate open confirmation */
    SELECT COUNT(*)
      INTO v_open_count
      FROM hr_confirmation
     WHERE emp_id = p_emp_id
       AND status IN ('DRAFT', 'PENDING');

    IF v_open_count > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20003,
            'Employee already has a Draft/Pending confirmation.'
        );
    END IF;


    /* =========================================================
       EMPLOYEE INFORMATION
       ========================================================= */

    SELECT e.emp_type,
           e.job_id,
           j.grade_order,
           e.desig_id,
           e.dept_id,
           NVL(e.eb_status, 'NORMAL'),
           NVL(e.probation_period_months, 12)
      INTO v_old_emp_type,
           v_job_id,
           v_grade_order,
           v_desig_id,
           v_dept_id,
           v_eb_status,
           v_probation_months
      FROM employees e
           JOIN job_grades j
             ON j.id = e.job_id
     WHERE e.id = p_emp_id;


    IF NVL(v_old_emp_type, 0) = 2 THEN
        RAISE_APPLICATION_ERROR(
            -20004,
            'Employee is already confirmed.'
        );
    END IF;


    /* =========================================================
       6 MONTH SPECIAL CATEGORY
       ========================================================= */

    IF     v_dept_id IN (22,23)
       AND v_desig_id IN
           (
               136,
               120,
               123
               /* add remaining designation IDs */
           )
    THEN
        v_special_6_month := 'Y';
    END IF;


    /* =========================================================
       INCREMENT ELIGIBILITY
       ========================================================= */

    IF v_grade_order BETWEEN 15 AND 20 THEN

        v_increment_eligible := 'N';

    ELSIF v_special_6_month = 'Y' THEN

        v_increment_eligible := 'N';

    ELSIF     v_grade_order BETWEEN 1 AND 14
          AND NVL(v_probation_months,12) > 6
    THEN

        v_increment_eligible := 'Y';

    ELSE

        v_increment_eligible := 'N';

    END IF;


    /* =========================================================
       ACTIVE PAY SCALE
       ========================================================= */

    BEGIN
        SELECT scale_id,
               start_basic,
               increment_1,
               eb_basic,
               increment_2,
               max_basic,
               NVL(hr,0),
               NVL(cpf,0),
               NVL(pfcont,0),
               NVL(conv,0),
               NVL(medical,0),
               NVL(allowance,0),
               NVL(saf,0)
          INTO v_scale_id,
               v_start_basic,
               v_increment_1,
               v_eb_basic,
               v_increment_2,
               v_max_basic,
               v_hr_pct,
               v_company_pf_pct,
               v_employee_pf_pct,
               v_conv,
               v_medical,
               v_allowance,
               v_saf
          FROM
          (
              SELECT m.*
                FROM pay_scale_master m
               WHERE m.grade_id = v_job_id
                 AND NVL(m.is_active,'Y') = 'Y'
                 AND TRUNC(p_confirm_date) >=
                     NVL(TRUNC(m.effective_from), DATE '1900-01-01')
                 AND TRUNC(p_confirm_date) <=
                     NVL(TRUNC(m.effective_to), DATE '2999-12-31')
               ORDER BY NVL(m.effective_from,DATE '1900-01-01') DESC,
                        m.revision_no DESC,
                        m.scale_id DESC
          )
         WHERE ROWNUM = 1;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(
                -20005,
                'Active payscale not found for Grade ID '
                || v_job_id
            );
    END;


    /* =========================================================
       CURRENT BASIC
       ========================================================= */

    SELECT NVL(MAX(
               CASE
                   WHEN s.slno = 1 OR s.headcode = '001'
                   THEN NVL(s.amount,0)
               END
           ),0)
      INTO v_old_basic
      FROM emp_salary_structure s
     WHERE s.employee_id = p_emp_id
       AND NVL(s.is_active,'Y') = 'Y';


    /* =========================================================
       CURRENT PROTECTED GROSS

       Earnings
       minus Employee PF 057.

       Other payroll deductions such as SAF/Tax are not part
       of this gross-protection comparison.
       ========================================================= */

    SELECT NVL(
               SUM(
                   CASE
                       WHEN s.slno = 57
                         OR s.headcode = '057'
                       THEN -NVL(s.amount,0)

                       WHEN ah.head_type = 'EARNING'
                       THEN NVL(s.amount,0)

                       ELSE 0
                   END
               ),
               0
           )
      INTO v_old_gross
      FROM emp_salary_structure s
           LEFT JOIN allowance_head ah
             ON ah.head_id = s.slno
     WHERE s.employee_id = p_emp_id
       AND NVL(s.is_active,'Y') = 'Y';


    /* =========================================================
       EXISTING NON-STANDARD EARNINGS

       Examples:
       015 Dearness
       026 Special
       030 Performance
       Technical allowance
       etc.

       Exclude standard payscale heads and Others.
       ========================================================= */

    SELECT NVL(SUM(s.amount),0)
      INTO v_retained_earning
      FROM emp_salary_structure s
           JOIN allowance_head ah
             ON ah.head_id = s.slno
     WHERE s.employee_id = p_emp_id
       AND NVL(s.is_active,'Y') = 'Y'
       AND ah.head_type = 'EARNING'
       AND s.slno NOT IN
           (
               1,      -- Basic
               5,      -- HR
               7,      -- Conveyance
               10,     -- Medical
               13,     -- Company PF
               25,     -- Others
               37      -- Allowance
           );


    /* =========================================================
       BASE BASIC BEFORE CONFIRMATION INCREMENT
       ========================================================= */

    v_base_basic :=
        GREATEST(
            NVL(v_old_basic,0),
            NVL(v_start_basic,0)
        );


    /* =========================================================
       CURRENT STANDARD PACKAGE
       ========================================================= */

    v_base_hr :=
        ROUND(v_base_basic * v_hr_pct / 100, 2);

    /* Company PF = CPF */
    v_base_company_pf :=
        ROUND(v_base_basic * v_company_pf_pct / 100, 2);

    /* Employee PF = PFCONT */
    v_base_employee_pf :=
        ROUND(v_base_basic * v_employee_pf_pct / 100, 2);


    v_base_package :=
          v_base_basic
        + v_base_hr
        + v_conv
        + v_medical
        + v_allowance
        + v_base_company_pf
        - v_base_employee_pf;


    /* =========================================================
       OTHERS PROTECTION

       Existing special/performance/dearness earnings remain
       separate, therefore they are deducted from the balancing
       Others calculation.
       ========================================================= */

    v_new_others :=
        GREATEST(
              ROUND(NVL(v_old_gross,0),0)
            - ROUND(NVL(v_base_package,0),0)
            - ROUND(NVL(v_retained_earning,0),0),
            0
        );


    /* =========================================================
       CONFIRMATION BASIC / INCREMENT
       ========================================================= */

    v_new_basic := v_base_basic;


    IF v_increment_eligible = 'Y' THEN

        IF v_base_basic < v_eb_basic THEN

            IF     v_base_basic + v_increment_1 >= v_eb_basic
               AND NVL(v_eb_status,'NORMAL') = 'EB_HOLD'
            THEN
                v_new_basic := v_base_basic;
            ELSE
                v_new_basic :=
                    LEAST(
                        v_base_basic + v_increment_1,
                        v_eb_basic
                    );
            END IF;

        ELSIF     v_base_basic >= v_eb_basic
              AND v_base_basic < v_max_basic
        THEN

            IF NVL(v_eb_status,'NORMAL') = 'EB_HOLD' THEN
                v_new_basic := v_base_basic;
            ELSE
                v_new_basic :=
                    LEAST(
                        v_base_basic + v_increment_2,
                        v_max_basic
                    );
            END IF;

        ELSE
            v_new_basic := v_base_basic;
        END IF;

    END IF;


    v_new_basic :=
        GREATEST(
            NVL(v_new_basic,v_base_basic),
            v_base_basic
        );


    v_increment_amount :=
        GREATEST(
            v_new_basic - v_base_basic,
            0
        );


    /* =========================================================
       NEW PAY SCALE STRUCTURE
       ========================================================= */

    v_new_hr :=
        ROUND(v_new_basic * v_hr_pct / 100,2);

    v_new_company_pf :=
        ROUND(v_new_basic * v_company_pf_pct / 100,2);

    v_new_employee_pf :=
        ROUND(v_new_basic * v_employee_pf_pct / 100,2);


    v_proposed_gross :=
        ROUND(
              v_new_basic
            + v_new_hr
            + v_conv
            + v_medical
            + v_allowance
            + v_new_company_pf
            - v_new_employee_pf
            + v_new_others
            + v_retained_earning,
            0
        );


    /* =========================================================
       CREATE HEADER
       ========================================================= */

    INSERT INTO hr_confirmation
    (
        emp_id,
        confirm_date,

        old_emp_type_id,
        new_emp_type_id,

        job_id,
        grade_order,
        desig_id,
        dept_id,

        old_basic,
        proposed_basic,

        old_gross,
        proposed_gross,

        increment_eligible,
        increment_amount,

        status,
        remarks,

        created_by,
        created_date
    )
    VALUES
    (
        p_emp_id,
        p_confirm_date,

        v_old_emp_type,
        2,

        v_job_id,
        v_grade_order,
        v_desig_id,
        v_dept_id,

        v_old_basic,
        v_new_basic,

        ROUND(v_old_gross,0),
        v_proposed_gross,

        v_increment_eligible,
        v_increment_amount,

        'DRAFT',
        p_remarks,

        p_user_id,
        SYSDATE
    )
    RETURNING confirm_id
         INTO p_confirm_id;


    /* =========================================================
       STANDARD PAY SCALE HEADS

       Metadata comes dynamically from ALLOWANCE_HEAD.
       ========================================================= */

    INSERT INTO hr_confirmation_salary_dtl
    (
        confirm_id,
        emp_id,

        slno,
        headcode,
        head_name,
        head_type,
        calc_type,

        old_amount,
        proposed_amount,

        source_type,
        is_manual,
        is_active,
        show_in_letter,
        display_order,

        created_by,
        created_date
    )
    SELECT p_confirm_id,
           p_emp_id,

           ah.head_id,
           ah.head_code,
           ah.head_name,
           ah.head_type,
           ah.calc_type,

           NVL(
               (
                   SELECT MAX(s.amount)
                     FROM emp_salary_structure s
                    WHERE s.employee_id = p_emp_id
                      AND s.slno = ah.head_id
                      AND NVL(s.is_active,'Y') = 'Y'
               ),
               0
           ) AS old_amount,

           CASE ah.head_id
               WHEN 1  THEN v_new_basic
               WHEN 5  THEN v_new_hr
               WHEN 7  THEN v_conv
               WHEN 10 THEN v_medical
               WHEN 13 THEN v_new_company_pf
               WHEN 25 THEN v_new_others
               WHEN 37 THEN v_allowance
               WHEN 57 THEN v_new_employee_pf
               WHEN 75 THEN v_saf
           END AS proposed_amount,

           CASE
               WHEN ah.head_id = 25
               THEN 'ADJUSTMENT'
               ELSE 'PAYSCALE'
           END,

           'N',
           'Y',
           'Y',
           NVL(ah.print_order,ah.head_id),

           p_user_id,
           SYSDATE

      FROM allowance_head ah
     WHERE ah.head_id IN
           (
               1,
               5,
               7,
               10,
               13,
               25,
               37,
               57,
               75
           )
       AND NVL(ah.is_active,'Y') = 'Y';


    /* =========================================================
       CARRY ALL OTHER EXISTING SALARY HEADS

       Therefore:
       015 Dearness
       026 Special
       030 Performance
       etc.

       automatically remain with employee.
       ========================================================= */

    INSERT INTO hr_confirmation_salary_dtl
    (
        confirm_id,
        emp_id,

        slno,
        headcode,
        head_name,
        head_type,
        calc_type,

        old_amount,
        proposed_amount,

        source_type,
        is_manual,

        is_active,
        show_in_letter,
        display_order,

        created_by,
        created_date
    )
    SELECT p_confirm_id,
           p_emp_id,

           s.slno,
           ah.head_code,
           ah.head_name,
           ah.head_type,
           ah.calc_type,

           NVL(s.amount,0),
           NVL(s.amount,0),

           'CURRENT',
           'N',

           'Y',
           'Y',
           NVL(ah.print_order,s.slno),

           p_user_id,
           SYSDATE

      FROM emp_salary_structure s
           JOIN allowance_head ah
             ON ah.head_id = s.slno

     WHERE s.employee_id = p_emp_id
       AND NVL(s.is_active,'Y') = 'Y'

       AND s.slno NOT IN
           (
               1,
               5,
               7,
               10,
               13,
               25,
               37,
               57,
               75
           );


    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END PR_PREPARE_CONFIRMATION;
/
