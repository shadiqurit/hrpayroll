CREATE OR REPLACE PROCEDURE HRMS.pr_reverse_increment (
    p_increment_id IN NUMBER,
    p_remarks      IN VARCHAR2,
    p_user_id      IN NUMBER,
    p_reopen_yn    IN VARCHAR2 DEFAULT 'Y'
)
IS
    v_emp_id          NUMBER;
    v_action_id       NUMBER;
    v_reverse_action  NUMBER;
    v_due_date        DATE;
    v_effective_date  DATE;
    v_old_basic       NUMBER;
    v_new_basic       NUMBER;
    v_old_gross       NUMBER;
    v_new_gross       NUMBER;
    v_status          VARCHAR2(30);
    v_later_actions   NUMBER;
    v_history_rows    NUMBER;
    v_salary_mismatch NUMBER;
    v_current_gross   NUMBER;
    v_prev_inc_date   DATE;
    v_reopen_yn       VARCHAR2(1) := UPPER(NVL(p_reopen_yn, 'Y'));
BEGIN
    IF TRIM(p_remarks) IS NULL OR LENGTH(p_remarks) > 1000 THEN
        RAISE_APPLICATION_ERROR(-20512, 'Revert reason is required and must not exceed 1000 characters.');
    END IF;

    IF v_reopen_yn NOT IN ('Y', 'N') THEN
        RAISE_APPLICATION_ERROR(-20516, 'Reopen value must be Y or N.');
    END IF;

    /* Lock the exact posted occurrence; never reverse by employee alone. */
    SELECT i.emp_id,
           i.action_id,
           i.due_date,
           NVL(i.revised_effective_date, i.effective_date),
           i.old_basic,
           i.proposed_basic,
           i.old_gross,
           i.proposed_gross,
           i.status
      INTO v_emp_id,
           v_action_id,
           v_due_date,
           v_effective_date,
           v_old_basic,
           v_new_basic,
           v_old_gross,
           v_new_gross,
           v_status
      FROM hr_employee_increment i
     WHERE i.increment_id = p_increment_id
       FOR UPDATE;

    IF v_status <> 'POSTED' OR v_action_id IS NULL THEN
        RAISE_APPLICATION_ERROR(-20513, 'Only a POSTED increment can be reverted.');
    END IF;

    /*
       A later approved salary/career action may depend on this salary.
       Reverting underneath it would corrupt history, so require manual review.
    */
    SELECT COUNT(*)
      INTO v_later_actions
      FROM hr_employee_action a
     WHERE a.emp_id = v_emp_id
       AND a.action_id <> v_action_id
       AND a.approval_status = 'APPROVED'
       AND (
            a.effective_date > v_effective_date
            OR (a.effective_date = v_effective_date AND a.action_id > v_action_id)
       )
       AND a.action_type IN (
            'INCREMENT',
            'CONFIRMATION',
            'PROMOTION',
            'SALARY_REVISION'
       );

    IF v_later_actions > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20514,
            'Increment cannot be reverted because a later approved salary/career action exists.'
        );
    END IF;

    SELECT COUNT(*)
      INTO v_history_rows
      FROM emp_salary_structure_hist h
     WHERE h.action_id = v_action_id
       AND h.emp_id = v_emp_id;

    IF v_history_rows = 0 THEN
        RAISE_APPLICATION_ERROR(
            -20515,
            'Salary component history is missing; this increment cannot be reverted safely.'
        );
    END IF;

    /* Never overwrite a salary that has changed outside this action. */
    SELECT COUNT(*)
      INTO v_salary_mismatch
      FROM emp_salary_structure_hist h
     WHERE h.action_id = v_action_id
       AND h.emp_id = v_emp_id
       AND NOT EXISTS (
             SELECT 1
               FROM emp_salary_structure s
              WHERE s.employee_id = v_emp_id
                AND NVL(s.is_active, 'Y') = 'Y'
                AND (
                     (h.sals_id IS NOT NULL AND s.sals_id = h.sals_id)
                     OR (h.sals_id IS NULL AND s.headcode = h.headcode)
                )
                AND NVL(s.amount, 0) = NVL(h.new_amount, 0)
           );

    IF v_salary_mismatch > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20517,
            'Current salary no longer matches the posted increment; review later or manual salary changes first.'
        );
    END IF;

    SELECT NVL(SUM(s.amount), 0)
      INTO v_current_gross
      FROM emp_salary_structure s
           JOIN allowance_head ah ON ah.head_id = s.slno
     WHERE s.employee_id = v_emp_id
       AND NVL(s.is_active, 'Y') = 'Y'
       AND ah.head_type = 'EARNING'
       AND s.headcode NOT IN ('025', '026');

    IF NVL(v_current_gross, 0) <> NVL(v_new_gross, 0) THEN
        RAISE_APPLICATION_ERROR(
            -20517,
            'Current gross salary no longer matches the posted increment; review later or manual salary changes first.'
        );
    END IF;

    /* Restore every component from the immutable increment history. */
    FOR h IN (
        SELECT sals_id,
               slno,
               headcode,
               old_amount
          FROM emp_salary_structure_hist
         WHERE action_id = v_action_id
           AND emp_id = v_emp_id
         ORDER BY hist_id
    ) LOOP
        IF h.sals_id IS NULL AND NVL(h.old_amount, 0) = 0 THEN
            /* Component was introduced by the increment: deactivate it. */
            UPDATE emp_salary_structure s
               SET s.amount        = 0,
                   s.is_active     = 'N',
                   s.revision_type = 'R',
                   s.updated_by    = p_user_id,
                   s.updated_date  = SYSDATE
             WHERE s.employee_id = v_emp_id
               AND s.headcode = h.headcode;
        ELSE
            UPDATE emp_salary_structure s
               SET s.amount        = NVL(h.old_amount, 0),
                   s.is_active     = 'Y',
                   s.revision_type = 'R',
                   s.updated_by    = p_user_id,
                   s.updated_date  = SYSDATE
             WHERE s.employee_id = v_emp_id
               AND (
                    (h.sals_id IS NOT NULL AND s.sals_id = h.sals_id)
                    OR (h.sals_id IS NULL AND s.headcode = h.headcode)
               );

            IF SQL%ROWCOUNT = 0 AND NVL(h.old_amount, 0) <> 0 THEN
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
                    v_emp_id,
                    h.slno,
                    h.headcode,
                    h.old_amount,
                    'R',
                    'Y',
                    p_user_id,
                    SYSDATE
                );
            END IF;
        END IF;
    END LOOP;

    UPDATE hr_employee_action
       SET approval_status = 'REVERSED',
           remarks = CASE
                       WHEN remarks IS NULL THEN 'Reverted: ' || p_remarks
                       ELSE remarks || ' | Reverted: ' || p_remarks
                     END,
           upd_by = p_user_id,
           upd_date = SYSDATE
     WHERE action_id = v_action_id;

    INSERT INTO hr_employee_action (
        emp_id,
        increment_id,
        action_type,
        action_date,
        effective_date,
        old_effective_date,
        new_effective_date,
        reversal_of_action_id,
        old_basic,
        new_basic,
        old_gross,
        new_gross,
        increment_amount,
        reason,
        remarks,
        approval_status,
        ent_by,
        approved_by,
        approved_date
    ) VALUES (
        v_emp_id,
        p_increment_id,
        'REVERSE_INCREMENT',
        SYSDATE,
        v_effective_date,
        v_effective_date,
        v_effective_date,
        v_action_id,
        v_new_basic,
        v_old_basic,
        v_new_gross,
        v_old_gross,
        v_old_basic - v_new_basic,
        'Revert annual increment',
        p_remarks,
        'APPROVED',
        p_user_id,
        p_user_id,
        SYSDATE
    )
    RETURNING action_id INTO v_reverse_action;

    /* Keep a second immutable component trail for the reversing action. */
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
    )
    SELECT v_reverse_action,
           v_emp_id,
           NVL(
               h.sals_id,
               (SELECT MAX(s.sals_id)
                  FROM emp_salary_structure s
                 WHERE s.employee_id = v_emp_id
                   AND s.headcode = h.headcode)
           ),
           h.slno,
           h.headcode,
           h.new_amount,
           h.old_amount,
           'R',
           v_effective_date,
           p_remarks,
           p_user_id
      FROM emp_salary_structure_hist h
     WHERE h.action_id = v_action_id
       AND h.emp_id = v_emp_id;

    /* A letter for a reverted action must no longer be printable as valid. */
    UPDATE hr_employee_letter
       SET status = 'CANCELLED'
     WHERE action_id = v_action_id
       AND status <> 'CANCELLED';

    UPDATE hr_employee_increment
       SET status            = CASE WHEN v_reopen_yn = 'Y' THEN 'DRAFT' ELSE 'REVERSED' END,
           decision_code     = CASE WHEN v_reopen_yn = 'Y' THEN NULL ELSE decision_code END,
           current_list_date = CASE
                                 WHEN v_reopen_yn = 'Y' THEN TRUNC(SYSDATE, 'MM')
                                 ELSE current_list_date
                               END,
           salary_month      = CASE
                                 WHEN v_reopen_yn = 'Y' THEN TO_NUMBER(TO_CHAR(SYSDATE, 'YYYYMM'))
                                 ELSE salary_month
                               END,
           reverse_action_id = v_reverse_action,
           reversed_by       = p_user_id,
           reversed_date     = SYSDATE,
           reversal_reason   = p_remarks,
           updated_by        = p_user_id,
           updated_date      = SYSDATE,
           version_no        = NVL(version_no, 0) + 1
     WHERE increment_id = p_increment_id;

    SELECT MAX(a.effective_date)
      INTO v_prev_inc_date
      FROM hr_employee_action a
     WHERE a.emp_id = v_emp_id
       AND a.action_type = 'INCREMENT'
       AND a.approval_status = 'APPROVED'
       AND a.action_id <> v_action_id
       AND a.effective_date < v_effective_date;

    UPDATE employees
       SET last_increment_date = v_prev_inc_date,
           next_increment_date =
               CASE
                   WHEN v_reopen_yn = 'Y' THEN v_due_date
                   ELSE ADD_MONTHS(v_due_date, NVL(increment_cycle_months, 12))
               END
     WHERE id = v_emp_id;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20513, 'Posted increment occurrence was not found.');
END;
/
