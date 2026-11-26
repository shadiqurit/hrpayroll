-- ============================================================================
-- Page 485: Monthly Quota Summary Badge / Card
-- Region Type: Cards or Classic Report / Static Content with SQL
-- ============================================================================
SELECT 
    TO_CHAR(SYSDATE, 'FMMonth YYYY')                                              AS current_month,
    3                                                                             AS max_allowed_quota,
    HRMS.fn_get_monthly_sl_count(:USER_ID, SYSDATE, 'SHORT_LEAVE', 'PERSONAL')    AS used_quota,
    (3 - HRMS.fn_get_monthly_sl_count(:USER_ID, SYSDATE, 'SHORT_LEAVE', 'PERSONAL')) AS remaining_quota
FROM DUAL;
