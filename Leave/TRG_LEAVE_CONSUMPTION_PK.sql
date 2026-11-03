-- SQL*Plus/SQLcl, HRMS. Pause consumption writes on first install.
DECLARE
    l_count NUMBER;
    l_start NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM user_sequences
     WHERE sequence_name = 'SEQ_LEAVE_CONSUMPTION';
    IF l_count = 0 THEN
        SELECT GREATEST(NVL(MAX(consumption_id), 0) + 1, 1) INTO l_start
          FROM HRMS.leave_consumption;
        EXECUTE IMMEDIATE 'CREATE SEQUENCE HRMS.seq_leave_consumption START WITH '
            || TO_CHAR(l_start, 'FM9999999999999999999999999999') || ' NOCYCLE CACHE 20';
    END IF;
END;
/
CREATE OR REPLACE TRIGGER HRMS.trg_leave_consumption_pk
    BEFORE INSERT ON HRMS.leave_consumption
    FOR EACH ROW
BEGIN
    IF :NEW.consumption_id IS NULL THEN
        :NEW.consumption_id := HRMS.seq_leave_consumption.NEXTVAL;
    END IF;
END;
/
