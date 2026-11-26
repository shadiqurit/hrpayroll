-- ============================================================================
-- SHORT LEAVE & SHORT TOUR MODULE
-- 02_FN_CHECK_SHORT_LEAVE_QUOTA.sql
-- Monthly Quota Validation Logic: Maximum 3 Short Leaves Allowed per Month
-- ============================================================================

CREATE OR REPLACE FUNCTION HRMS.fn_get_monthly_sl_count
(
    p_empid          IN NUMBER,
    p_req_date       IN DATE,
    p_req_category   IN VARCHAR2 DEFAULT 'SHORT_LEAVE',
    p_purpose_type   IN VARCHAR2 DEFAULT NULL,
    p_exclude_id     IN NUMBER   DEFAULT NULL
)
RETURN NUMBER
IS
    l_month_start DATE := TRUNC(NVL(p_req_date, SYSDATE), 'MM');
    l_month_end   DATE := LAST_DAY(TRUNC(NVL(p_req_date, SYSDATE)));
    l_count       NUMBER := 0;
BEGIN
    -- Counts all non-rejected, non-cancelled applications in the calendar month
    -- (Includes Pending 'P', Approved 'A', and Forwarded 'F' states)
    SELECT COUNT(*)
      INTO l_count
      FROM HRMS.short_leave_tour_req r
     WHERE r.empid = p_empid
       AND r.req_date BETWEEN l_month_start AND l_month_end
       AND r.req_category = NVL(p_req_category, 'SHORT_LEAVE')
       AND (p_purpose_type IS NULL OR r.purpose_type = p_purpose_type)
       AND r.status IN ('P', 'A', 'F')
       AND (p_exclude_id IS NULL OR r.id <> p_exclude_id);

    RETURN l_count;
END fn_get_monthly_sl_count;
/

CREATE OR REPLACE FUNCTION HRMS.fn_check_short_leave_quota
(
    p_empid          IN NUMBER,
    p_req_date       IN DATE,
    p_req_category   IN VARCHAR2 DEFAULT 'SHORT_LEAVE',
    p_purpose_type   IN VARCHAR2 DEFAULT 'PERSONAL',
    p_exclude_id     IN NUMBER   DEFAULT NULL,
    p_max_allowed    IN NUMBER   DEFAULT 3
)
RETURN VARCHAR2
IS
    l_used NUMBER;
BEGIN
    -- Policy: Quota limit (default 3) strictly applies to Short Leave.
    -- Short Tour or Official duties can be exempt or individually configured.
    IF p_req_category = 'SHORT_LEAVE' THEN
        l_used := HRMS.fn_get_monthly_sl_count(
            p_empid        => p_empid,
            p_req_date     => p_req_date,
            p_req_category => p_req_category,
            p_purpose_type => p_purpose_type,
            p_exclude_id   => p_exclude_id
        );
        
        IF l_used >= p_max_allowed THEN
            RETURN 'N'; -- Quota exceeded
        END IF;
    END IF;

    RETURN 'Y'; -- Allowed
END fn_check_short_leave_quota;
/

CREATE OR REPLACE PROCEDURE HRMS.pr_validate_sl_quota
(
    p_empid          IN NUMBER,
    p_req_date       IN DATE,
    p_req_category   IN VARCHAR2 DEFAULT 'SHORT_LEAVE',
    p_purpose_type   IN VARCHAR2 DEFAULT 'PERSONAL',
    p_exclude_id     IN NUMBER   DEFAULT NULL,
    p_max_allowed    IN NUMBER   DEFAULT 3
)
IS
    l_used       NUMBER;
    l_month_name VARCHAR2(30);
BEGIN
    IF p_req_category = 'SHORT_LEAVE' THEN
        l_used := HRMS.fn_get_monthly_sl_count(
            p_empid        => p_empid,
            p_req_date     => p_req_date,
            p_req_category => p_req_category,
            p_purpose_type => p_purpose_type,
            p_exclude_id   => p_exclude_id
        );

        IF l_used >= p_max_allowed THEN
            l_month_name := TO_CHAR(p_req_date, 'FMMonth YYYY');
            RAISE_APPLICATION_ERROR(-20850, 
                'Monthly limit exceeded: Maximum ' || p_max_allowed || 
                ' short leave(s) allowed per month. You already have ' || 
                l_used || ' short leave(s) in ' || l_month_name || '.');
        END IF;
    END IF;
END pr_validate_sl_quota;
/
