CREATE OR REPLACE PROCEDURE HRMS.PR_APPROVE_CONFIRMATION
(
    p_confirm_id   IN NUMBER,
    p_user_id      IN NUMBER
)
IS
    v_emp_id             NUMBER;
    v_confirm_date       DATE;

    v_old_emp_type       NUMBER;
    v_new_emp_type       NUMBER;

    v_job_id             NUMBER;
    v_grade_order        NUMBER;
    v_desig_id           NUMBER;
    v_dept_id            NUMBER;

    v_old_basic          NUMBER;
    v_new_basic          NUMBER;

    v_old_gross          NUMBER;
    v_new_gross          NUMBER;

    v_increment_eligible VARCHAR2(1);
    v_increment_amount   NUMBER;

    v_status             VARCHAR2(20);
    v_remarks            VARCHAR2(1000);

    v_eb_status          VARCHAR2(20);

    v_action_id          NUMBER;

    v_revision_type      VARCHAR2(1);

    v_sals_id            NUMBER;
    v_old_amount         NUMBER;

    v_dup_count          NUMBER;

    v_reason             VARCHAR2(1000);

BEGIN
    /* =========================================================
       LOCK CONFIRMATION
       ========================================================= */

    SELECT emp_id,
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
           remarks

      INTO v_emp_id,
           v_confirm_date,

           v_old_emp_type,
           v_new_emp_type,

           v_job_id,
           v_grade_order,
           v_desig_id,
           v_dept_id,

           v_old_basic,
           v_new_basic,

           v_old_gross,
           v_new_gross,

           v_increment_eligible,
           v_increment_amount,

           v_status,
           v_remarks

      FROM hr_confirmation

     WHERE confirm_id = p_confirm_id

       FOR UPDATE;


    IF v_status <> 'PENDING' THEN
        RAISE_APPLICATION_ERROR(
            -20200,
            'Only PENDING confirmation can be approved.'
        );
    END IF;


    /* =========================================================
       MAKE SURE EMPLOYEE IS STILL PROBATIONARY
       ========================================================= */

    SELECT NVL(eb_status,'NORMAL')
      INTO v_eb_status
      FROM employees
     WHERE id = v_emp_id
       AND emp_type = 1
       FOR UPDATE;


    /* =========================================================
       CHECK DUPLICATE CURRENT ACTIVE SALARY HEADS
       ========================================================= */

    SELECT COUNT(*)
      INTO v_dup_count
      FROM
      (
          SELECT slno
            FROM emp_salary_structure
           WHERE employee_id = v_emp_id
             AND NVL(is_active,'Y') = 'Y'
           GROUP BY slno
          HAVING COUNT(*) > 1
      );


    IF v_dup_count > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20201,
            'Duplicate active salary heads exist for employee.'
        );
    END IF;


    /* =========================================================
       RECALCULATE FROM APPROVED STAGING DATA

       Important:
       never trust stale header totals.
       ========================================================= */

    SELECT NVL(MAX(
               CASE
                   WHEN slno = 1
                   THEN proposed_amount
               END
           ),0),

           NVL(SUM(
               CASE
                   WHEN head_type = 'EARNING'
                   THEN NVL(proposed_amount,0)

                   WHEN slno = 57
                   THEN -NVL(proposed_amount,0)

                   ELSE 0
               END
           ),0)

      INTO v_new_basic,
           v_new_gross

      FROM hr_confirmation_salary_dtl

     WHERE confirm_id = p_confirm_id
       AND NVL(is_active,'Y') = 'Y';


    v_new_gross := ROUND(v_new_gross,0);


    IF v_new_basic <= 0 THEN
        RAISE_APPLICATION_ERROR(
            -20202,
            'Approved Basic Salary cannot be zero.'
        );
    END IF;


    /* =========================================================
       LIVE REVISION TYPE

       I = confirmation with increment
       R = confirmation without increment / restructure
       ========================================================= */

    IF NVL(v_increment_amount,0) > 0 THEN
        v_revision_type := 'I';

        v_reason :=
            'Employee confirmed with payscale increment and approved salary structure.';
    ELSE
        v_revision_type := 'R';

        v_reason :=
            'Employee confirmed without confirmation increment and approved salary structure.';
    END IF;


    /* =========================================================
       EMPLOYEE ACTION
       ========================================================= */

    INSERT INTO hr_employee_action
    (
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

        old_eb_status,
        new_eb_status,

        reason,
        remarks,

        approval_status,

        ent_by,
        approved_by,
        approved_date
    )
    VALUES
    (
        v_emp_id,
        'CONFIRMATION',
        SYSDATE,
        v_confirm_date,

        v_old_emp_type,
        NVL(v_new_emp_type,2),

        v_job_id,
        v_job_id,

        v_desig_id,
        v_desig_id,

        v_dept_id,
        v_dept_id,

        v_old_basic,
        v_new_basic,

        v_old_gross,
        v_new_gross,

        NVL(v_increment_amount,0),

        v_eb_status,
        v_eb_status,

        v_reason,
        v_remarks,

        'APPROVED',

        p_user_id,
        p_user_id,
        SYSDATE
    )
    RETURNING action_id
         INTO v_action_id;


    /* =========================================================
       CAREER HISTORY
       ========================================================= */

    INSERT INTO hr_employee_career_hist
    (
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
    )
    VALUES
    (
        v_emp_id,
        v_action_id,
        'CONFIRMATION',
        v_confirm_date,

        v_old_emp_type,
        NVL(v_new_emp_type,2),

        v_job_id,
        v_job_id,

        v_desig_id,
        v_desig_id,

        v_dept_id,
        v_dept_id,

        v_remarks,
        p_user_id
    );


    /* =========================================================
       DEACTIVATE HEADS REMOVED FROM APPROVED STRUCTURE
       ========================================================= */

    FOR r IN
    (
        SELECT s.sals_id,
               s.slno,
               s.headcode,
               s.amount
          FROM emp_salary_structure s
         WHERE s.employee_id = v_emp_id
           AND NVL(s.is_active,'Y') = 'Y'

           AND NOT EXISTS
               (
                   SELECT 1
                     FROM hr_confirmation_salary_dtl d
                    WHERE d.confirm_id = p_confirm_id
                      AND d.slno = s.slno
                      AND NVL(d.is_active,'Y') = 'Y'
               )
    )
    LOOP
        INSERT INTO emp_salary_structure_hist
        (
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
        )
        VALUES
        (
            v_action_id,
            v_emp_id,
            r.sals_id,
            r.slno,
            r.headcode,

            r.amount,
            0,

            'C',
            v_confirm_date,
            v_remarks,
            p_user_id
        );


        UPDATE emp_salary_structure
           SET is_active    = 'N',
               updated_by   = p_user_id,
               updated_date = SYSDATE
         WHERE sals_id = r.sals_id;

    END LOOP;


    /* =========================================================
       POST ALL APPROVED SALARY HEADS

       Dynamic:
       no hard coding of 015 / 026 / 030 / etc.
       ========================================================= */

    FOR r IN
    (
        SELECT slno,
               headcode,
               proposed_amount
          FROM hr_confirmation_salary_dtl
         WHERE confirm_id = p_confirm_id
           AND NVL(is_active,'Y') = 'Y'
         ORDER BY display_order,
                  slno
    )
    LOOP
        BEGIN
            SELECT sals_id,
                   NVL(amount,0)
              INTO v_sals_id,
                   v_old_amount
              FROM emp_salary_structure
             WHERE employee_id = v_emp_id
               AND slno = r.slno
               AND NVL(is_active,'Y') = 'Y';


            /* History */
            INSERT INTO emp_salary_structure_hist
            (
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
            )
            VALUES
            (
                v_action_id,
                v_emp_id,
                v_sals_id,
                r.slno,
                r.headcode,

                v_old_amount,
                NVL(r.proposed_amount,0),

                'C',
                v_confirm_date,
                v_remarks,
                p_user_id
            );


            /* Live salary */
            UPDATE emp_salary_structure
               SET headcode      = r.headcode,
                   amount        = NVL(r.proposed_amount,0),
                   revision_type = v_revision_type,
                   updated_by    = p_user_id,
                   updated_date  = SYSDATE
             WHERE sals_id = v_sals_id;


        EXCEPTION
            WHEN NO_DATA_FOUND THEN

                INSERT INTO emp_salary_structure
                (
                    employee_id,
                    slno,
                    headcode,
                    amount,

                    revision_type,
                    is_active,

                    created_by,
                    created_date
                )
                VALUES
                (
                    v_emp_id,
                    r.slno,
                    r.headcode,
                    NVL(r.proposed_amount,0),

                    v_revision_type,
                    'Y',

                    p_user_id,
                    SYSDATE
                )
                RETURNING sals_id
                     INTO v_sals_id;


                INSERT INTO emp_salary_structure_hist
                (
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
                )
                VALUES
                (
                    v_action_id,
                    v_emp_id,
                    v_sals_id,
                    r.slno,
                    r.headcode,

                    0,
                    NVL(r.proposed_amount,0),

                    'C',
                    v_confirm_date,
                    v_remarks,
                    p_user_id
                );
        END;

    END LOOP;


    /* =========================================================
       EMPLOYEE CONFIRMATION
       ========================================================= */

    UPDATE employees
       SET emp_type  = NVL(v_new_emp_type,2),

           conf_date = v_confirm_date,

           last_increment_date =
               CASE
                   WHEN NVL(v_increment_amount,0) > 0
                   THEN v_confirm_date

                   ELSE last_increment_date
               END,

           next_increment_date =
               ADD_MONTHS(
                   v_confirm_date,
                   NVL(increment_cycle_months,12)
               )

     WHERE id = v_emp_id;


    /* =========================================================
       COMPLETE CONFIRMATION TRANSACTION
       ========================================================= */

    UPDATE hr_confirmation
       SET proposed_basic = v_new_basic,
           proposed_gross = v_new_gross,

           status         = 'APPROVED',

           action_id      = v_action_id,

           approved_by    = p_user_id,
           approved_date  = SYSDATE

     WHERE confirm_id = p_confirm_id;


    COMMIT;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        ROLLBACK;

        RAISE_APPLICATION_ERROR(
            -20210,
            'Confirmation or probationary employee not found.'
        );

    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END PR_APPROVE_CONFIRMATION;
/
