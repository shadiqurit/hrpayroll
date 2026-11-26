-- ============================================================================
-- Page 487: Short Leave & Tour Approval Inbox Query
-- Region Type: Interactive Report
-- Source: SQL Query
-- ============================================================================
SELECT 
    h.history_id,
    h.req_id,
    h.req_no,
    h.empcode || ' - ' || h.emp_name                   AS employee,
    h.department_name,
    h.designation_name,
    h.req_category,
    CASE h.req_category
        WHEN 'SHORT_LEAVE' THEN 'Short Leave'
        WHEN 'SHORT_TOUR'  THEN 'Short Tour'
        ELSE h.req_category
    END AS category_desc,
    h.purpose_type,
    CASE h.purpose_type
        WHEN 'PERSONAL' THEN 'Personal'
        WHEN 'OFFICIAL' THEN 'Official'
        ELSE h.purpose_type
    END AS purpose_type_desc,
    h.req_date_char                                    AS leave_date,
    h.out_time_char || ' - ' || h.in_time_char         AS timings,
    h.duration_display                                 AS duration,
    h.reason_purpose                                   AS reason,
    h.destination_place                                AS destination,
    -- Live usage indicator for approver awareness
    h.monthly_sl_used || ' of 3 used'                  AS monthly_quota_status,
    h.approver_level,
    h.applied_date
FROM HRMS.v_short_leave_pending_inbox h
WHERE h.approver_id = :USER_ID
ORDER BY h.applied_date DESC;
