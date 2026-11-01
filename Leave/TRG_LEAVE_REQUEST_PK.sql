-- HRMS, SQL*Plus/SQLcl. Pause request writes while first installing.
DECLARE
    l_count NUMBER;
    l_start NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM user_sequences WHERE sequence_name = 'SEQ_LEAVE_REQUEST';
    IF l_count = 0 THEN
        SELECT GREATEST(NVL(MAX(leave_id), 0) + 1, 1) INTO l_start FROM HRMS.leave_request;
        EXECUTE IMMEDIATE 'CREATE SEQUENCE HRMS.seq_leave_request START WITH '
            || TO_CHAR(l_start, 'FM9999999999999999999999999999') || ' NOCYCLE CACHE 20';
    END IF;
END;
/

CREATE OR REPLACE TRIGGER HRMS.trg_leave_request_pk
    BEFORE INSERT ON HRMS.leave_request
    FOR EACH ROW
BEGIN
    IF :NEW.leave_id IS NULL THEN
        :NEW.leave_id := HRMS.seq_leave_request.NEXTVAL;
    END IF;
END;
/
