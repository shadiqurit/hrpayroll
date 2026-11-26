-- ============================================================================
-- Page 486: After Submit Process (Save Draft & Submit to Workflow)
-- Processing -> Processing -> Add Process
-- Process Name: PROCESS_SHORT_LEAVE_FORM
-- Type: Execute Code (PL/SQL)
-- Server-side Condition: Request IN ('CREATE', 'APPLY', 'SAVE', 'SAVE_DRAFT', 'SUBMIT', 'FORWARD')
-- ============================================================================
DECLARE
    l_id       NUMBER := :P486_ID;
    l_req_date DATE;
    l_out_time DATE;
    l_in_time  DATE;

    FUNCTION parse_time(p_dt_str VARCHAR2, p_time_str VARCHAR2) RETURN DATE IS
        l_combined VARCHAR2(100);
    BEGIN
        IF TRIM(p_time_str) IS NULL THEN RETURN NULL; END IF;
        l_combined := TRIM(p_dt_str) || ' ' || TRIM(p_time_str);
        BEGIN RETURN TO_DATE(l_combined, 'YYYY-MM-DD HH12:MI AM'); EXCEPTION WHEN OTHERS THEN NULL; END;
        BEGIN RETURN TO_DATE(l_combined, 'YYYY-MM-DD HH24:MI'); EXCEPTION WHEN OTHERS THEN NULL; END;
        BEGIN RETURN TO_DATE(l_combined, 'DD-MON-YYYY HH12:MI AM'); EXCEPTION WHEN OTHERS THEN NULL; END;
        BEGIN RETURN TO_DATE(l_combined, 'DD-MON-YYYY HH24:MI'); EXCEPTION WHEN OTHERS THEN NULL; END;
        BEGIN RETURN TO_DATE(p_time_str, 'HH12:MI AM'); EXCEPTION WHEN OTHERS THEN NULL; END;
        BEGIN RETURN TO_DATE(p_time_str, 'HH24:MI'); EXCEPTION WHEN OTHERS THEN NULL; END;
        RETURN TO_DATE(l_combined);
    END;
BEGIN
    -- Parse Date
    BEGIN
        l_req_date := TO_DATE(:P486_REQ_DATE, 'YYYY-MM-DD');
    EXCEPTION WHEN OTHERS THEN
        l_req_date := TO_DATE(:P486_REQ_DATE);
    END;

    -- Parse Times
    l_out_time := parse_time(:P486_REQ_DATE, :P486_OUT_TIME);
    l_in_time  := parse_time(:P486_REQ_DATE, :P486_IN_TIME);

    SAVEPOINT sp_save_short_leave;

    -- 1. Save or Update Draft in Database
    HRMS.pkg_short_leave_approval.save_draft(
        p_id                => l_id,
        p_company_id        => :G_COM_ID,
        p_actor_id          => :USER_ID,
        p_empid             => :USER_ID,
        p_req_category      => :P486_REQ_CATEGORY,
        p_purpose_type      => :P486_PURPOSE_TYPE,
        p_req_date          => l_req_date,
        p_out_time          => l_out_time,
        p_in_time           => l_in_time,
        p_reason            => :P486_REASON_PURPOSE,
        p_destination       => :P486_DESTINATION_PLACE,
        p_contact           => :P486_CONTACT_DURING_ABS,
        p_transport_mode    => :P486_TRANSPORT_MODE,
        p_is_expense_claim  => NVL(:P486_IS_EXPENSE_CLAIM, 'N'),
        p_estimated_expense => TO_NUMBER(:P486_ESTIMATED_EXPENSE),
        p_comments          => NULL
    );

    -- 2. If user pressed Apply/Submit/Forward, route to Supervisor RP/HOD
    IF :REQUEST IN ('CREATE', 'APPLY', 'SUBMIT', 'FORWARD') THEN
        HRMS.pkg_short_leave_approval.submit_request(
            p_id         => l_id,
            p_company_id => :G_COM_ID,
            p_actor_id   => :USER_ID
        );
    END IF;

    :P486_ID := l_id;

EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO sp_save_short_leave;
    RAISE;
END;
