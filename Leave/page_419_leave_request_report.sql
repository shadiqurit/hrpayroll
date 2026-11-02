-- Page 419 report SQL Source. USER_ID is numeric EMPLOYEES.ID.
-- Pending people come from the saved route, not today's RP/HOD/role setup.
-- Aggregate history so even duplicate pending steps do not duplicate requests.
WITH pending_step AS (
    SELECT h.leave_id,
           COUNT(*) AS pending_count,
           COUNT(DISTINCT h.approver_id) AS pending_people,
           COUNT(DISTINCT h.approver_level) AS pending_roles,
           COUNT(DISTINCT CASE h.approver_level
               WHEN 'RP' THEN 10
               WHEN 'HOD' THEN 20
               WHEN 'PLANT_HEAD' THEN 20
               WHEN 'MANAGING_DIRECTOR' THEN 20
               WHEN 'LEAVE_RECORD' THEN 50
               ELSE -1 END) AS pending_groups,
           LISTAGG(
               NVL(TRIM(e.f_name || ' ' || e.l_name),
                   'Employee ID ' || TO_CHAR(h.approver_id)), ', ')
               WITHIN GROUP (ORDER BY h.id) AS pending_with,
           LISTAGG(
               CASE h.approver_level
                   WHEN 'RP' THEN 'RP (Reporting Person)'
                   WHEN 'HOD' THEN 'HOD (Head of Department)'
                   WHEN 'PLANT_HEAD' THEN 'Plant Head'
                   WHEN 'MANAGING_DIRECTOR' THEN 'Managing Director'
                   WHEN 'LEAVE_RECORD' THEN 'HRD Record Keeping'
                   ELSE NVL(h.approver_level, 'Unknown Role')
               END, ', ')
               WITHIN GROUP (ORDER BY h.id) AS pending_role
      FROM leave_app_history h
      LEFT JOIN employees e ON e.id = h.approver_id
     WHERE h.approval_status = 'PENDING'
     GROUP BY h.leave_id
)
SELECT lr.leave_id,
       lr.empid,
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
       CASE lr.leave_status
           WHEN 'D' THEN 'Draft'
           WHEN 'P' THEN 'Pending'
           WHEN 'R' THEN 'Rejected'
           WHEN 'F' THEN 'Forwarded'
           WHEN 'A' THEN 'Approved'
       END AS leave_status,
       lr.ent_date,
       lr.ent_by,
       lr.upd_date,
       lr.upd_by,
       lr.comments,
       p.pending_with,
       p.pending_role,
       CASE
           WHEN lr.leave_status = 'R' THEN 'Rejected'
           WHEN lr.leave_status IN ('P', 'D') THEN 'Not Submitted'
           WHEN p.pending_count > p.pending_people
             OR p.pending_count > p.pending_roles
             OR p.pending_groups > 1 THEN 'Review: Invalid Pending Assignments'
           WHEN lr.leave_status = 'A' AND p.leave_id IS NOT NULL
               THEN 'Pending HRD Recording'
           WHEN lr.leave_status = 'A' THEN 'Approved'
           WHEN lr.leave_status = 'F' AND p.leave_id IS NOT NULL
               THEN 'Pending Approval'
           ELSE 'Approval Route Requires Review'
       END AS current_stage
  FROM leave_request lr
  LEFT JOIN pending_step p
    ON p.leave_id = lr.leave_id AND lr.leave_status IN ('F', 'A')
 WHERE lr.empid = :USER_ID;
