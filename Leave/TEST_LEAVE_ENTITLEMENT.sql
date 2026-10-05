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
    check_days('January joiner full CL by June', 10, DATE '2026-01-01', 'CL', DATE '2026-06-30');
    check_days('January joiner full SL by June', 14, DATE '2026-01-01', 'SL', DATE '2026-06-30');
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
    check_days('January 15 remaining-year CL', 9.17, DATE '2026-01-15', 'CL', DATE '2026-07-14');
    check_days('Partial join month plus February milestone', 2, DATE '2026-01-15', 'EL', DATE '2026-02-13');
    check_days('Late January join earns February day 24 milestone', 2, DATE '2026-01-30', 'EL', DATE '2026-02-27');
    check_days('Calendar months reset independently', 4.5, DATE '2026-01-30', 'EL', DATE '2026-03-28');
    check_days('Future join date', 0, DATE '2027-01-01', 'CL');
    check_days('Missing join date', 0, NULL, 'SL');
    check_days('Missing DOB still gets EL', 30, DATE '2020-01-01', 'EL', p_dob => NULL);
    check_days('Selected prior year', 30, DATE '2020-01-01', 'EL', p_year => 2025);
    check_days('Selected future year', 0, DATE '2020-01-01', 'EL', p_year => 2027);
    check_days('Confirmation during year', 27, DATE '2020-01-01', 'EL', p_conf => DATE '2026-07-01');
    check_days('January joiner full SL upfront', 14, DATE '2026-01-01', 'SL', DATE '2026-01-01');
    check_days('January joiner full CL upfront', 10, DATE '2026-01-01', 'CL', DATE '2026-01-01');

    check_days('Prior-year employee full CL upfront', 10, DATE '2020-06-15', 'CL', DATE '2026-01-01');
    check_days('Prior-year employee full SL upfront', 14, DATE '2020-06-15', 'SL', DATE '2026-01-01');
    check_days('Recent prior-year joiner full CL', 10, DATE '2025-12-20', 'CL', DATE '2026-01-01');
    check_days('Recent prior-year joiner full SL', 14, DATE '2025-12-20', 'SL', DATE '2026-01-01');
    check_days('January 14 full CL', 10, DATE '2026-01-14', 'CL', DATE '2026-01-14');
    check_days('January 14 full SL', 14, DATE '2026-01-14', 'SL', DATE '2026-01-14');
    check_days('January 15 prorated CL upfront', 9.17, DATE '2026-01-15', 'CL', DATE '2026-01-15');
    check_days('January 15 prorated SL upfront', 12.83, DATE '2026-01-15', 'SL', DATE '2026-01-15');
    check_days('July joiner half CL upfront', 5, DATE '2026-07-01', 'CL', DATE '2026-07-01');
    check_days('July joiner half SL upfront', 7, DATE '2026-07-01', 'SL', DATE '2026-07-01');
    check_days('April joiner nine months CL', 7.5, DATE '2026-04-01', 'CL', DATE '2026-04-01');
    check_days('April joiner nine months SL', 10.5, DATE '2026-04-01', 'SL', DATE '2026-04-01');
    check_days('Future joiner gets no upfront CL', 0, DATE '2026-07-01', 'CL', DATE '2026-06-30');
    check_days('Future joiner gets no upfront SL', 0, DATE '2026-07-01', 'SL', DATE '2026-06-30');
    check_days('December 1 one month CL', 0.83, DATE '2026-12-01', 'CL', DATE '2026-12-01');
    check_days('December 1 one month SL', 1.17, DATE '2026-12-01', 'SL', DATE '2026-12-01');
    check_days('Selected prior year CL uses its year end', 5, DATE '2025-07-01', 'CL', p_year => 2025);
    check_days('Selected future year CL not yet available', 0, DATE '2020-01-01', 'CL', p_year => 2027);

    check_days('January before day 12', 0, DATE '2020-01-01', 'EL', DATE '2026-01-11');
    check_days('January day 12', 1, DATE '2020-01-01', 'EL', DATE '2026-01-12');
    check_days('January before day 24', 1, DATE '2020-01-01', 'EL', DATE '2026-01-23');
    check_days('January day 24', 2, DATE '2020-01-01', 'EL', DATE '2026-01-24');
    check_days('January before day 30', 2, DATE '2020-01-01', 'EL', DATE '2026-01-29');
    check_days('January day 30', 2.5, DATE '2020-01-01', 'EL', DATE '2026-01-30');
    check_days('January day 31 does not exceed cap', 2.5, DATE '2020-01-01', 'EL', DATE '2026-01-31');
    check_days('February before day 12', 2.5, DATE '2020-01-01', 'EL', DATE '2026-02-11');
    check_days('February day 12 cumulative', 3.5, DATE '2020-01-01', 'EL', DATE '2026-02-12');
    check_days('February day 24 cumulative', 4.5, DATE '2020-01-01', 'EL', DATE '2026-02-24');
    check_days('February before month end', 4.5, DATE '2020-01-01', 'EL', DATE '2026-02-27');
    check_days('February 28 cumulative', 5, DATE '2020-01-01', 'EL', DATE '2026-02-28');
    check_days('Leap February 28 not yet full', 4.5, DATE '2020-01-01', 'EL', DATE '2024-02-28', p_year => 2024);
    check_days('Leap February 29 cumulative', 5, DATE '2020-01-01', 'EL', DATE '2024-02-29', p_year => 2024);
    check_days('April before day 30', 9.5, DATE '2020-01-01', 'EL', DATE '2026-04-29');
    check_days('April day 30', 10, DATE '2020-01-01', 'EL', DATE '2026-04-30');
    check_days('Join date starts service day count', 0, DATE '2026-01-15', 'EL', DATE '2026-01-25');
    check_days('Twelve days from join date', 1, DATE '2026-01-15', 'EL', DATE '2026-01-26');
    check_days('Join month not given full quota', 1, DATE '2026-01-15', 'EL', DATE '2026-01-31');
    check_days('Late join before first milestone', 0, DATE '2026-12-25', 'EL');
    check_days('Repeated calculation is the same total', 5, DATE '2020-01-01', 'EL', DATE '2026-02-28');
    check_days('Confirmation before February cap', 4, DATE '2020-01-01', 'EL', DATE '2026-02-27', p_conf => DATE '2026-02-28');
    check_days('Confirmation on February cap', 4.5, DATE '2020-01-01', 'EL', DATE '2026-02-28', p_conf => DATE '2026-02-28');

    FOR r IN (SELECT id FROM HRMS.t_emp_typ WHERE id IN (1, 3)) LOOP
        check_days('Type ' || r.id || ' day 11', 0, DATE '2020-01-01', 'EL', DATE '2026-01-11', r.id);
        check_days('Type ' || r.id || ' day 12', 1, DATE '2020-01-01', 'EL', DATE '2026-01-12', r.id);
        check_days('Type ' || r.id || ' day 24', 2, DATE '2020-01-01', 'EL', DATE '2026-01-24', r.id);
        check_days('Type ' || r.id || ' monthly cap', 2, DATE '2020-01-01', 'EL', DATE '2026-01-31', r.id);
        check_days('Type ' || r.id || ' February day 12', 3, DATE '2020-01-01', 'EL', DATE '2026-02-12', r.id);
        check_days('Type ' || r.id || ' February day 24', 4, DATE '2020-01-01', 'EL', DATE '2026-02-24', r.id);
        check_days('Type ' || r.id || ' February cap', 4, DATE '2020-01-01', 'EL', DATE '2026-02-28', r.id);
    END LOOP;

    FOR r IN (SELECT id FROM HRMS.t_emp_typ WHERE id IN (0, 1, 2, 3, 4)) LOOP
        check_days('Type ' || r.id || ' CL upfront', 10, DATE '2026-01-14', 'CL', DATE '2026-01-14', r.id);
        check_days('Type ' || r.id || ' SL upfront', 14, DATE '2026-01-14', 'SL', DATE '2026-01-14', r.id);
        check_days('Type ' || r.id || ' partial CL upfront', 5, DATE '2026-07-01', 'CL', DATE '2026-07-01', r.id);
        check_days('Type ' || r.id || ' partial SL upfront', 7, DATE '2026-07-01', 'SL', DATE '2026-07-01', r.id);
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
