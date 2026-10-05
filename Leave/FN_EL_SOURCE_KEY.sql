CREATE OR REPLACE FUNCTION HRMS.fn_el_source_key (
    p_empcode VARCHAR2, p_leave_type VARCHAR2, p_date_from DATE, p_date_to DATE,
    p_duration NUMBER, p_year NUMBER, p_leaveadtype VARCHAR2, p_empid NUMBER
) RETURN VARCHAR2 AUTHID DEFINER DETERMINISTIC
AS
    v_text VARCHAR2(4000);
    v_key VARCHAR2(64);
    FUNCTION token(p_value VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        IF p_value IS NULL THEN RETURN '-1:'; END IF;
        RETURN TO_CHAR(LENGTH(p_value), 'TM9') || ':' || p_value;
    END;
    FUNCTION num(p_value NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(p_value, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''');
    END;
BEGIN
    -- Length-prefix fields to distinguish nulls, separators and empty values.
    -- Numeric date offsets include time and avoid NLS calendar/date formats.
    v_text := token(p_empcode) || token(p_leave_type)
        || token(num(p_date_from - DATE '2000-01-01'))
        || token(num(p_date_to - DATE '2000-01-01'))
        || token(num(p_duration)) || token(num(p_year))
        || token(p_leaveadtype) || token(num(p_empid));
    SELECT RAWTOHEX(STANDARD_HASH(v_text, 'SHA256')) INTO v_key FROM dual;
    RETURN v_key;
END fn_el_source_key;
/
