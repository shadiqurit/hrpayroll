-- ============================================================================
-- Page 486: Server-side Validation for Monthly Quota (Max 3 Allowed)
-- Page Designer -> Validations -> Create Validation
-- Validation Name: VAL_SHORT_LEAVE_MONTHLY_LIMIT
-- Type: PL/SQL Function Returning Error Text
-- Associated Item: P486_REQ_DATE
-- Server-side Condition: Request IN ('CREATE', 'APPLY', 'SAVE', 'SUBMIT', 'FORWARD')
-- ============================================================================
DECLARE
    l_used       NUMBER;
    l_date       DATE;
    l_month_name VARCHAR2(50);
BEGIN
    IF TRIM(:P486_REQ_DATE) IS NULL THEN
        RETURN 'আবেদনের তারিখ প্রদান করুন।';
    END IF;

    -- Date parsing
    BEGIN
        l_date := TO_DATE(:P486_REQ_DATE, 'YYYY-MM-DD');
    EXCEPTION WHEN OTHERS THEN
        BEGIN
            l_date := TO_DATE(:P486_REQ_DATE, 'DD-MON-YYYY');
        EXCEPTION WHEN OTHERS THEN
            l_date := TO_DATE(:P486_REQ_DATE);
        END;
    END;

    -- Policy Check: Short Leave (Personal) is strictly capped at 3 per month
    IF :P486_REQ_CATEGORY = 'SHORT_LEAVE' AND :P486_PURPOSE_TYPE = 'PERSONAL' THEN
        l_used := HRMS.fn_get_monthly_sl_count(
            p_empid        => :USER_ID,
            p_req_date     => l_date,
            p_req_category => 'SHORT_LEAVE',
            p_purpose_type => 'PERSONAL',
            p_exclude_id   => :P486_ID
        );

        IF l_used >= 3 THEN
            l_month_name := TO_CHAR(l_date, 'FMMonth YYYY');
            RETURN 'মাসিক কোটা অতিক্রম করেছে! প্রতি মাসে সর্বোচ্চ ৩টি ব্যক্তিগত শর্ট লিভ অনুমোদিত। ' || 
                   l_month_name || ' মাসে আপনি ইতোমধ্যে ' || l_used || 'টি শর্ট লিভ নিয়েছেন/আবেদন করেছেন।';
        END IF;
    END IF;

    -- Time sequence check
    IF :P486_OUT_TIME IS NOT NULL AND :P486_IN_TIME IS NOT NULL THEN
        IF :P486_IN_TIME <= :P486_OUT_TIME THEN
            RETURN 'শেষ সময় (To Time) অবশ্যই শুরুর সময় (From Time) থেকে বেশি হতে হবে।';
        END IF;
    END IF;

    RETURN NULL;
END;
