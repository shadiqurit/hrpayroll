-- Trusted server API. Called by PKG_LEAVE_APPROVAL only after a final decision.
-- Caller owns COMMIT. Request + allocation locks protect retries and balance.
CREATE OR REPLACE PROCEDURE HRMS.post_leave_consumption(
    p_leave_id NUMBER, p_company_id NUMBER, p_actor_id NUMBER)
    AUTHID DEFINER IS
    l_request leave_request%ROWTYPE;
    l_company NUMBER;
    l_type NUMBER;
    l_year NUMBER;
    l_allocated NUMBER;
    l_consumed NUMBER;
    l_count NUMBER;
    l_matches NUMBER;
BEGIN
    SAVEPOINT leave_post_start;
    SELECT * INTO l_request FROM leave_request WHERE leave_id = p_leave_id FOR UPDATE;
    SELECT com_id INTO l_company FROM employees WHERE id = l_request.empid;
    IF p_company_id IS NULL OR l_company IS NULL OR l_company <> p_company_id
       OR NVL(l_request.leave_status, '#') <> 'A'
       OR NVL(l_request.request_status, '#') <> 'A' THEN
        RAISE_APPLICATION_ERROR(-20831, 'Only a final-approved request in the selected company can be posted.');
    END IF;
    SELECT COUNT(*) INTO l_count FROM employees WHERE id = p_actor_id AND status = 1;
    IF l_count <> 1 THEN
        RAISE_APPLICATION_ERROR(-20804, 'An active authenticated final approver is required.');
    END IF;
    SELECT COUNT(*), COUNT(CASE WHEN approver_id = p_actor_id AND com_id = p_company_id THEN 1 END)
      INTO l_count, l_matches FROM leave_app_history
     WHERE leave_id = p_leave_id AND approval_status = 'APPROVED'
       AND approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR');
    IF l_count <> 1 OR l_matches <> 1 OR p_actor_id = l_request.empid THEN
        RAISE_APPLICATION_ERROR(-20831, 'Consumption must be posted by the single recorded final approver.');
    END IF;
    IF l_request.l_start_date IS NULL OR l_request.l_end_date IS NULL
       OR TRUNC(l_request.l_end_date) < TRUNC(l_request.l_start_date)
       OR l_request.proposed_days IS NULL OR l_request.proposed_days <= 0 THEN
        RAISE_APPLICATION_ERROR(-20826, 'Valid leave dates and positive proposed days are required.');
    END IF;
    l_type := HRMS.fn_leave_type_id(l_request.leave_type, l_company);
    -- Entire approved quantity is charged to the start-date year, even if the
    -- end date is in the following year. Do not prorate or split PROPOSED_DAYS.
    l_year := EXTRACT(YEAR FROM l_request.l_start_date);
    BEGIN
        SELECT allocated_days INTO l_allocated FROM leave_allocation
         WHERE empid = l_request.empid AND leave_type_id = l_type AND allocation_year = l_year
         FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20834, 'No allocation exists for this employee, leave type, and start year.');
        WHEN TOO_MANY_ROWS THEN
            RAISE_APPLICATION_ERROR(-20834, 'Duplicate allocation rows require administrator review.');
    END;
    -- The allocation lock is acquired before reading consumption. Different
    -- requests for the same account cannot both spend the same remaining days.
    SELECT COUNT(*), COUNT(CASE
               WHEN empid = l_request.empid AND leave_type_id = l_type
                AND consumed_days = l_request.proposed_days AND consum_year = l_year
                AND TRUNC(start_date) = TRUNC(l_request.l_start_date)
                AND TRUNC(end_date) = TRUNC(l_request.l_end_date)
                AND com_id = p_company_id THEN 1 END)
      INTO l_count, l_matches FROM leave_consumption WHERE leave_id = p_leave_id;
    IF l_count > 0 THEN
        IF l_count <> 1 OR l_matches <> 1 THEN
            RAISE_APPLICATION_ERROR(-20835, 'Existing consumption does not match the approved request; review required.');
        END IF;
        -- A matching posted request is a safe retry; never insert or debit again.
    ELSE
        SELECT COUNT(*) INTO l_count FROM leave_consumption
         WHERE leave_id IS NULL AND empid = l_request.empid AND leave_type_id = l_type
           AND consumed_days = l_request.proposed_days
           AND TRUNC(NVL(start_date, consumption_date)) = TRUNC(l_request.l_start_date)
           AND (TRUNC(end_date) = TRUNC(l_request.l_end_date)
                OR (end_date IS NULL AND TRUNC(l_request.l_start_date) = TRUNC(l_request.l_end_date)));
        IF l_count > 0 THEN
            RAISE_APPLICATION_ERROR(-20838, 'Matching unlinked consumption already exists; review/link it instead of posting twice.');
        END IF;
        SELECT NVL(SUM(consumed_days), 0) INTO l_consumed FROM leave_consumption
         WHERE empid = l_request.empid AND leave_type_id = l_type AND consum_year = l_year;
        IF l_request.proposed_days > l_allocated - l_consumed THEN
            RAISE_APPLICATION_ERROR(-20836, 'Insufficient leave balance. Available: '
                || (l_allocated - l_consumed) || ', requested: ' || l_request.proposed_days);
        END IF;
        INSERT INTO leave_consumption
            (leave_id, empid, leave_type_id, consumed_days, consumption_date,
             start_date, end_date, ent_date, ent_by, com_id, consum_year)
        VALUES
            (p_leave_id, l_request.empid, l_type, l_request.proposed_days, SYSDATE,
             TRUNC(l_request.l_start_date), TRUNC(l_request.l_end_date),
             SYSDATE, p_actor_id, l_company, l_year);
    END IF;
    SELECT NVL(SUM(consumed_days), 0) INTO l_consumed FROM leave_consumption
     WHERE empid = l_request.empid AND leave_type_id = l_type AND consum_year = l_year;
    UPDATE leave_request
       SET leave_balance = l_allocated - l_consumed, leave_taken = l_consumed
     WHERE leave_id = p_leave_id;
EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO leave_post_start;
    RAISE;
END post_leave_consumption;
/
