-- Create tracking tables only. LEAVE_DATA is a read-only legacy reference.
DECLARE
    v_count NUMBER;
    v_next NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM all_tables
     WHERE owner = 'HRMS' AND table_name = 'HR_EL_LEGACY_EVENT';
    IF v_count = 0 THEN
        EXECUTE IMMEDIATE q'[
            CREATE TABLE HRMS.hr_el_legacy_event (
                source_id NUMBER PRIMARY KEY,
                empid NUMBER NOT NULL REFERENCES HRMS.employees(id),
                leave_type_id NUMBER NOT NULL REFERENCES HRMS.leave_types(lt_id),
                event_year NUMBER NOT NULL,
                event_date DATE NOT NULL,
                end_date DATE,
                event_kind VARCHAR2(15) NOT NULL,
                source_days NUMBER NOT NULL,
                adjustment_days NUMBER DEFAULT 0 NOT NULL,
                active_flag CHAR(1) DEFAULT 'Y' NOT NULL,
                imported_at DATE DEFAULT SYSDATE NOT NULL,
                CONSTRAINT ck_el_legacy_kind CHECK
                    (event_kind IN ('OPENING', 'LEAVE', 'ENCASHMENT')),
                CONSTRAINT ck_el_legacy_active CHECK (active_flag IN ('Y', 'N')),
                CONSTRAINT ck_el_legacy_days CHECK (event_kind = 'OPENING' OR source_days >= 0)
            )
        ]';
        EXECUTE IMMEDIATE 'CREATE INDEX HRMS.ix_el_legacy_emp_year '
            || 'ON HRMS.hr_el_legacy_event(empid, event_year, event_date)';
    END IF;

    SELECT COUNT(*) INTO v_count FROM all_tables
     WHERE owner = 'HRMS' AND table_name = 'HR_EL_LEGACY_REF';
    IF v_count = 0 THEN
        -- Avoid source-ID collisions if the previous import ledger exists.
        EXECUTE IMMEDIATE 'SELECT NVL(MAX(source_id), 0) + 1 FROM HRMS.hr_el_legacy_event'
            INTO v_next;
        EXECUTE IMMEDIATE 'CREATE TABLE HRMS.hr_el_legacy_ref ('
            || 'source_id NUMBER GENERATED ALWAYS AS IDENTITY (START WITH '
            || TO_CHAR(v_next, 'TM9') || ') PRIMARY KEY, '
            || 'source_key VARCHAR2(64) NOT NULL, occurrence_no NUMBER NOT NULL, '
            || 'empcode VARCHAR2(100), leave_type VARCHAR2(20), '
            || 'date_from DATE, date_to DATE, duration NUMBER, legacy_year NUMBER, '
            || 'leaveadtype VARCHAR2(100), legacy_empid NUMBER, '
            || 'active_flag CHAR(1) DEFAULT ''Y'' NOT NULL, '
            || 'copied_at DATE DEFAULT SYSDATE NOT NULL, '
            || 'CONSTRAINT uk_el_legacy_ref UNIQUE (source_key, occurrence_no), '
            || 'CONSTRAINT ck_el_ref_active CHECK (active_flag IN (''Y'', ''N'')), '
            || 'CONSTRAINT ck_el_ref_occurrence CHECK (occurrence_no >= 1))';
    END IF;
END;
/

COMMENT ON COLUMN HRMS.hr_el_legacy_event.adjustment_days IS
    'Signed correction making an OPENING snapshot equal to its source balance; not annual entitlement';
