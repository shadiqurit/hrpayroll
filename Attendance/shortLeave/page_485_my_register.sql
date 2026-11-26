-- ============================================================================
-- Page 485: Short Leave & Tour Register - My Applications Query
-- Region Type: Interactive Report
-- Source: SQL Query
-- ============================================================================
SELECT 
    r.id,
    r.req_no,
    r.req_category_desc                                AS category,
    r.purpose_type_desc                                AS purpose_type,
    r.req_date_char                                    AS leave_date,
    r.out_time_char || ' - ' || r.in_time_char         AS timings,
    r.duration_display                                 AS duration,
    r.reason_purpose                                   AS reason,
    r.destination_place                                AS destination,
    r.status_display_text                              AS status,
    r.status                                           AS raw_status,
    -- Edit/View Link using APEX_PAGE.GET_URL
    CASE 
        WHEN r.status = 'D' THEN
            APEX_PAGE.GET_URL(
                p_page        => '486',
                p_clear_cache => '486',
                p_items       => 'P486_ID',
                p_values      => r.id
            )
        ELSE
            APEX_PAGE.GET_URL(
                p_page        => '486',
                p_clear_cache => '486',
                p_items       => 'P486_ID,P486_READONLY',
                p_values      => r.id || ',Y'
            )
    END AS action_url
FROM HRMS.v_short_leave_my_report r
WHERE r.empid = :USER_ID
ORDER BY r.req_date DESC, r.id DESC;
