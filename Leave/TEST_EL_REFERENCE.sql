-- Run manually in a TEST HRMS schema after INSTALL_EL_HISTORY.sql.
-- Reads the existing LEAVE_DATA only; reference-copy changes are rolled back.
-- Keep the source unchanged during these repeated-read checks.
SET SERVEROUTPUT ON
DECLARE
    TYPE key_map IS TABLE OF NUMBER INDEX BY VARCHAR2(100);
    v_ids key_map;
    v_key VARCHAR2(100);
    v_source_count NUMBER;
    v_copy_count NUMBER;
    v_bad_count NUMBER;
    PROCEDURE check_value(p_label VARCHAR2, p_actual NUMBER, p_expected NUMBER) IS
    BEGIN
        IF p_actual IS NULL OR p_actual <> p_expected THEN
            RAISE_APPLICATION_ERROR(-20088, p_label || ': expected ' || p_expected
                || ', actual ' || NVL(TO_CHAR(p_actual), 'NULL'));
        END IF;
        DBMS_OUTPUT.PUT_LINE('PASS: ' || p_label);
    END;
    FUNCTION fingerprint(p_code VARCHAR2, p_type VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN HRMS.fn_el_source_key(p_code, p_type, DATE '2010-01-01',
            DATE '2010-12-31', 30, 2010, 'Opening', 1);
    END;
BEGIN
    SAVEPOINT el_reference_test;
    check_value('Source key is SHA-256 hex', LENGTH(fingerprint('ab', 'c')), 64);
    IF fingerprint('ab', 'c') = fingerprint('a', 'bc')
       OR fingerprint(NULL, 'EL') = fingerprint('-1:', 'EL') THEN
        RAISE_APPLICATION_ERROR(-20088, 'Field boundaries/nulls must produce distinct keys.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('PASS: field boundaries and nulls have distinct keys');
    IF HRMS.fn_el_source_key('A', 'EL', DATE '2010-01-01', DATE '2010-12-31',
            30, 2010, 'Opening', 1)
       = HRMS.fn_el_source_key('A', 'EL', DATE '2010-01-01' + 1/86400,
            DATE '2010-12-31', 30, 2010, 'Opening', 1) THEN
        RAISE_APPLICATION_ERROR(-20088, 'Source time changes must produce distinct keys.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('PASS: source keys preserve date time');

    HRMS.pkg_el_history.stage_reference;
    SELECT COUNT(*) INTO v_source_count FROM HRMS.leave_data
     WHERE UPPER(TRIM(leave_type)) = 'EL';
    SELECT COUNT(*) INTO v_copy_count FROM HRMS.hr_el_legacy_ref WHERE active_flag = 'Y';
    check_value('Every source occurrence is copied', v_copy_count, v_source_count);
    SELECT COUNT(*) INTO v_bad_count FROM (
        SELECT source_key FROM HRMS.hr_el_legacy_ref WHERE active_flag = 'Y'
         GROUP BY source_key
        HAVING MIN(occurrence_no) <> 1 OR MAX(occurrence_no) <> COUNT(*)
    );
    check_value('Duplicate occurrences have contiguous stable numbers', v_bad_count, 0);

    FOR r IN (SELECT source_id, source_key, occurrence_no
                FROM HRMS.hr_el_legacy_ref WHERE active_flag = 'Y') LOOP
        v_key := r.source_key || ':' || TO_CHAR(r.occurrence_no, 'TM9');
        v_ids(v_key) := r.source_id;
    END LOOP;
    HRMS.pkg_el_history.stage_reference;
    SELECT COUNT(*) INTO v_copy_count FROM HRMS.hr_el_legacy_ref WHERE active_flag = 'Y';
    check_value('Repeated read retains occurrence count', v_copy_count, v_source_count);
    FOR r IN (SELECT source_id, source_key, occurrence_no
                FROM HRMS.hr_el_legacy_ref WHERE active_flag = 'Y') LOOP
        v_key := r.source_key || ':' || TO_CHAR(r.occurrence_no, 'TM9');
        IF NOT v_ids.EXISTS(v_key) THEN
            RAISE_APPLICATION_ERROR(-20088, 'Repeated read introduced an unexpected key.');
        END IF;
        IF v_ids(v_key) <> r.source_id THEN
            RAISE_APPLICATION_ERROR(-20088, 'Repeated read changed a reference ID.');
        END IF;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('PASS: repeated read retains reference IDs');
    ROLLBACK TO el_reference_test;
    DBMS_OUTPUT.PUT_LINE('Reference checks passed; all reference-copy changes rolled back.');
EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO el_reference_test;
    RAISE;
END;
/
