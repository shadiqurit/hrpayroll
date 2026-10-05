-- Run manually in a TEST HRMS schema after INSTALL_EL_HISTORY.sql.
-- Uses a temporary employee and the user's historical transaction pattern.
-- All fixture business rows are rolled back, including on failure.
-- Fixtures use our reference copy only; LEAVE_DATA is never modified.
-- The existing employee-insert trigger requires company ID 1.
SET SERVEROUTPUT ON
DECLARE
    v_empid NUMBER;
    v_code VARCHAR2(30) := 'T' || SUBSTR(RAWTOHEX(SYS_GUID()), 1, 9);
    v_count NUMBER;
    v_value NUMBER;
    v_lt_id NUMBER;
    v_native_id NUMBER;
    PROCEDURE check_value(p_label VARCHAR2, p_actual NUMBER, p_expected NUMBER) IS
    BEGIN
        IF p_actual IS NULL OR p_actual <> p_expected THEN
            RAISE_APPLICATION_ERROR(-20084, p_label || ': expected ' || p_expected
                || ', actual ' || NVL(TO_CHAR(p_actual), 'NULL'));
        END IF;
        DBMS_OUTPUT.PUT_LINE('PASS: ' || p_label);
    END;
    PROCEDURE add_event(p_kind VARCHAR2, p_start DATE, p_end DATE, p_days NUMBER) IS
    BEGIN
        INSERT INTO HRMS.hr_el_legacy_ref
            (source_key, occurrence_no, empcode, leave_type, date_from, date_to,
             duration, legacy_year, leaveadtype, legacy_empid)
        VALUES (HRMS.fn_el_source_key(v_code, 'EL', p_start, p_end, p_days,
                    EXTRACT(YEAR FROM p_start), p_kind, v_empid),
            1, v_code, 'EL', p_start, p_end, p_days, EXTRACT(YEAR FROM p_start), p_kind, v_empid);
    END;
    PROCEDURE check_year(p_year NUMBER, p_expected NUMBER) IS
    BEGIN
        SELECT closing_balance INTO v_value FROM HRMS.v_el_year_balance
         WHERE empid = v_empid AND leave_year = p_year;
        check_value('Closing balance ' || p_year, v_value, p_expected);
    END;
