/*
  Simple four-page increment module API.

  IMPORTANT PREREQUISITE
  ----------------------
  HR_EMPLOYEE_INCREMENT is referenced by existing repository procedures but
  its production DDL was not supplied. A complete new-install definition is
  now provided in Table/hr_employee_increment.sql. Reconcile that definition
  with any existing production table before compiling this package. The
  package expects these additional columns:

    COM_ID, ORIGINAL_LIST_DATE, CURRENT_LIST_DATE, SALARY_MONTH,
    REVISED_EFFECTIVE_DATE, DECISION_CODE, HOLD_TYPE, HOLD_REASON,
    HOLD_REVIEW_DATE, PUNISHMENT_REF_NO, SCALE_ID, FROM_STEP_NO,
    TO_STEP_NO, TOTAL_STEPS, REVERSE_ACTION_ID, REVERSED_BY,
    REVERSED_DATE, REVERSAL_REASON, VERSION_NO.

  Existing expected columns include INCREMENT_ID, EMP_ID, DUE_DATE,
  EFFECTIVE_DATE, OLD_BASIC, PROPOSED_BASIC, OLD_GROSS, PROPOSED_GROSS,
  INCREMENT_AMOUNT, STATUS, REMARKS, CHANGE_REASON, ACTION_ID and audit fields.

  No public routine commits. APEX owns commit on success. FINALIZE_MONTHLY_LIST
  uses a savepoint so any failed employee rolls back the entire final request.
*/

CREATE OR REPLACE PACKAGE HRMS.pkg_hr_increment_simple AS

    PROCEDURE prepare_monthly_list (
        p_com_id       IN  NUMBER,
        p_list_date    IN  DATE,
        p_user_id      IN  NUMBER,
        p_new_count    OUT NUMBER,
        p_carry_count  OUT NUMBER
    );

    PROCEDURE recalculate_case (
        p_increment_id IN NUMBER,
        p_user_id      IN NUMBER
    );

    PROCEDURE set_decision (
        p_increment_id        IN NUMBER,
        p_decision_code       IN VARCHAR2,
        p_reason              IN VARCHAR2 DEFAULT NULL,
        p_review_date         IN DATE DEFAULT NULL,
        p_revised_effective   IN DATE DEFAULT NULL,
        p_punishment_ref_no   IN VARCHAR2 DEFAULT NULL,
        p_user_id             IN NUMBER
    );

    PROCEDURE release_hold (
        p_increment_id IN NUMBER,
        p_remarks      IN VARCHAR2,
        p_user_id      IN NUMBER
    );

    PROCEDURE finalize_monthly_list (
        p_com_id          IN  NUMBER,
        p_list_date       IN  DATE,
        p_user_id         IN  NUMBER,
        p_processed_count OUT NUMBER
    );

    PROCEDURE revert_increment (
        p_increment_id IN NUMBER,
        p_reason       IN VARCHAR2,
        p_user_id      IN NUMBER,
        p_reopen_yn    IN VARCHAR2 DEFAULT 'Y'
    );

    PROCEDURE generate_letter (
        p_increment_id IN  NUMBER,
        p_template_id  IN  NUMBER,
        p_user_id      IN  NUMBER,
        p_letter_id    OUT NUMBER
    );

END pkg_hr_increment_simple;
/

