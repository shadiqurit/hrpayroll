CREATE OR REPLACE FORCE VIEW V_LEAVE_REPORT
AS
    SELECT lr.leave_id,
           lr.empid,
           IPI,
           FULLNAME,
           DOB,
           JOIN_DATE,
           DESIGNATION,
           DEPARTMENT,
           JOBLOC,
           lr.leave_type,
           lr.leave_balance,
           lr.leave_taken,
           lr.applied_date,
           lr.l_start_date,
           lr.l_end_date,
           lr.proposed_days,
           lr.leave_purpose,
           lr.app_leave_typ,
           lr.leave_address,
           CASE
               WHEN lr.leave_status = 'D' THEN 'Draft'
               WHEN lr.leave_status = 'P' THEN 'Pending'
               WHEN lr.leave_status = 'R' THEN 'Rejected'
               WHEN lr.leave_status = 'F' THEN 'Forwarded'
               WHEN lr.leave_status = 'A' THEN 'Approved'
           END    AS leave_status,
           lr.ent_date,
           lr.ent_by,
           lr.upd_date,
           lr.upd_by,
           comments,
           lr.request_status,
           CASE lr.request_status
               WHEN 'D' THEN 'Draft'
               WHEN 'F' THEN 'Forwarded'
               WHEN 'A' THEN 'Final'
           END AS request_status_text
      FROM leave_request lr, v_emp v
     WHERE lr.empid = v.EMP_ID;
