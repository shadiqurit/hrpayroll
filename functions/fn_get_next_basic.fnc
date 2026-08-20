DROP FUNCTION HRMS.FN_GET_NEXT_BASIC;

CREATE OR REPLACE FUNCTION HRMS.fn_get_next_basic (
    p_job_id         IN NUMBER,
    p_current_basic  IN NUMBER,
    p_eb_status      IN VARCHAR2 DEFAULT 'NORMAL',
    p_effective_date IN DATE DEFAULT SYSDATE
) RETURN NUMBER
IS
    v_scale_id        pay_scale_master.scale_id%TYPE;
    v_pre_eb_steps     pay_scale_master.steps_before_eb%TYPE;
    v_post_eb_steps    pay_scale_master.steps_after_eb%TYPE;
    v_start_basic      pay_scale_master.start_basic%TYPE;
    v_max_basic        pay_scale_master.max_basic%TYPE;
    v_current_step     pay_scale_detail.step_no%TYPE;
    v_next_step        pay_scale_detail.step_no%TYPE;
    v_total_steps      NUMBER;
    v_next_basic       pay_scale_detail.basic_amount%TYPE;
BEGIN
    /*
       PAY SCALE RULE
       ----------------
       Step 0  : starting basic (not an annual increment)
       Steps 1..10  : pre-EB increments
       Step 10      : EB basic / EB crossing point
       Steps 11..25 : post-EB increments
       Step 25      : maximum basic; no further increment is allowed

       The exact number of steps is read from PAY_SCALE_MASTER, while the
       table constraint requires pre-EB + post-EB = 25.
    */

    SELECT scale_id,
           steps_before_eb,
           steps_after_eb,
           start_basic,
           max_basic
      INTO v_scale_id,
           v_pre_eb_steps,
           v_post_eb_steps,
           v_start_basic,
           v_max_basic
      FROM (
            SELECT scale_id,
                   steps_before_eb,
                   steps_after_eb,
                   start_basic,
                   max_basic
              FROM pay_scale_master
             WHERE grade_id = p_job_id
               AND NVL(is_active, 'Y') = 'Y'
               AND TRUNC(NVL(p_effective_date, SYSDATE))
                   BETWEEN TRUNC(NVL(effective_from, DATE '1900-01-01'))
                       AND TRUNC(NVL(effective_to, DATE '2999-12-31'))
             ORDER BY revision_no DESC,
                      effective_from DESC NULLS LAST,
                      scale_id DESC
           )
     WHERE ROWNUM = 1;

    v_total_steps := v_pre_eb_steps + v_post_eb_steps;

    /* Never reduce an off-scale/legacy salary. */
    IF NVL(p_current_basic, 0) >= v_max_basic THEN
        RETURN NVL(p_current_basic, v_max_basic);
    END IF;

    /*
       Locate the employee's current position.  A salary below step 0 is
       treated as an initial placement and moves to START_BASIC.  For an
       off-step salary, the next higher configured step is selected.
    */
    SELECT NVL(MAX(step_no), -1)
      INTO v_current_step
      FROM pay_scale_detail
     WHERE scale_id = v_scale_id
       AND basic_amount <= NVL(p_current_basic, 0);

    v_next_step := v_current_step + 1;

    /* Hard cap: step 25 (10 pre-EB + 15 post-EB) is final. */
    IF v_current_step >= v_total_steps OR v_next_step > v_total_steps THEN
        RETURN p_current_basic;
    END IF;

    /*
       EB_HOLD blocks reaching the EB step and every post-EB step.  After
       an authorized EB release, EB_STATUS must be changed from EB_HOLD
       before this function is called again.
    */
    IF NVL(UPPER(p_eb_status), 'NORMAL') = 'EB_HOLD'
       AND v_next_step >= v_pre_eb_steps
    THEN
        RETURN p_current_basic;
    END IF;

    SELECT basic_amount
      INTO v_next_basic
      FROM pay_scale_detail
     WHERE scale_id = v_scale_id
       AND step_no = v_next_step;

    RETURN NVL(v_next_basic, p_current_basic);

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        /* Missing scale/detail is handled as a blocking precheck error. */
        RETURN p_current_basic;
END;
/
