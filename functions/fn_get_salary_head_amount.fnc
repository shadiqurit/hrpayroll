DROP FUNCTION HRMS.FN_GET_SALARY_HEAD_AMOUNT;

CREATE OR REPLACE FUNCTION HRMS.fn_get_salary_head_amount (
    p_grade_id        IN NUMBER,
    p_headcode        IN VARCHAR2,
    p_basic           IN NUMBER,
    p_effective_date  IN DATE DEFAULT SYSDATE
) RETURN NUMBER
IS
    v_amount NUMBER;
BEGIN
    SELECT CASE p_headcode
             WHEN '001' THEN p_basic                         -- Basic
             WHEN '005' THEN ROUND(p_basic * NVL(hr,0) / 100) -- HR
             WHEN '013' THEN ROUND(p_basic * NVL(cpf,0) / 100) -- CPF earning
             WHEN '057' THEN ROUND(p_basic * NVL(pfcont,0) / 100) -- PF deduction
             WHEN '007' THEN NVL(conv,0)                     -- Conveyance
             WHEN '010' THEN NVL(medical,0)                  -- Medical
             WHEN '037' THEN NVL(allowance,0)                -- Allowance
             WHEN '075' THEN NVL(saf,0)                      -- SAF deduction
             ELSE NULL                                       -- keep unchanged
           END
      INTO v_amount
      FROM pay_scale_master
     WHERE grade_id = p_grade_id
       AND NVL(is_active,'Y') = 'Y'
       AND p_effective_date BETWEEN NVL(effective_from, DATE '1900-01-01')
                                AND NVL(effective_to, DATE '2999-12-31')
     ORDER BY revision_no DESC
     FETCH FIRST 1 ROW ONLY;

    RETURN v_amount;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN NULL;
END;
/
