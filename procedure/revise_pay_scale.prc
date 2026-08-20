DROP PROCEDURE HRMS.REVISE_PAY_SCALE;

CREATE OR REPLACE PROCEDURE HRMS.revise_pay_scale (
    p_grade_id        IN NUMBER,
    p_start_basic     IN NUMBER,
    p_increment_1     IN NUMBER,
    p_steps_before_eb IN NUMBER DEFAULT 10,
    p_eb_basic        IN NUMBER,
    p_increment_2     IN NUMBER,
    p_steps_after_eb  IN NUMBER DEFAULT 15,
    p_max_basic       IN NUMBER,
    p_effective_from  IN DATE   DEFAULT SYSDATE,
    p_revision_name   IN VARCHAR2 DEFAULT NULL,
    p_approved_by     IN VARCHAR2 DEFAULT NULL
) AS
    v_old_scale_id  NUMBER;
    v_old_rev_no    NUMBER;
    v_new_scale_id  NUMBER;
BEGIN
    IF NVL(p_steps_before_eb, 0) <= 0
       OR NVL(p_steps_after_eb, 0) <= 0
    THEN
        RAISE_APPLICATION_ERROR(
            -20310,
            'Pre-EB and post-EB step counts must both be greater than zero.'
        );
    END IF;

    IF NVL(p_steps_before_eb, 0) + NVL(p_steps_after_eb, 0) <> 25 THEN
        RAISE_APPLICATION_ERROR(
            -20311,
            'A pay scale must contain exactly 25 increments: pre-EB plus post-EB.'
        );
    END IF;

    IF p_increment_1 <= 0 OR p_increment_2 <= 0 THEN
        RAISE_APPLICATION_ERROR(
            -20312,
            'Pre-EB and post-EB increment amounts must be greater than zero.'
        );
    END IF;

    IF p_eb_basic <>
       p_start_basic + (p_increment_1 * p_steps_before_eb)
    THEN
        RAISE_APPLICATION_ERROR(
            -20313,
            'EB basic must equal start basic plus all pre-EB increments.'
        );
    END IF;

    IF p_max_basic <>
       p_eb_basic + (p_increment_2 * p_steps_after_eb)
    THEN
        RAISE_APPLICATION_ERROR(
            -20314,
            'Maximum basic must equal EB basic plus all post-EB increments.'
        );
    END IF;

    -- Get current active scale for this grade
    BEGIN
        SELECT scale_id, revision_no
        INTO   v_old_scale_id, v_old_rev_no
        FROM   pay_scale_master
        WHERE  grade_id  = p_grade_id
        AND    is_active = 'Y';

        -- Deactivate old scale
        UPDATE pay_scale_master
        SET    is_active    = 'N',
               effective_to = p_effective_from - 1,
               updated_by   = USER,
               updated_date = SYSDATE
        WHERE  scale_id = v_old_scale_id;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_old_rev_no := 0;  -- First scale for this grade
    END;

    -- Insert new active scale
    INSERT INTO pay_scale_master (
        grade_id, revision_no, revision_name,
        start_basic, increment_1, steps_before_eb, eb_basic,
        increment_2, steps_after_eb, max_basic,
        is_active, effective_from,
        approved_by, approved_date
    ) VALUES (
        p_grade_id, v_old_rev_no + 1, p_revision_name,
        p_start_basic, p_increment_1, p_steps_before_eb, p_eb_basic,
        p_increment_2, p_steps_after_eb, p_max_basic,
        'Y', p_effective_from,
        p_approved_by, SYSDATE
    ) RETURNING scale_id INTO v_new_scale_id;

    -- Auto-populate step details
    populate_scale_detail(v_new_scale_id);

    COMMIT;
END;
/
