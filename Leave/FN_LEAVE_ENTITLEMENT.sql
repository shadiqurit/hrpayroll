CREATE OR REPLACE FUNCTION HRMS.fn_leave_entitlement (
    p_year          IN NUMBER,
    p_as_of_date    IN DATE,
    p_join_date     IN DATE,
    p_dob           IN DATE,
    p_emp_type      IN NUMBER,
    p_conf_date     IN DATE,
    p_short_code    IN VARCHAR2,
    p_rl_all_employees IN NUMBER DEFAULT 0
) RETURN NUMBER
AUTHID DEFINER
AS
    v_year_start DATE;
    v_year_end   DATE;
    v_start      DATE;
    v_cutoff     DATE;
    v_credit     DATE;
    v_code       VARCHAR2(5) := UPPER(TRIM(p_short_code));
    v_months     PLS_INTEGER := 0;
BEGIN
    IF p_year IS NULL OR p_year <> TRUNC(p_year)
       OR p_year < 1 OR p_year > 9998 OR p_as_of_date IS NULL THEN
        RAISE_APPLICATION_ERROR(-20050, 'A valid year and allocation date are required.');
    END IF;

    IF p_rl_all_employees IS NULL OR p_rl_all_employees NOT IN (0, 1) THEN
        RAISE_APPLICATION_ERROR(-20053, 'RL eligibility must be 0 (restricted) or 1 (all employees).');
    END IF;

    -- EL has calendar-month day milestones, separate from SL/CL/RL proration.
    IF v_code = 'EL' THEN
        RETURN HRMS.fn_el_entitlement(
            p_year, p_as_of_date, p_join_date, p_dob, p_emp_type, p_conf_date);
    END IF;

    v_year_start := TO_DATE(TO_CHAR(p_year, 'FM0000') || '0101', 'YYYYMMDD');
    v_year_end := ADD_MONTHS(v_year_start, 12);
    -- The allocation date determines whether the employee has joined yet.
    -- RL uses elapsed months; SL/CL allocate the selected year's entitlement.
    v_cutoff := LEAST(TRUNC(p_as_of_date) + 1, v_year_end);
    v_start := GREATEST(TRUNC(p_join_date), v_year_start);

    IF p_join_date IS NULL OR v_start >= v_cutoff THEN
        RETURN 0;
    END IF;

    IF v_code IN ('SL', 'CL') THEN
        -- Prior-year employees and January 1-14 joiners receive the full
        -- annual quota upfront. January 15 is the first prorated join date.
        IF TRUNC(p_join_date) < v_year_start + 14 THEN
            v_months := 12;
        ELSE
            -- Prorate to the end of p_year, rather than waiting for months
            -- to elapse as of the allocation date. Count completed months.
            FOR i IN 1 .. 12 LOOP
                EXIT WHEN ADD_MONTHS(v_start, i) > v_year_end;
                v_months := v_months + 1;
            END LOOP;
        END IF;

        IF v_code = 'SL' THEN
            RETURN ROUND(14 * v_months / 12, 2);
        END IF;
        RETURN ROUND(10 * v_months / 12, 2);
    END IF;

    FOR i IN 1 .. 12 LOOP
        -- Anchoring every period on the original date handles month ends
        -- without accumulating February's shortened day into later months.
        v_credit := ADD_MONTHS(v_start, i);
        EXIT WHEN v_credit > v_cutoff;
        v_months := v_months + 1;
    END LOOP;

    CASE v_code
        WHEN 'RL' THEN
            -- T_EMP_TYP.ID = 3 is Contractual. Age 60+ also qualifies.
            IF p_rl_all_employees = 1 OR p_emp_type = 3
               OR (p_dob IS NOT NULL AND
                   ADD_MONTHS(TRUNC(p_dob), 720) <= v_cutoff - 1) THEN
                RETURN ROUND(15 * v_months / 12, 2);
            END IF;
            RETURN 0;
        ELSE RETURN 0;
    END CASE;
END fn_leave_entitlement;
/
