-- Pause writes during first installation. Sequence IDs are concurrency-safe.
DECLARE
    l_count NUMBER;
    l_start NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM user_sequences WHERE sequence_name = 'SEQ_M_ATT_APP_HISTORY';
    IF l_count = 0 THEN
        SELECT GREATEST(NVL(MAX(id), 0) + 1, 1) INTO l_start FROM HRMS.m_att_app_history;
        EXECUTE IMMEDIATE 'CREATE SEQUENCE HRMS.seq_m_att_app_history START WITH '
            || TO_CHAR(l_start, 'FM9999999999999999999999999999') || ' NOCYCLE CACHE 20';
    END IF;
END;
/
CREATE OR REPLACE TRIGGER HRMS.trg_m_att_app_history_pk
    BEFORE INSERT ON HRMS.m_att_app_history FOR EACH ROW
BEGIN
    IF :NEW.id IS NULL THEN :NEW.id := HRMS.seq_m_att_app_history.NEXTVAL; END IF;
END;
/
