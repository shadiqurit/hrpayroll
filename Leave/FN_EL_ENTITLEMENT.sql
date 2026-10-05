CREATE OR REPLACE FUNCTION HRMS.fn_el_entitlement (
    p_year       IN NUMBER,
    p_as_of_date IN DATE,
    p_join_date  IN DATE,
    p_dob        IN DATE,
    p_emp_type   IN NUMBER,
    p_conf_date  IN DATE
) RETURN NUMBER
AUTHID DEFINER
AS
    v_year_start    DATE;
    v_cutoff        DATE;
    v_month_start   DATE;
    v_month_end     DATE;
    v_service_start DATE;
    v_period_end    DATE;
    v_service_days  NUMBER;
    v_month_quota   NUMBER;
    v_month_days    NUMBER;
    v_total         NUMBER := 0;
BEGIN
    IF p_year IS NULL OR p_year <> TRUNC(p_year)
       OR p_year < 1 OR p_year > 9998 OR p_as_of_date IS NULL THEN
        RAISE_APPLICATION_ERROR(-20050, 'A valid year and allocation date are required.');
    END IF;

    v_year_start := TO_DATE(TO_CHAR(p_year, 'FM0000') || '0101', 'YYYYMMDD');
    v_cutoff := LEAST(TRUNC(p_as_of_date), ADD_MONTHS(v_year_start, 12) - 1);
    IF p_join_date IS NULL OR TRUNC(p_join_date) > v_cutoff
       OR v_cutoff < v_year_start THEN
        RETURN 0;
    END IF;

    -- Clear the year's EL on the 60th birthday, including earlier accrual.
    IF p_dob IS NOT NULL AND ADD_MONTHS(TRUNC(p_dob), 720) <= v_cutoff THEN
        RETURN 0;
    END IF;

    FOR i IN 0 .. 11 LOOP
        v_month_start := ADD_MONTHS(v_year_start, i);
        EXIT WHEN v_month_start > v_cutoff;
        v_month_end := ADD_MONTHS(v_month_start, 1) - 1;
        v_service_start := GREATEST(TRUNC(p_join_date), v_month_start);
        v_period_end := LEAST(v_cutoff, v_month_end);
        IF v_service_start <= v_period_end THEN
            v_service_days := v_period_end - v_service_start + 1;
            -- T_EMP_TYP.ID 2 = Confirmed; other eligible IDs earn 24/year.
            IF p_emp_type = 2
               AND (p_conf_date IS NULL OR TRUNC(p_conf_date) <= v_period_end) THEN
                v_month_quota := 2.5;
            ELSE
                v_month_quota := 2;
            END IF;

            -- Reset milestones each calendar month. Day 30 reaches the cap
            -- in 30/31-day months; February reaches it on day 28/29.
            IF v_service_days >= LEAST(30, v_month_end - v_month_start + 1) THEN
                v_month_days := v_month_quota;
            ELSIF v_service_days >= 24 THEN
                v_month_days := 2;
            ELSIF v_service_days >= 12 THEN
                v_month_days := 1;
            ELSE
                v_month_days := 0;
            END IF;
            v_total := v_total + LEAST(v_month_days, v_month_quota);
        END IF;
    END LOOP;

    RETURN ROUND(v_total, 2);
END fn_el_entitlement;
/
