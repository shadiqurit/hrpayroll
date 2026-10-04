-- Install after adding REQUEST_STATUS to LEAVE_REQUEST.
CREATE OR REPLACE TRIGGER HRMS.trg_leave_request_status
    BEFORE INSERT OR UPDATE OF leave_status ON HRMS.leave_request
    FOR EACH ROW
BEGIN
    -- A normal save defaults to Draft. Approval actions synchronize the stage.
    -- Saving an unchanged LEAVE_STATUS must not reset an existing stage.
    IF INSERTING
       OR NVL(UPPER(TRIM(:OLD.leave_status)), '#')
          <> NVL(UPPER(TRIM(:NEW.leave_status)), '#')
    THEN
        :NEW.request_status :=
            CASE UPPER(TRIM(:NEW.leave_status))
                WHEN 'P' THEN 'D'
                WHEN 'D' THEN 'D'
                WHEN 'F' THEN 'F'
                WHEN 'A' THEN 'A'
                -- Rejected/unknown requests are outside the draft stage.
                -- Rejection remains recorded in LEAVE_STATUS = R.
                ELSE 'F'
            END;
    END IF;
END;
/
