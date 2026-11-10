-- ATT_DATE is the shift date; install before upgrading legacy rows.
CREATE OR REPLACE TRIGGER HRMS.trg_manual_att_date
    BEFORE INSERT OR UPDATE ON HRMS.manual_att FOR EACH ROW
BEGIN
    -- ATT_DATE is the shift date. Do not move an OUT-only night correction
    -- to the following day, or convert DATE through an NLS-dependent string.
    :NEW.att_date := TRUNC(NVL(:NEW.att_date, NVL(:NEW.m_intime, :NEW.m_outtime)));
END;
/
