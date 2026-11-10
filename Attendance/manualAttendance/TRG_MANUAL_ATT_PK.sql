-- Pause writes during first installation. Sequence IDs are concurrency-safe.
DECLARE
    l_count NUMBER;
    l_start NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM user_sequences WHERE sequence_name = 'SEQ_MANUAL_ATT';
    IF l_count = 0 THEN
        SELECT GREATEST(NVL(MAX(id), 0) + 1, 1) INTO l_start FROM HRMS.manual_att;
        EXECUTE IMMEDIATE 'CREATE SEQUENCE HRMS.seq_manual_att START WITH '
            || TO_CHAR(l_start, 'FM9999999999999999999999999999') || ' NOCYCLE CACHE 20';
    END IF;
END;
/
CREATE OR REPLACE TRIGGER HRMS.trg_manual_att_pk
    BEFORE INSERT ON HRMS.manual_att FOR EACH ROW
BEGIN
    IF :NEW.id IS NULL THEN :NEW.id := HRMS.seq_manual_att.NEXTVAL; END IF;
END;
/
