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
    v_days       NUMBER := 0;
BEGIN
    IF p_year IS NULL OR p_year <> TRUNC(p_year)
       OR p_year < 1 OR p_year > 9998 OR p_as_of_date IS NULL THEN
        RAISE_APPLICATION_ERROR(-20050, 'A valid year and allocation date are required.');
    END IF;

    IF p_rl_all_employees IS NULL OR p_rl_all_employees NOT IN (0, 1) THEN
        RAISE_APPLICATION_ERROR(-20053, 'RL eligibility must be 0 (restricted) or 1 (all employees).');
    END IF;

    v_year_start := TO_DATE(TO_CHAR(p_year, 'FM0000') || '0101', 'YYYYMMDD');
    v_year_end := ADD_MONTHS(v_year_start, 12);
    -- The allocation date is inclusive; a period ending June 30 earns six
    -- months for a January 1 join date. Never credit beyond the selected year.
    v_cutoff := LEAST(TRUNC(p_as_of_date) + 1, v_year_end);
    v_start := GREATEST(TRUNC(p_join_date), v_year_start);

    IF p_join_date IS NULL OR v_start >= v_cutoff THEN
        RETURN 0;
    END IF;

    -- Age 60 overrides every employee type, including confirmed employees.
    -- The requested policy clears EL entirely on the 60th birthday.
    IF v_code = 'EL' AND p_dob IS NOT NULL
       AND ADD_MONTHS(TRUNC(p_dob), 720) <= v_cutoff - 1 THEN
        RETURN 0;
    END IF;

    FOR i IN 1 .. 12 LOOP
        -- Anchoring every period on the original date handles month ends
        -- without accumulating February's shortened day into later months.
        v_credit := ADD_MONTHS(v_start, i);
        EXIT WHEN v_credit > v_cutoff;
        v_months := v_months + 1;
        IF v_code = 'EL' THEN
            -- T_EMP_TYP data: 2 = Confirmed; 0/1/3/4 earn the other rate.
            IF p_emp_type = 2
               AND (p_conf_date IS NULL OR TRUNC(p_conf_date) < v_credit) THEN
                v_days := v_days + 30 / 12;
            ELSE
                v_days := v_days + 24 / 12;
            END IF;
        END IF;
    END LOOP;

    CASE v_code
        WHEN 'EL' THEN RETURN ROUND(v_days, 2);
        WHEN 'SL' THEN RETURN ROUND(14 * v_months / 12, 2);
        WHEN 'CL' THEN RETURN ROUND(10 * v_months / 12, 2);
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
