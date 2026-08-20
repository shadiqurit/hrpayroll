CREATE OR REPLACE PROCEDURE HRMS.pr_release_increment_hold (
    p_emp_id      IN NUMBER,
    p_remarks     IN VARCHAR2,
    p_user_id     IN NUMBER,
    p_increment_id IN NUMBER DEFAULT NULL
)
IS
    v_action_id     NUMBER;
    v_hold_id       NUMBER;
    v_increment_id  NUMBER;
    v_effective_date DATE;
BEGIN
    SELECT hold_id
      INTO v_hold_id
      FROM (
            SELECT h.hold_id,
                   h.hold_from_date
              FROM hr_increment_hold h
             WHERE h.emp_id = p_emp_id
               AND h.hold_status = 'ACTIVE'
               AND (p_increment_id IS NULL OR h.increment_id = p_increment_id)
             ORDER BY h.hold_from_date DESC,
                      h.hold_id DESC
           )
     WHERE ROWNUM = 1;

    SELECT h.increment_id,
           i.effective_date
      INTO v_increment_id,
           v_effective_date
      FROM hr_increment_hold h
           JOIN hr_employee_increment i
             ON i.increment_id = h.increment_id
     WHERE h.hold_id = v_hold_id
       AND h.hold_status = 'ACTIVE'
       FOR UPDATE OF h.hold_status,
                     i.status;

    INSERT INTO hr_employee_action (
        emp_id,
        increment_id,
        action_type,
        action_date,
        effective_date,
        reason,
        remarks,
        approval_status,
        ent_by,
        approved_by,
        approved_date
    )
    VALUES (
        p_emp_id,
        v_increment_id,
        'INCREMENT_RELEASE',
        SYSDATE,
        v_effective_date,
        'Increment hold released',
        p_remarks,
        'APPROVED',
        p_user_id,
        p_user_id,
        SYSDATE
    )
    RETURNING action_id INTO v_action_id;

    UPDATE hr_increment_hold
    SET hold_status     = 'RELEASED',
        released_date   = SYSDATE,
        released_by     = p_user_id,
        release_remarks = p_remarks,
        upd_by          = p_user_id,
        upd_date        = SYSDATE
    WHERE hold_id = v_hold_id;

    UPDATE hr_employee_increment
       SET status       = 'READY',
           updated_by   = p_user_id,
           updated_date = SYSDATE
     WHERE increment_id = v_increment_id
       AND status = 'HOLD';

    UPDATE employees
    SET increment_hold_status = 'N',
        increment_hold_reason = NULL,
        increment_hold_date   = NULL
    WHERE id = p_emp_id
      AND NOT EXISTS (
            SELECT 1
              FROM hr_increment_hold h
             WHERE h.emp_id = p_emp_id
               AND h.hold_status = 'ACTIVE'
          );
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(
            -20130,
            'No active temporary hold was found for the selected increment occurrence.'
        );
END;
/
