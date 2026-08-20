DROP FUNCTION HRMS.F_GET_NEXT_INCREMENT;

CREATE OR REPLACE FUNCTION HRMS.f_get_next_increment (
    p_grade_code      IN VARCHAR2,
    p_current_basic   IN NUMBER,
    p_eb_status       IN VARCHAR2 DEFAULT 'NORMAL',
    p_effective_date  IN DATE DEFAULT SYSDATE
)
    RETURN VARCHAR2
AS
    v_result          VARCHAR2(1000);
    v_scale_id        NUMBER;
    v_pre_eb_steps    NUMBER;
    v_post_eb_steps   NUMBER;
    v_total_steps     NUMBER;
    v_max_basic       NUMBER;
    v_current_step    NUMBER;
    v_next_step       NUMBER;
    v_next_basic      NUMBER;
    v_increment       NUMBER;
    v_phase           VARCHAR2(10);
    v_is_eb_step      VARCHAR2(1);
BEGIN
    SELECT scale_id,
           steps_before_eb,
           steps_after_eb,
           max_basic
      INTO v_scale_id,
           v_pre_eb_steps,
           v_post_eb_steps,
           v_max_basic
      FROM (
            SELECT s.scale_id,
                   s.steps_before_eb,
                   s.steps_after_eb,
                   s.max_basic
              FROM pay_scale_master s
                   JOIN job_grades g ON g.id = s.grade_id
             WHERE g.grade_code = p_grade_code
               AND NVL(s.is_active, 'Y') = 'Y'
               AND TRUNC(NVL(p_effective_date, SYSDATE))
                   BETWEEN TRUNC(NVL(s.effective_from, DATE '1900-01-01'))
                       AND TRUNC(NVL(s.effective_to, DATE '2999-12-31'))
             ORDER BY s.revision_no DESC,
                      s.effective_from DESC NULLS LAST,
                      s.scale_id DESC
           )
     WHERE ROWNUM = 1;

    v_total_steps := v_pre_eb_steps + v_post_eb_steps;

    SELECT NVL(MAX(step_no), -1)
      INTO v_current_step
      FROM pay_scale_detail
     WHERE scale_id = v_scale_id
       AND basic_amount <= NVL(p_current_basic, 0);

    IF NVL(p_current_basic, 0) >= v_max_basic
       OR v_current_step >= v_total_steps
    THEN
        RETURN 'STATUS=MAX_REACHED'
               || '|CURRENT_STEP=' || v_current_step
               || '|NEXT_STEP=' || v_current_step
               || '|TOTAL_STEPS=' || v_total_steps
               || '|NEXT_BASIC=' || p_current_basic
               || '|INCREMENT=0'
               || '|PHASE=MAX'
               || '|EB_CROSSING=N'
               || '|REMAINING=0';
    END IF;

    v_next_step := v_current_step + 1;

    SELECT basic_amount,
           increment_amount,
           phase,
           is_eb_step
      INTO v_next_basic,
           v_increment,
           v_phase,
           v_is_eb_step
      FROM pay_scale_detail
     WHERE scale_id = v_scale_id
       AND step_no = v_next_step;

    IF NVL(UPPER(p_eb_status), 'NORMAL') = 'EB_HOLD'
       AND v_next_step >= v_pre_eb_steps
    THEN
        RETURN 'STATUS=EB_HOLD'
               || '|CURRENT_STEP=' || v_current_step
               || '|NEXT_STEP=' || v_next_step
               || '|TOTAL_STEPS=' || v_total_steps
               || '|NEXT_BASIC=' || p_current_basic
               || '|INCREMENT=0'
               || '|PHASE=' || v_phase
               || '|EB_CROSSING=' || v_is_eb_step
               || '|REMAINING=' || (v_total_steps - v_current_step);
    END IF;

    v_result := 'STATUS=AVAILABLE'
                || '|CURRENT_STEP=' || v_current_step
                || '|NEXT_STEP=' || v_next_step
                || '|TOTAL_STEPS=' || v_total_steps
                || '|NEXT_BASIC=' || v_next_basic
                || '|INCREMENT=' || NVL(v_increment, v_next_basic - NVL(p_current_basic, 0))
                || '|PHASE=' || v_phase
                || '|EB_CROSSING=' || v_is_eb_step
                || '|REMAINING=' || (v_total_steps - v_next_step);

    RETURN v_result;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 'STATUS=CONFIG_ERROR'
               || '|MESSAGE=Active pay scale or generated step is missing';
END;
/