BEGIN
    SAVEPOINT el_test_start;
    SELECT LEAST(NVL(MIN(id), 0), 0) - 1000 INTO v_empid FROM HRMS.employees;
    LOOP
        SELECT COUNT(*) INTO v_count FROM HRMS.employees WHERE id = v_empid OR empid = v_empid;
        EXIT WHEN v_count = 0;
        v_empid := v_empid - 1;
    END LOOP;
    INSERT INTO HRMS.employees
        (id, emp_id, empid, emp_type, join_date, dob, conf_date, status, com_id, user_grp)
    VALUES (v_empid, v_code, v_empid, '2', DATE '2010-01-01', DATE '1990-01-01',
            DATE '2010-01-01', 1, 1, NULL);
    FOR y IN 2010 .. 2015 LOOP
        add_event('Opening', TO_DATE(TO_CHAR(y) || '0101', 'YYYYMMDD'),
            TO_DATE(TO_CHAR(y) || '1231', 'YYYYMMDD'), 30);
    END LOOP;
    add_event('Encashment', DATE '2011-08-01', DATE '2011-09-29', 60);
    add_event('Leave', DATE '2013-09-15', DATE '2013-10-24', 40);
    add_event('Leave', DATE '2013-10-25', DATE '2013-11-06', 13);
    add_event('Leave', DATE '2014-07-27', DATE '2014-07-27', 1);
    add_event('Encashment', DATE '2015-05-02', DATE '2015-06-30', 60);

    HRMS.pkg_el_history.reconcile(DATE '2015-12-31', v_empid, 0);
    check_year(2010, 60);
    check_year(2011, 0);
    check_year(2012, 60);
    check_year(2013, 7);
    check_year(2014, 59);
    check_year(2015, 0);
    SELECT COUNT(*), SUM(allocated_days), MIN(leave_type_id)
      INTO v_count, v_value, v_lt_id FROM HRMS.leave_allocation WHERE empid = v_empid;
    check_value('One allocation per service year', v_count, 6);
    check_value('Earned EL is separate from snapshot balances', v_value, 180);
    SELECT SUM(adjustment_days) INTO v_value FROM HRMS.hr_el_legacy_event
     WHERE empid = v_empid AND active_flag = 'Y';
    check_value('Snapshot corrections are signed, not summed opening credits', v_value, -6);

    HRMS.pkg_el_history.reconcile(DATE '2015-12-31', v_empid, 0);
    SELECT COUNT(*) INTO v_count FROM HRMS.hr_el_legacy_event
     WHERE empid = v_empid AND active_flag = 'Y';
    check_value('Rerun imports each ERP event once', v_count, 11);
    SELECT COUNT(*) INTO v_count FROM HRMS.leave_allocation WHERE empid = v_empid;
    check_value('Rerun keeps yearly allocation row count', v_count, 6);
    check_year(2015, 0);

    -- Simulate refreshed reference content: changed fields get a new key.
    UPDATE HRMS.hr_el_legacy_ref SET active_flag = 'N'
     WHERE legacy_empid = v_empid AND date_from = DATE '2014-07-27' AND leaveadtype = 'Leave';
    add_event('Leave', DATE '2014-07-27', DATE '2014-07-27', 3);
    HRMS.pkg_el_history.reconcile(DATE '2015-12-31', v_empid, 0);
    check_year(2014, 57);
    check_year(2015, 0); -- The later Opening snapshot is still authoritative.
    UPDATE HRMS.hr_el_legacy_ref SET active_flag = 'N' WHERE legacy_empid = v_empid
       AND legacy_year = 2015 AND leaveadtype = 'Opening';
    HRMS.pkg_el_history.reconcile(DATE '2015-12-31', v_empid, 0);
    check_year(2015, 27);
    SELECT COUNT(*) INTO v_count FROM HRMS.hr_el_legacy_event
     WHERE empid = v_empid AND active_flag = 'N';
    check_value('Changed and removed ERP rows retained as inactive audit records', v_count, 2);

    -- Existing native consumption matching an ERP event must stop the import,
    -- and its failed call must preserve the prior successful reconciliation.
    SELECT LEAST(NVL(MIN(consumption_id), 0), 0) - 1000 INTO v_native_id FROM HRMS.leave_consumption;
    INSERT INTO HRMS.leave_consumption
        (consumption_id, empid, leave_type_id, consumed_days, consumption_date,
         start_date, end_date, com_id, consum_year)
    VALUES (v_native_id, v_empid, v_lt_id, 60, DATE '2011-08-01',
            DATE '2011-08-01', DATE '2011-09-29', 1, 2011);
    BEGIN
        HRMS.pkg_el_history.reconcile(DATE '2015-12-31', v_empid, 0);
        RAISE_APPLICATION_ERROR(-20084, 'Expected duplicate consumption protection.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE <> -20081 THEN RAISE; END IF;
        DBMS_OUTPUT.PUT_LINE('PASS: overlapping native/ERP consumption rejected');
    END;
    SELECT COUNT(*) INTO v_count FROM HRMS.hr_el_legacy_event
     WHERE empid = v_empid AND active_flag = 'N';
    check_value('Failed import rolls back ledger changes', v_count, 2);

    DELETE FROM HRMS.leave_consumption WHERE consumption_id = v_native_id;
    add_event('Opening', DATE '2016-01-01', DATE '2016-12-31', -5);
    HRMS.pkg_el_history.reconcile(DATE '2016-12-31', v_empid, 0);
    check_year(2016, 25); -- A signed Opening balance plus 30 earned days.

    ROLLBACK TO el_test_start;
    DBMS_OUTPUT.PUT_LINE('EL history integration checks passed; all fixture rows rolled back.');
EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO el_test_start;
    RAISE;
END;
/
