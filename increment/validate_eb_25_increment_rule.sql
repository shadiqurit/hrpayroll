-- Read-only validation for the 25-step annual increment and EB rule.
-- Run after PAY_SCALE_DETAIL has been populated and the revised functions
-- have been compiled. The script raises an error if any invariant fails.

SET SERVEROUTPUT ON

DECLARE
    v_invalid NUMBER;
BEGIN
    SELECT COUNT(*)
      INTO v_invalid
      FROM pay_scale_master
     WHERE NVL(is_active, 'Y') = 'Y'
       AND (
            steps_before_eb + steps_after_eb <> 25
            OR increment_1 <= 0
            OR increment_2 <= 0
            OR eb_basic <> start_basic + (increment_1 * steps_before_eb)
            OR max_basic <> eb_basic + (increment_2 * steps_after_eb)
       );

    IF v_invalid > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20401,
            v_invalid || ' active pay scale(s) violate the 25-step/EB formulas.'
        );
    END IF;

    DBMS_OUTPUT.PUT_LINE('PASS: all active pay-scale master rows satisfy the 25-step and EB formulas.');

    SELECT COUNT(*)
      INTO v_invalid
      FROM (
            SELECT s.scale_id
              FROM pay_scale_master s
                   LEFT JOIN pay_scale_detail d
                     ON d.scale_id = s.scale_id
             WHERE NVL(s.is_active, 'Y') = 'Y'
             GROUP BY s.scale_id,
                      s.steps_before_eb,
                      s.steps_after_eb,
                      s.eb_basic,
                      s.max_basic
            HAVING COUNT(d.detail_id) <> 26
                OR NVL(MIN(d.step_no), -1) <> 0
                OR NVL(MAX(d.step_no), -1) <> 25
                OR COUNT(DISTINCT d.step_no) <> 26
                OR NVL(MAX(CASE
                             WHEN d.step_no = s.steps_before_eb
                             THEN d.basic_amount
                           END), -1) <> s.eb_basic
                OR NVL(MAX(CASE
                             WHEN d.step_no = 25
                             THEN d.basic_amount
                           END), -1) <> s.max_basic
           );

    IF v_invalid > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20402,
            v_invalid || ' active scale(s) have missing or invalid generated steps.'
        );
    END IF;

    DBMS_OUTPUT.PUT_LINE('PASS: every active scale has continuous steps 0 through 25.');

    SELECT COUNT(*)
      INTO v_invalid
      FROM pay_scale_master s
           JOIN pay_scale_detail d24
             ON d24.scale_id = s.scale_id
            AND d24.step_no = 24
           JOIN pay_scale_detail d25
             ON d25.scale_id = s.scale_id
            AND d25.step_no = 25
     WHERE NVL(s.is_active, 'Y') = 'Y'
       AND (
            fn_get_next_basic(
                p_job_id         => s.grade_id,
                p_current_basic  => d24.basic_amount,
                p_eb_status      => 'NORMAL',
                p_effective_date => NVL(s.effective_from, SYSDATE)
            ) <> d25.basic_amount
            OR
            fn_get_next_basic(
                p_job_id         => s.grade_id,
                p_current_basic  => d25.basic_amount,
                p_eb_status      => 'NORMAL',
                p_effective_date => NVL(s.effective_from, SYSDATE)
            ) <> d25.basic_amount
       );

    IF v_invalid > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20403,
            v_invalid || ' active scale(s) fail the step-24/step-25 hard-cap test.'
        );
    END IF;

    DBMS_OUTPUT.PUT_LINE('PASS: step 24 advances to step 25 and step 25 cannot advance again.');

    SELECT COUNT(*)
      INTO v_invalid
      FROM pay_scale_master s
           JOIN pay_scale_detail d_before_eb
             ON d_before_eb.scale_id = s.scale_id
            AND d_before_eb.step_no = s.steps_before_eb - 1
     WHERE NVL(s.is_active, 'Y') = 'Y'
       AND fn_get_next_basic(
               p_job_id         => s.grade_id,
               p_current_basic  => d_before_eb.basic_amount,
               p_eb_status      => 'EB_HOLD',
               p_effective_date => NVL(s.effective_from, SYSDATE)
           ) <> d_before_eb.basic_amount;

    IF v_invalid > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20404,
            v_invalid || ' active scale(s) fail the EB-hold crossing test.'
        );
    END IF;

    DBMS_OUTPUT.PUT_LINE('PASS: EB_HOLD blocks movement onto the EB step.');
END;
/

SELECT s.scale_id,
       s.grade_id,
       s.steps_before_eb,
       s.steps_after_eb,
       s.steps_before_eb + s.steps_after_eb AS total_steps,
       s.start_basic,
       s.eb_basic,
       s.max_basic
  FROM pay_scale_master s
 WHERE NVL(s.is_active, 'Y') = 'Y'
 ORDER BY s.grade_id;