CREATE OR REPLACE PACKAGE BODY HRMS.pkg_hr_increment_simple AS

    c_dec_ready              CONSTANT VARCHAR2(30) := 'READY';
    c_dec_temp_hold          CONSTANT VARCHAR2(30) := 'TEMP_HOLD';
    c_dec_punish_delay       CONSTANT VARCHAR2(30) := 'PUNISHMENT_DELAY';
    c_dec_punish_forfeit     CONSTANT VARCHAR2(30) := 'PUNISHMENT_FORFEIT';

    PROCEDURE assert_list_date (p_list_date IN DATE) IS
    BEGIN
        IF p_list_date IS NULL
           OR TRUNC(p_list_date) <> TRUNC(p_list_date, 'MM')
        THEN
            RAISE_APPLICATION_ERROR(
                -20501,
                'Increment list date must be the first day of a month.'
            );
        END IF;
    END assert_list_date;

    PROCEDURE recalculate_case (
        p_increment_id IN NUMBER,
        p_user_id      IN NUMBER
    ) IS
        v_emp_id          NUMBER;
        v_grade_id        NUMBER;
        v_effective_date  DATE;
        v_status          VARCHAR2(20);
        v_eb_status       VARCHAR2(20);
        v_old_basic       NUMBER;
        v_old_gross       NUMBER;
        v_scale_id        NUMBER;
        v_pre_steps       NUMBER;
        v_post_steps      NUMBER;
        v_max_basic       NUMBER;
        v_from_step       NUMBER;
        v_to_step         NUMBER;
        v_new_basic       NUMBER;
    BEGIN
        SELECT emp_id,
               NVL(revised_effective_date, effective_date),
               status
          INTO v_emp_id,
               v_effective_date,
               v_status
          FROM hr_employee_increment
         WHERE increment_id = p_increment_id
           FOR UPDATE;

        SELECT NVL(d.grade, e.job_id) AS grade_id,
               NVL(e.eb_status, 'NORMAL'),
               NVL(v.basic_salary, 0),
               NVL(v.gross_salary, 0)
          INTO v_grade_id,
               v_eb_status,
               v_old_basic,
               v_old_gross
          FROM employees e
               LEFT JOIN designations d ON d.id = e.desig_id
               LEFT JOIN vw_employee_salary v ON v.emp_id = e.id
         WHERE e.id = v_emp_id;

        IF v_status IN ('POSTED', 'FORFEITED', 'CANCELLED', 'REVERSED') THEN
            RAISE_APPLICATION_ERROR(-20503, 'Finalized increment cannot be recalculated.');
        END IF;

        SELECT scale_id,
               steps_before_eb,
               steps_after_eb,
               max_basic
          INTO v_scale_id,
               v_pre_steps,
               v_post_steps,
               v_max_basic
          FROM (
                SELECT s.scale_id,
                       s.steps_before_eb,
                       s.steps_after_eb,
                       s.max_basic
                  FROM pay_scale_master s
                 WHERE s.grade_id = v_grade_id
                   AND NVL(s.is_active, 'Y') = 'Y'
                   AND TRUNC(v_effective_date)
                       BETWEEN TRUNC(NVL(s.effective_from, DATE '1900-01-01'))
                           AND TRUNC(NVL(s.effective_to, DATE '2999-12-31'))
                 ORDER BY s.revision_no DESC,
                          s.effective_from DESC NULLS LAST,
                          s.scale_id DESC
               )
         WHERE ROWNUM = 1;

        IF v_pre_steps + v_post_steps <> 25 THEN
            RAISE_APPLICATION_ERROR(-20508, 'Pay scale must contain exactly 25 increment steps.');
        END IF;

        SELECT NVL(MAX(step_no), -1)
          INTO v_from_step
          FROM pay_scale_detail
         WHERE scale_id = v_scale_id
           AND basic_amount <= v_old_basic;

        IF v_from_step >= 25 OR v_old_basic >= v_max_basic THEN
            UPDATE hr_employee_increment
               SET old_basic       = v_old_basic,
                   proposed_basic  = v_old_basic,
                   old_gross       = v_old_gross,
                   proposed_gross  = v_old_gross,
                   increment_amount = 0,
                   scale_id        = v_scale_id,
                   from_step_no    = 25,
                   to_step_no      = 25,
                   total_steps     = 25,
                   decision_code   = 'MAX_REACHED',
                   status          = 'CLOSED_NO_INCREMENT',
                   updated_by      = p_user_id,
                   updated_date    = SYSDATE,
                   version_no      = NVL(version_no, 0) + 1
             WHERE increment_id = p_increment_id;

            UPDATE employees
               SET next_increment_date = NULL
             WHERE id = v_emp_id;

            RETURN;
        END IF;

        v_to_step := v_from_step + 1;

        IF v_eb_status = 'EB_HOLD' AND v_to_step >= v_pre_steps THEN
            UPDATE hr_employee_increment
               SET old_basic        = v_old_basic,
                   proposed_basic   = v_old_basic,
                   old_gross        = v_old_gross,
                   proposed_gross   = v_old_gross,
                   increment_amount = 0,
                   scale_id         = v_scale_id,
                   from_step_no     = CASE
                                          WHEN v_from_step < 0 THEN NULL
                                          ELSE v_from_step
                                      END,
                   to_step_no       = v_to_step,
                   total_steps      = 25,
                   decision_code    = 'EB_HOLD',
                   status           = 'DRAFT',
                   updated_by       = p_user_id,
                   updated_date     = SYSDATE,
                   version_no       = NVL(version_no, 0) + 1
             WHERE increment_id = p_increment_id;

            RETURN;
        END IF;

        v_new_basic := HRMS.fn_get_next_basic(
            p_job_id         => v_grade_id,
            p_current_basic  => v_old_basic,
            p_eb_status      => v_eb_status,
            p_effective_date => v_effective_date
        );

        IF NVL(v_new_basic, 0) <= v_old_basic THEN
            RAISE_APPLICATION_ERROR(-20508, 'Salary or pay-scale configuration is not valid for increment.');
        END IF;

        UPDATE hr_employee_increment
           SET old_basic        = v_old_basic,
               proposed_basic   = v_new_basic,
               old_gross        = v_old_gross,
               proposed_gross   = NULL,
               increment_amount = v_new_basic - v_old_basic,
               scale_id         = v_scale_id,
               from_step_no     = CASE
                                      WHEN v_from_step < 0 THEN NULL
                                      ELSE v_from_step
                                  END,
               to_step_no       = v_to_step,
               total_steps      = 25,
               updated_by       = p_user_id,
               updated_date     = SYSDATE,
               version_no       = NVL(version_no, 0) + 1
         WHERE increment_id = p_increment_id;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20508, 'Employee, salary, grade or effective pay scale is missing.');
    END recalculate_case;

    PROCEDURE prepare_monthly_list (
        p_com_id       IN  NUMBER,
        p_list_date    IN  DATE,
        p_user_id      IN  NUMBER,
        p_new_count    OUT NUMBER,
        p_carry_count  OUT NUMBER
    ) IS
        v_period_from DATE;
        v_period_to   DATE;
        v_salary_month NUMBER(6);
        v_increment_id NUMBER;
    BEGIN
        assert_list_date(p_list_date);

        v_period_from  := ADD_MONTHS(TRUNC(p_list_date, 'MM'), -1);
        v_period_to    := TRUNC(p_list_date, 'MM') - 1;
        v_salary_month := TO_NUMBER(TO_CHAR(p_list_date, 'YYYYMM'));

        /* Carry the same unresolved occurrence into the displayed month. */
        UPDATE hr_employee_increment
           SET current_list_date = TRUNC(p_list_date),
               salary_month      = v_salary_month,
               updated_by        = p_user_id,
               updated_date      = SYSDATE,
               version_no        = NVL(version_no, 0) + 1
         WHERE com_id = p_com_id
           AND current_list_date < TRUNC(p_list_date)
           AND decision_code IN (c_dec_temp_hold, c_dec_punish_delay)
           AND status IN ('HOLD', 'PUNISHMENT');

        p_carry_count := SQL%ROWCOUNT;
        p_new_count := 0;

        FOR r IN (
            SELECT e.id AS emp_id,
                   e.com_id,
                   e.next_increment_date AS due_date,
                   NVL(v.basic_salary, 0) AS old_basic,
                   NVL(v.gross_salary, 0) AS old_gross
              FROM employees e
                   LEFT JOIN vw_employee_salary v ON v.emp_id = e.id
             WHERE e.com_id = p_com_id
               AND TO_CHAR(e.emp_type) = '2'
               AND e.conf_date IS NOT NULL
               AND TRUNC(e.next_increment_date) BETWEEN v_period_from AND v_period_to
               AND NOT EXISTS (
                     SELECT 1
                       FROM hr_employee_increment i
                      WHERE i.emp_id = e.id
                        AND TRUNC(i.due_date) = TRUNC(e.next_increment_date)
                   )
             ORDER BY e.id
        ) LOOP
            INSERT INTO hr_employee_increment (
                emp_id,
                com_id,
                original_list_date,
                current_list_date,
                salary_month,
                due_date,
                effective_date,
                old_basic,
                proposed_basic,
                old_gross,
                proposed_gross,
                increment_amount,
                decision_code,
                status,
                created_by,
                created_date,
                version_no
            ) VALUES (
                r.emp_id,
                r.com_id,
                TRUNC(p_list_date),
                TRUNC(p_list_date),
                v_salary_month,
                TRUNC(r.due_date),
                TRUNC(r.due_date),
                r.old_basic,
                r.old_basic,
                r.old_gross,
                r.old_gross,
                0,
                NULL,
                'DRAFT',
                p_user_id,
                SYSDATE,
                1
            )
            RETURNING increment_id INTO v_increment_id;

            recalculate_case(v_increment_id, p_user_id);

            /*
               Normal newly generated employees are READY by default. HR only
               records exceptions (temporary hold or punishment) before the
               final salary update. Recalculation may already have marked an
               EB/max/configuration case with a blocking decision/status; those
               rows must never be auto-readied here.
            */
            UPDATE hr_employee_increment
               SET decision_code = c_dec_ready,
                   status        = 'READY',
                   remarks       = 'Eligible annual increment; review exceptions before final submit.',
                   updated_by    = p_user_id,
                   updated_date  = SYSDATE,
                   version_no    = NVL(version_no, 0) + 1
             WHERE increment_id = v_increment_id
               AND status = 'DRAFT'
               AND decision_code IS NULL;

            IF SQL%ROWCOUNT > 0 THEN
                INSERT INTO hr_employee_action (
                    emp_id,
                    increment_id,
                    action_type,
                    action_date,
                    effective_date,
                    old_effective_date,
                    new_effective_date,
                    reason,
                    remarks,
                    approval_status,
                    ent_by,
                    approved_by,
                    approved_date
                ) VALUES (
                    r.emp_id,
                    v_increment_id,
                    'INCREMENT_READY',
                    SYSDATE,
                    TRUNC(r.due_date),
                    TRUNC(r.due_date),
                    TRUNC(r.due_date),
                    'Automatically ready on monthly increment list generation',
                    'HR must record hold or punishment exceptions before final submit.',
                    'APPROVED',
                    p_user_id,
                    p_user_id,
                    SYSDATE
                );
            END IF;

            p_new_count := p_new_count + 1;
        END LOOP;
    END prepare_monthly_list;

    PROCEDURE set_decision (
        p_increment_id        IN NUMBER,
        p_decision_code       IN VARCHAR2,
        p_reason              IN VARCHAR2 DEFAULT NULL,
        p_review_date         IN DATE DEFAULT NULL,
        p_revised_effective   IN DATE DEFAULT NULL,
        p_punishment_ref_no   IN VARCHAR2 DEFAULT NULL,
        p_user_id             IN NUMBER
    ) IS
        v_decision       VARCHAR2(30) := UPPER(TRIM(p_decision_code));
        v_emp_id         NUMBER;
        v_effective_date DATE;
        v_due_date       DATE;
        v_status         VARCHAR2(20);
        v_active_hold    NUMBER;
    BEGIN
        SELECT emp_id,
               effective_date,
               due_date,
               status
          INTO v_emp_id,
               v_effective_date,
               v_due_date,
               v_status
          FROM hr_employee_increment
         WHERE increment_id = p_increment_id
           FOR UPDATE;

        IF v_status IN ('POSTED', 'FORFEITED', 'CANCELLED', 'REVERSED', 'CLOSED_NO_INCREMENT') THEN
            RAISE_APPLICATION_ERROR(-20503, 'Finalized increment cannot be changed.');
        END IF;

        IF v_decision NOT IN (
            c_dec_ready,
            c_dec_temp_hold,
            c_dec_punish_delay,
            c_dec_punish_forfeit
        ) THEN
            RAISE_APPLICATION_ERROR(-20504, 'Invalid increment decision.');
        END IF;

        IF v_decision = c_dec_ready THEN
            IF v_status = 'PUNISHMENT' THEN
                RAISE_APPLICATION_ERROR(
                    -20505,
                    'Use Release Hold after the punishment delay is completed.'
                );
            END IF;

            SELECT COUNT(*)
              INTO v_active_hold
              FROM hr_increment_hold
             WHERE increment_id = p_increment_id
               AND hold_status = 'ACTIVE';

            IF v_active_hold > 0 THEN
                RAISE_APPLICATION_ERROR(-20505, 'Release the active hold before marking Ready.');
            END IF;

            recalculate_case(p_increment_id, p_user_id);

            UPDATE hr_employee_increment
               SET decision_code          = c_dec_ready,
                   status                 = 'READY',
                   hold_type              = CASE
                                                WHEN hold_type = c_dec_punish_delay
                                                 AND revised_effective_date IS NOT NULL
                                                THEN hold_type
                                                ELSE NULL
                                            END,
                   revised_effective_date = CASE
                                                WHEN hold_type = c_dec_punish_delay
                                                THEN revised_effective_date
                                                ELSE NULL
                                            END,
                   hold_reason            = CASE
                                                WHEN hold_type = c_dec_punish_delay
                                                THEN hold_reason
                                                ELSE NULL
                                            END,
                   hold_review_date       = NULL,
                   punishment_ref_no      = CASE
                                                WHEN hold_type = c_dec_punish_delay
                                                THEN punishment_ref_no
                                                ELSE NULL
                                            END,
                   updated_by             = p_user_id,
                   updated_date           = SYSDATE,
                   version_no             = NVL(version_no, 0) + 1
             WHERE increment_id = p_increment_id
               AND status NOT IN ('CLOSED_NO_INCREMENT');

            IF SQL%ROWCOUNT > 0 THEN
                INSERT INTO hr_employee_action (
                    emp_id,
                    increment_id,
                    action_type,
                    action_date,
                    effective_date,
                    old_effective_date,
                    new_effective_date,
                    reason,
                    remarks,
                    approval_status,
                    ent_by,
                    approved_by,
                    approved_date
                ) VALUES (
                    v_emp_id,
                    p_increment_id,
                    'INCREMENT_READY',
                    SYSDATE,
                    v_effective_date,
                    v_effective_date,
                    v_effective_date,
                    'Employee marked ready for annual increment',
                    p_reason,
                    'APPROVED',
                    p_user_id,
                    p_user_id,
                    SYSDATE
                );
            END IF;

        ELSIF v_decision = c_dec_temp_hold THEN
            IF p_reason IS NULL THEN
                RAISE_APPLICATION_ERROR(-20504, 'Temporary-hold reason is required.');
            END IF;

            HRMS.pr_hold_increment(
                p_emp_id       => v_emp_id,
                p_reason       => p_reason,
                p_user_id      => p_user_id,
                p_increment_id => p_increment_id,
                p_hold_to_date => p_review_date
            );

            UPDATE hr_employee_increment
               SET decision_code          = c_dec_temp_hold,
                   hold_type              = c_dec_temp_hold,
                   hold_reason            = p_reason,
                   hold_review_date       = p_review_date,
                   revised_effective_date = NULL,
                   updated_by             = p_user_id,
                   updated_date           = SYSDATE,
                   version_no             = NVL(version_no, 0) + 1
             WHERE increment_id = p_increment_id;

        ELSIF v_decision = c_dec_punish_delay THEN
            IF p_reason IS NULL
               OR p_punishment_ref_no IS NULL
               OR p_revised_effective IS NULL
               OR TRUNC(p_revised_effective) <= TRUNC(v_effective_date)
            THEN
                RAISE_APPLICATION_ERROR(
                    -20504,
                    'Punishment reason, reference and a later revised effective date are required.'
                );
            END IF;

            UPDATE hr_employee_increment
               SET decision_code          = c_dec_punish_delay,
                   status                 = 'PUNISHMENT',
                   hold_type              = c_dec_punish_delay,
                   hold_reason            = p_reason,
                   hold_review_date       = p_review_date,
                   punishment_ref_no      = p_punishment_ref_no,
                   revised_effective_date = TRUNC(p_revised_effective),
                   updated_by             = p_user_id,
                   updated_date           = SYSDATE,
                   version_no             = NVL(version_no, 0) + 1
             WHERE increment_id = p_increment_id;

            INSERT INTO hr_employee_action (
                emp_id,
                increment_id,
                action_type,
                action_date,
                effective_date,
                old_effective_date,
                new_effective_date,
                reason,
                remarks,
                approval_status,
                ent_by,
                approved_by,
                approved_date
            ) VALUES (
                v_emp_id,
                p_increment_id,
                'INCREMENT_PUNISH_DELAY',
                SYSDATE,
                TRUNC(p_revised_effective),
                v_effective_date,
                TRUNC(p_revised_effective),
                p_reason,
                'Punishment reference: ' || p_punishment_ref_no,
                'APPROVED',
                p_user_id,
                p_user_id,
                SYSDATE
            );

        ELSE
            IF p_reason IS NULL OR p_punishment_ref_no IS NULL THEN
                RAISE_APPLICATION_ERROR(-20504, 'Punishment reason and reference are required.');
            END IF;

            UPDATE hr_employee_increment
               SET decision_code          = c_dec_punish_forfeit,
                   status                 = 'FORFEITED',
                   hold_type              = c_dec_punish_forfeit,
                   hold_reason            = p_reason,
                   punishment_ref_no      = p_punishment_ref_no,
                   revised_effective_date = NULL,
                   updated_by             = p_user_id,
                   updated_date           = SYSDATE,
                   version_no             = NVL(version_no, 0) + 1
             WHERE increment_id = p_increment_id;

            INSERT INTO hr_employee_action (
                emp_id,
                increment_id,
                action_type,
                action_date,
                effective_date,
                old_effective_date,
                new_effective_date,
                reason,
                remarks,
                approval_status,
                ent_by,
                approved_by,
                approved_date
            ) VALUES (
                v_emp_id,
                p_increment_id,
                'INCREMENT_FORFEIT',
                SYSDATE,
                v_effective_date,
                v_effective_date,
                NULL,
                p_reason,
                'Punishment reference: ' || p_punishment_ref_no,
                'APPROVED',
                p_user_id,
                p_user_id,
                SYSDATE
            );

            UPDATE employees
               SET next_increment_date = ADD_MONTHS(
                       v_due_date,
                       NVL(increment_cycle_months, 12)
                   )
             WHERE id = v_emp_id;
        END IF;
    END set_decision;

    PROCEDURE release_hold (
        p_increment_id IN NUMBER,
        p_remarks      IN VARCHAR2,
        p_user_id      IN NUMBER
    ) IS
        v_emp_id         NUMBER;
        v_hold_type      VARCHAR2(30);
        v_effective_date DATE;
        v_revised_date   DATE;
    BEGIN
        SELECT emp_id,
               hold_type,
               effective_date,
               revised_effective_date
          INTO v_emp_id,
               v_hold_type,
               v_effective_date,
               v_revised_date
          FROM hr_employee_increment
         WHERE increment_id = p_increment_id
           AND status IN ('HOLD', 'PUNISHMENT')
           FOR UPDATE;

        IF v_hold_type = c_dec_temp_hold THEN
            HRMS.pr_release_increment_hold(
                p_emp_id       => v_emp_id,
                p_remarks      => p_remarks,
                p_user_id      => p_user_id,
                p_increment_id => p_increment_id
            );
        ELSIF v_hold_type = c_dec_punish_delay THEN
            IF v_revised_date IS NULL THEN
                RAISE_APPLICATION_ERROR(-20504, 'Punishment revised effective date is required.');
            END IF;

            IF TRUNC(v_revised_date) > TRUNC(SYSDATE) THEN
                RAISE_APPLICATION_ERROR(
                    -20505,
                    'Punishment delay cannot be released before its revised effective date.'
                );
            END IF;

            INSERT INTO hr_employee_action (
                emp_id,
                increment_id,
                action_type,
                action_date,
                effective_date,
                old_effective_date,
                new_effective_date,
                reason,
                remarks,
                approval_status,
                ent_by,
                approved_by,
                approved_date
            ) VALUES (
                v_emp_id,
                p_increment_id,
                'INCREMENT_PUNISH_RELEASE',
                SYSDATE,
                v_revised_date,
                v_effective_date,
                v_revised_date,
                'Punishment delay completed',
                p_remarks,
                'APPROVED',
                p_user_id,
                p_user_id,
                SYSDATE
            );
        ELSE
            RAISE_APPLICATION_ERROR(-20503, 'Selected decision is not releasable.');
        END IF;

        recalculate_case(p_increment_id, p_user_id);

        UPDATE hr_employee_increment
           SET decision_code     = c_dec_ready,
               status            = 'READY',
               hold_review_date  = NULL,
               updated_by        = p_user_id,
               updated_date      = SYSDATE,
               version_no        = NVL(version_no, 0) + 1
         WHERE increment_id = p_increment_id
           AND status <> 'CLOSED_NO_INCREMENT';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20503, 'Selected occurrence is not an active hold.');
    END release_hold;

    PROCEDURE finalize_monthly_list (
        p_com_id          IN  NUMBER,
        p_list_date       IN  DATE,
        p_user_id         IN  NUMBER,
        p_processed_count OUT NUMBER
    ) IS
        v_payable_effective DATE;
    BEGIN
        assert_list_date(p_list_date);
        SAVEPOINT before_increment_final;
        p_processed_count := 0;

        /* Lock the complete ready set. NOWAIT prevents two processors. */
        FOR r IN (
            SELECT increment_id,
                   emp_id,
                   effective_date,
                   revised_effective_date,
                   remarks
              FROM hr_employee_increment
             WHERE com_id = p_com_id
               AND current_list_date = TRUNC(p_list_date)
               AND decision_code = c_dec_ready
               AND status = 'READY'
             ORDER BY emp_id
             FOR UPDATE OF status NOWAIT
        ) LOOP
            v_payable_effective := NVL(r.revised_effective_date, r.effective_date);

            HRMS.pr_apply_increment(
                p_emp_id         => r.emp_id,
                p_effective_date => v_payable_effective,
                p_remarks        => NVL(r.remarks, 'Monthly annual increment'),
                p_user_id        => p_user_id,
                p_increment_id   => r.increment_id
            );

            p_processed_count := p_processed_count + 1;
        END LOOP;

        IF p_processed_count = 0 THEN
            RAISE_APPLICATION_ERROR(-20503, 'No READY employees were found for final processing.');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO before_increment_final;

            IF SQLCODE = -54 THEN
                RAISE_APPLICATION_ERROR(-20509, 'Another user is processing this increment list.');
            ELSIF SQLCODE BETWEEN -20599 AND -20500 THEN
                RAISE;
            ELSE
                RAISE_APPLICATION_ERROR(
                    -20510,
                    'Final increment processing failed and all employee changes were rolled back.'
                );
            END IF;
    END finalize_monthly_list;

    PROCEDURE revert_increment (
        p_increment_id IN NUMBER,
        p_reason       IN VARCHAR2,
        p_user_id      IN NUMBER,
        p_reopen_yn    IN VARCHAR2 DEFAULT 'Y'
    ) IS
    BEGIN
        /*
           PR_REVERSE_INCREMENT performs the locked, history-based reversal.
           This package remains the only API called directly from APEX.
        */
        HRMS.pr_reverse_increment(
            p_increment_id => p_increment_id,
            p_remarks      => p_reason,
            p_user_id      => p_user_id,
            p_reopen_yn    => p_reopen_yn
        );
    END revert_increment;

    PROCEDURE generate_letter (
        p_increment_id IN  NUMBER,
        p_template_id  IN  NUMBER,
        p_user_id      IN  NUMBER,
        p_letter_id    OUT NUMBER
    ) IS
        v_action_id        NUMBER;
        v_emp_id           NUMBER;
        v_emp_code         VARCHAR2(30);
        v_emp_name         VARCHAR2(200);
        v_designation      VARCHAR2(200);
        v_department       VARCHAR2(200);
        v_effective_date   DATE;
        v_old_basic        NUMBER;
        v_new_basic        NUMBER;
        v_old_gross        NUMBER;
        v_new_gross        NUMBER;
        v_increment_amount NUMBER;
        v_subject_template VARCHAR2(500);
        v_body_template    CLOB;
        v_subject          VARCHAR2(500);
        v_body             CLOB;
        v_letter_no        VARCHAR2(30);
    BEGIN
        BEGIN
            SELECT letter_id
              INTO p_letter_id
              FROM hr_employee_letter
             WHERE action_id = (
                   SELECT action_id
                     FROM hr_employee_increment
                    WHERE increment_id = p_increment_id
                 )
               AND status <> 'CANCELLED'
             ORDER BY letter_id DESC
             FETCH FIRST 1 ROW ONLY;

            RETURN;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN NULL;
        END;

        SELECT i.action_id,
               i.emp_id,
               e.emp_id,
               TRIM(e.f_name || ' ' || e.l_name),
               d.designation,
               dp.dept_name,
               NVL(i.revised_effective_date, i.effective_date),
               i.old_basic,
               i.proposed_basic,
               i.old_gross,
               i.proposed_gross,
               i.increment_amount
          INTO v_action_id,
               v_emp_id,
               v_emp_code,
               v_emp_name,
               v_designation,
               v_department,
               v_effective_date,
               v_old_basic,
               v_new_basic,
               v_old_gross,
               v_new_gross,
               v_increment_amount
          FROM hr_employee_increment i
               JOIN employees e ON e.id = i.emp_id
               LEFT JOIN designations d ON d.id = e.desig_id
               LEFT JOIN departments dp ON dp.id = e.dept_id
         WHERE i.increment_id = p_increment_id
           AND i.status = 'POSTED';

        SELECT subject_template,
               body_template
          INTO v_subject_template,
               v_body_template
          FROM hr_letter_template
         WHERE template_id = p_template_id
           AND action_type = 'INCREMENT'
           AND is_active = 'Y';

        v_letter_no := 'INC-'
                       || TO_CHAR(v_effective_date, 'YYYYMM')
                       || '-'
                       || TO_CHAR(p_increment_id);

        v_subject := REPLACE(v_subject_template, '#EMP_NAME#', v_emp_name);
        v_subject := REPLACE(v_subject, '#EMP_CODE#', v_emp_code);

        v_body := v_body_template;
        v_body := REPLACE(v_body, '#EMP_NAME#', v_emp_name);
        v_body := REPLACE(v_body, '#EMP_CODE#', v_emp_code);
        v_body := REPLACE(v_body, '#DESIGNATION#', v_designation);
        v_body := REPLACE(v_body, '#DEPARTMENT#', v_department);
        v_body := REPLACE(v_body, '#EFFECTIVE_DATE#', TO_CHAR(v_effective_date, 'DD-Mon-YYYY'));
        v_body := REPLACE(v_body, '#OLD_BASIC#', TO_CHAR(v_old_basic, 'FM999G999G999G990D00'));
        v_body := REPLACE(v_body, '#NEW_BASIC#', TO_CHAR(v_new_basic, 'FM999G999G999G990D00'));
        v_body := REPLACE(v_body, '#OLD_GROSS#', TO_CHAR(v_old_gross, 'FM999G999G999G990D00'));
        v_body := REPLACE(v_body, '#NEW_GROSS#', TO_CHAR(v_new_gross, 'FM999G999G999G990D00'));
        v_body := REPLACE(v_body, '#INCREMENT_AMOUNT#', TO_CHAR(v_increment_amount, 'FM999G999G999G990D00'));
        v_body := REPLACE(v_body, '#LETTER_DATE#', TO_CHAR(SYSDATE, 'DD-Mon-YYYY'));

        INSERT INTO hr_employee_letter (
            emp_id,
            action_id,
            template_id,
            letter_no,
            letter_date,
            subject_text,
            body_html,
            status,
            generated_by,
            generated_date
        ) VALUES (
            v_emp_id,
            v_action_id,
            p_template_id,
            v_letter_no,
            SYSDATE,
            v_subject,
            v_body,
            'DRAFT',
            p_user_id,
            SYSDATE
        ) RETURNING letter_id INTO p_letter_id;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20511, 'Posted increment or active increment-letter template was not found.');
    END generate_letter;

END pkg_hr_increment_simple;
/
