-- Install after PKG_M_ATT_APPROVAL.
CREATE OR REPLACE TRIGGER HRMS.trg_manual_att_guard
    BEFORE INSERT OR UPDATE OR DELETE ON HRMS.manual_att FOR EACH ROW
DECLARE
    FUNCTION changed(p_old NUMBER, p_new NUMBER) RETURN BOOLEAN IS
    BEGIN
        IF p_old IS NULL THEN RETURN p_new IS NOT NULL; END IF;
        IF p_new IS NULL THEN RETURN TRUE; END IF;
        RETURN p_old <> p_new;
    END;
BEGIN
    IF NOT HRMS.pkg_m_att_approval.workflow_write_allowed THEN
        IF INSERTING THEN
            :NEW.status := NVL(:NEW.status, 'D');
            :NEW.request_status := NVL(:NEW.request_status, 'D');
            IF :NEW.status <> 'D' OR :NEW.request_status <> 'D'
               OR NVL(:NEW.workflow_version, 0) <> 1 THEN
                RAISE_APPLICATION_ERROR(-20807, 'Create a draft using the manual attendance process.');
            END IF;
        ELSE
            IF NVL(:OLD.request_status, '#') <> 'D'
               OR NVL(:OLD.status, '#') NOT IN ('D', 'P') THEN
                RAISE_APPLICATION_ERROR(-20807, 'Submitted manual attendance cannot be edited or deleted.');
            END IF;
            IF UPDATING AND
               (NVL(:NEW.request_status, '#') <> 'D'
                OR NVL(:NEW.status, '#') NOT IN ('D', 'P')
                OR changed(:OLD.empid, :NEW.empid)
                OR changed(:OLD.com_id, :NEW.com_id)
                OR changed(:OLD.id, :NEW.id)
                OR changed(:OLD.workflow_version, :NEW.workflow_version)) THEN
                RAISE_APPLICATION_ERROR(-20807, 'Use the manual attendance workflow to change status.');
            END IF;
        END IF;
    END IF;
END;
/
