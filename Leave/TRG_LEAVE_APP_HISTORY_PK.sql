-- HRMS, SQL*Plus/SQLcl. Retains the sequence from earlier approval installs.
DECLARE
    l_count NUMBER;
    l_start NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM user_sequences
     WHERE sequence_name = 'SEQ_LEAVE_APPROVAL_HIST';
    IF l_count = 0 THEN
        SELECT GREATEST(NVL(MAX(id), 0) + 1, 1) INTO l_start FROM HRMS.leave_app_history;
        EXECUTE IMMEDIATE 'CREATE SEQUENCE HRMS.seq_leave_approval_hist START WITH '
            || TO_CHAR(l_start, 'FM9999999999999999999999999999') || ' NOCYCLE CACHE 20';
    END IF;
END;
/

CREATE OR REPLACE TRIGGER HRMS.trg_leave_app_history_pk
    BEFORE INSERT ON HRMS.leave_app_history
    FOR EACH ROW
BEGIN
    IF :NEW.id IS NULL THEN
        :NEW.id := HRMS.seq_leave_approval_hist.NEXTVAL;
    END IF;
END;
/
