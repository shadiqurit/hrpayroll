DROP FUNCTION HRMS.F_GET_BASIC_BY_STEP;

CREATE OR REPLACE FUNCTION HRMS.f_get_basic_by_step (p_grade_code   IN VARCHAR2,
                                              p_step_no      IN NUMBER)
    RETURN NUMBER
AS
    v_basic   NUMBER (10, 2);
BEGIN
    SELECT d.basic_amount
      INTO v_basic
      FROM pay_scale_detail  d
           JOIN pay_scale_master s ON s.scale_id = d.scale_id
           JOIN job_grades g ON g.id = s.grade_id
     WHERE     g.grade_code = p_grade_code
           AND s.is_active = 'Y'
           AND d.step_no = p_step_no;

    RETURN v_basic;
EXCEPTION
    WHEN NO_DATA_FOUND
    THEN
        RETURN NULL;
END;
/
