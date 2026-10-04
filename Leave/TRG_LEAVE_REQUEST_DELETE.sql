-- Install after REQUEST_STATUS exists. Covers direct / APEX form deletes.
CREATE OR REPLACE TRIGGER HRMS.trg_leave_request_delete
    BEFORE DELETE ON HRMS.leave_request
    FOR EACH ROW
BEGIN
    -- Read :OLD instead of querying the table being deleted.
    IF NVL(UPPER(TRIM(:OLD.leave_status)), '#') NOT IN ('P', 'D')
       OR NVL(:OLD.request_status, '#') <> 'D'
    THEN
        RAISE_APPLICATION_ERROR(
            -20003,
            'Only pending or draft leave requests in the Draft stage can be deleted.'
        );
    END IF;

    -- The FK stays enabled. Remove children before Oracle deletes the parent.
    DELETE FROM HRMS.leave_app_history
     WHERE leave_id = :OLD.leave_id;
END;
/
