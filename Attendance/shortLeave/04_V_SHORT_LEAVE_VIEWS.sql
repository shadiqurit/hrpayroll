-- ============================================================================
-- SHORT LEAVE & SHORT TOUR MODULE
-- 04_V_SHORT_LEAVE_VIEWS.sql
-- Views for APEX Applicant Report, Approval Inbox, and Monthly Balance
-- ============================================================================

-- 1. Applicant Applications Report View
CREATE OR REPLACE VIEW HRMS.v_short_leave_my_report AS
SELECT 
    r.id,
    r.req_no,
    r.empid,
    r.empcode,
    e.f_name || ' ' || e.l_name AS emp_name,
    d.dept_name AS department_name,
    ds.designation AS designation_name,
    r.com_id,
    r.req_category,
    CASE r.req_category
        WHEN 'SHORT_LEAVE' THEN 'Short Leave'
        WHEN 'SHORT_TOUR'  THEN 'Short Tour'
        ELSE r.req_category
    END AS req_category_desc,
    r.purpose_type,
    CASE r.purpose_type
        WHEN 'PERSONAL' THEN 'Personal'
        WHEN 'OFFICIAL' THEN 'Official'
        ELSE r.purpose_type
    END AS purpose_type_desc,
    r.req_date,
    TO_CHAR(r.req_date, 'DD-Mon-YYYY') AS req_date_char,
    TO_CHAR(r.out_time, 'HH12:MI AM')  AS out_time_char,
    TO_CHAR(r.in_time, 'HH12:MI AM')   AS in_time_char,
    r.duration_minutes,
    r.duration_display,
    r.reason_purpose,
    r.destination_place,
    r.contact_during_abs,
    r.transport_mode,
    r.is_expense_claim,
    r.estimated_expense,
    r.status,
    r.request_status,
    r.current_stage,
    -- Display Status with Current Approver Name
    CASE 
        WHEN r.status = 'D' THEN 'Draft'
        WHEN r.status = 'A' THEN 'Approved'
        WHEN r.status = 'R' THEN 'Rejected'
        WHEN r.status = 'C' THEN 'Cancelled'
        WHEN r.status = 'P' THEN 
            NVL(
                (SELECT 'Pending with ' || ap.f_name || ' ' || ap.l_name || ' (' || h.approver_level || ')'
                   FROM HRMS.short_leave_app_history h
                   JOIN HRMS.employees ap ON ap.id = h.approver_id
                  WHERE h.req_id = r.id AND h.approval_status = 'PENDING' AND ROWNUM = 1),
                'Pending Approval'
            )
        ELSE r.status
    END AS status_display_text,
    -- Live monthly quota count for that month
    HRMS.fn_get_monthly_sl_count(r.empid, r.req_date, 'SHORT_LEAVE', 'PERSONAL') AS monthly_sl_used,
    3 AS monthly_sl_quota,
    (3 - HRMS.fn_get_monthly_sl_count(r.empid, r.req_date, 'SHORT_LEAVE', 'PERSONAL')) AS monthly_sl_remaining,
    r.ent_date
  FROM HRMS.short_leave_tour_req r
  JOIN HRMS.employees e ON e.id = r.empid
  LEFT JOIN HRMS.departments d ON d.id = e.dept_id
  LEFT JOIN HRMS.designations ds ON ds.id = e.desig_id;


-- 2. Pending Approver Inbox View
CREATE OR REPLACE VIEW HRMS.v_short_leave_pending_inbox AS
SELECT 
    h.id AS history_id,
    h.req_id,
    r.req_no,
    r.empid,
    r.empcode,
    e.f_name || ' ' || e.l_name AS emp_name,
    d.dept_name AS department_name,
    ds.designation AS designation_name,
    r.req_category,
    r.purpose_type,
    r.req_date,
    TO_CHAR(r.req_date, 'DD-Mon-YYYY') AS req_date_char,
    TO_CHAR(r.out_time, 'HH12:MI AM')  AS out_time_char,
    TO_CHAR(r.in_time, 'HH12:MI AM')   AS in_time_char,
    r.duration_display,
    r.reason_purpose,
    r.destination_place,
    r.contact_during_abs,
    r.transport_mode,
    h.approver_level,
    h.approver_id,
    h.approval_status,
    h.step_no,
    r.com_id,
    -- Live monthly quota count for approver awareness
    HRMS.fn_get_monthly_sl_count(r.empid, r.req_date, 'SHORT_LEAVE', 'PERSONAL') AS monthly_sl_used,
    3 AS monthly_sl_quota,
    r.ent_date AS applied_date
  FROM HRMS.short_leave_app_history h
  JOIN HRMS.short_leave_tour_req r ON r.id = h.req_id
  JOIN HRMS.employees e ON e.id = r.empid
  LEFT JOIN HRMS.departments d ON d.id = e.dept_id
  LEFT JOIN HRMS.designations ds ON ds.id = e.desig_id
 WHERE h.approval_status = 'PENDING';
