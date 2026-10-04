-- Oracle regression checks: no employee, request, or allocation rows modified.
SET SERVEROUTPUT ON
DECLARE
    v_type_count NUMBER;
    PROCEDURE check_days (
        p_label VARCHAR2, p_expected NUMBER, p_join DATE,
        p_code VARCHAR2, p_as_of DATE DEFAULT DATE '2026-12-31',
        p_type NUMBER DEFAULT 2, p_dob DATE DEFAULT DATE '1990-01-01',
        p_conf DATE DEFAULT NULL, p_year NUMBER DEFAULT 2026,
        p_rl NUMBER DEFAULT 0
    ) IS
        v_actual NUMBER;
    BEGIN
        v_actual := HRMS.fn_leave_entitlement(
            p_year, p_as_of, p_join, p_dob, p_type, p_conf, p_code, p_rl);
        IF v_actual IS NULL OR v_actual <> p_expected THEN
            RAISE_APPLICATION_ERROR(-20055, p_label || ': expected '
                || p_expected || ', received ' || NVL(TO_CHAR(v_actual), 'NULL'));
        END IF;
        DBMS_OUTPUT.PUT_LINE('PASS: ' || p_label);
    END;
BEGIN
    SELECT COUNT(*) INTO v_type_count FROM HRMS.t_emp_typ
     WHERE (id = 0 AND etype = 'Reguler')
        OR (id = 1 AND etype = 'Probation')
        OR (id = 2 AND etype = 'Confirmed')
        OR (id = 3 AND etype = 'Contractual')
        OR (id = 4 AND etype = 'Casual');
    IF v_type_count <> 5 THEN
        RAISE_APPLICATION_ERROR(-20057, 'T_EMP_TYP does not match the supplied numeric type reference data.');
    END IF;

    check_days('Confirmed annual EL', 30, DATE '2020-01-01', 'EL');
    check_days('Probation annual EL', 24, DATE '2020-01-01', 'EL', p_type => 1);
    check_days('Contractual annual EL', 24, DATE '2020-01-01', 'EL', p_type => 3);
    check_days('Reguler annual EL', 24, DATE '2020-01-01', 'EL', p_type => 0);
    check_days('Casual annual EL', 24, DATE '2020-01-01', 'EL', p_type => 4);
    check_days('Confirmed first month', 2.5, DATE '2026-01-01', 'EL', DATE '2026-01-31');
    check_days('Probation first month', 2, DATE '2026-01-01', 'EL', DATE '2026-01-31', 1);
    check_days('Six month CL', 5, DATE '2026-01-01', 'CL', DATE '2026-06-30');
    check_days('Six month SL', 7, DATE '2026-01-01', 'SL', DATE '2026-06-30');
    check_days('Six month confirmed EL', 15, DATE '2026-01-01', 'EL', DATE '2026-06-30');
    check_days('Six month contractual EL', 12, DATE '2026-01-01', 'EL', DATE '2026-06-30', 3);
    check_days('Contractual annual RL', 15, DATE '2020-01-01', 'RL', p_type => 3);
    check_days('Six month contractual RL', 7.5, DATE '2026-01-01', 'RL', DATE '2026-06-30', 3);
    check_days('RL for all override', 15, DATE '2020-01-01', 'RL', p_rl => 1);
    check_days('Ineligible RL', 0, DATE '2020-01-01', 'RL', p_rl => 0);
    check_days('Age exactly 60', 0, DATE '2020-01-01', 'EL', DATE '2026-06-30', 2, DATE '1966-06-30');
    check_days('Before 60th birthday', 15, DATE '2020-01-01', 'EL', DATE '2026-06-30', 2, DATE '1966-07-01');
    check_days('Clear earlier EL on birthday', 0, DATE '2020-01-01', 'EL', DATE '2026-07-01', 2, DATE '1966-07-01');
    check_days('60+ retains SL', 14, DATE '2020-01-01', 'SL', p_dob => DATE '1960-01-01');
    check_days('60+ retains CL', 10, DATE '2020-01-01', 'CL', p_dob => DATE '1960-01-01');
    check_days('60+ retains RL', 15, DATE '2020-01-01', 'RL', p_dob => DATE '1960-01-01');
    check_days('New joiner annual proration', 5, DATE '2026-07-01', 'CL');
    check_days('Midmonth anniversary', 5, DATE '2026-01-15', 'CL', DATE '2026-07-14');
    check_days('Incomplete first month', 0, DATE '2026-01-15', 'EL', DATE '2026-02-13');
    check_days('January 30 to February end', 2.5, DATE '2026-01-30', 'EL', DATE '2026-02-27');
    check_days('No month end drift', 2.5, DATE '2026-01-30', 'EL', DATE '2026-03-28');
    check_days('Future join date', 0, DATE '2027-01-01', 'CL');
    check_days('Missing join date', 0, NULL, 'SL');
    check_days('Missing DOB still gets EL', 30, DATE '2020-01-01', 'EL', p_dob => NULL);
    check_days('Selected prior year', 30, DATE '2020-01-01', 'EL', p_year => 2025);
    check_days('Selected future year', 0, DATE '2020-01-01', 'EL', p_year => 2027);
    check_days('Confirmation during year', 27, DATE '2020-01-01', 'EL', p_conf => DATE '2026-07-01');
    check_days('Monthly SL fraction', 1.17, DATE '2026-01-01', 'SL', DATE '2026-01-31');
    check_days('Monthly CL fraction', 0.83, DATE '2026-01-01', 'CL', DATE '2026-01-31');

    FOR r IN (SELECT id FROM HRMS.t_emp_typ WHERE id IN (0, 1, 2, 3, 4)) LOOP
        check_days('Type ' || r.id || ' annual SL', 14, DATE '2020-01-01', 'SL', p_type => r.id);
        check_days('Type ' || r.id || ' annual CL', 10, DATE '2020-01-01', 'CL', p_type => r.id);
        check_days('Type ' || r.id || ' EL at 60+', 0, DATE '2020-01-01', 'EL',
            p_type => r.id, p_dob => DATE '1960-01-01');
        check_days('Type ' || r.id || ' RL at 60+', 15, DATE '2020-01-01', 'RL',
            p_type => r.id, p_dob => DATE '1960-01-01');
        IF r.id <> 3 THEN
            check_days('Type ' || r.id || ' no RL under 60', 0, DATE '2020-01-01', 'RL', p_type => r.id);
        END IF;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('All leave entitlement checks passed.');
END;
/
