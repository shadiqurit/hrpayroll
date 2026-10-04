-- Install in the HRMS schema. Deletes one pending or draft leave request.
-- The caller controls COMMIT / ROLLBACK.
CREATE OR REPLACE PROCEDURE HRMS.delete_leave_request (
    p_leave_id IN NUMBER
) IS
    v_status HRMS.LEAVE_REQUEST.LEAVE_STATUS%TYPE;
    v_request_status HRMS.LEAVE_REQUEST.REQUEST_STATUS%TYPE;
BEGIN
    SAVEPOINT delete_leave_request_start;

    IF p_leave_id IS NULL THEN
        RAISE_APPLICATION_ERROR(-20001, 'Leave ID is required.');
    END IF;

    -- Lock the request so its status cannot change during deletion.
    BEGIN
        SELECT leave_status, request_status
          INTO v_status, v_request_status
          FROM HRMS.leave_request
         WHERE leave_id = p_leave_id
           FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20002, 'Leave request was not found.');
    END;

    -- P = pending, D = draft.
    v_status := UPPER(TRIM(v_status));
    IF v_status IS NULL OR v_status NOT IN ('P', 'D')
       OR v_request_status IS NULL OR v_request_status <> 'D'
    THEN
        RAISE_APPLICATION_ERROR(
            -20003,
            'Only pending or draft leave requests in the Draft stage can be deleted. Current status: '
            || NVL(v_status, '(NULL)')
            || ', request stage: ' || NVL(v_request_status, '(NULL)')
        );
    END IF;

    -- Remove all history for this request before deleting the parent row.
    DELETE FROM HRMS.leave_app_history
     WHERE leave_id = p_leave_id;

    DELETE FROM HRMS.leave_request
     WHERE leave_id = p_leave_id;
EXCEPTION
    WHEN OTHERS THEN
        -- Restore both tables if either delete fails; preserve earlier work.
        ROLLBACK TO delete_leave_request_start;
        RAISE;
END delete_leave_request;
/
