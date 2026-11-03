-- Page 419 report SQL Source. USER_ID is numeric EMPLOYEES.ID.
-- Pending people come from the saved route, not today's RP/HOD/role setup.
-- One display column: LEAVE_STATUS includes pending names and roles.
-- Final approval displays Approved even while HRD recording remains pending.
-- Balance/taken are live amounts for the request's start-year account.
WITH pending_step AS (
    SELECT h.leave_id,
           LISTAGG(
               NVL(TRIM(e.f_name || ' ' || e.l_name),
                   'Employee ID ' || TO_CHAR(h.approver_id)) || ' (' ||
               CASE h.approver_level
                   WHEN 'RP' THEN 'RP'
                   WHEN 'HOD' THEN 'HOD'
                   WHEN 'PLANT_HEAD' THEN 'Plant Head'
                   WHEN 'MANAGING_DIRECTOR' THEN 'Managing Director'
               END || ')', ', ')
               WITHIN GROUP (ORDER BY h.id) AS pending_details
      FROM leave_app_history h
      LEFT JOIN employees e ON e.id = h.approver_id
     WHERE h.approval_status = 'PENDING'
       AND h.approver_level IN ('RP', 'HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR')
     GROUP BY h.leave_id
)
SELECT lr.leave_id,
       lr.empid,
       lr.leave_type,
       NVL(b.balance_days, 0) AS leave_balance,
       NVL(b.consumed_days, 0) AS leave_taken,
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
           WHEN 'F' THEN
               CASE WHEN p.pending_details IS NOT NULL
                   THEN 'Pending with ' || p.pending_details
                   ELSE 'Pending'
               END
           WHEN 'A' THEN 'Approved'
       END AS leave_status,
       lr.ent_date,
       lr.ent_by,
       lr.upd_date,
       lr.upd_by,
       lr.comments
  FROM leave_request lr
  LEFT JOIN employees applicant ON applicant.id = lr.empid
  LEFT JOIN leave_consumption posted ON posted.leave_id = lr.leave_id
  LEFT JOIN v_leave_year_balance b
    ON b.empid = lr.empid
   AND b.leave_type_id = CASE WHEN posted.leave_type_id IS NOT NULL
       THEN posted.leave_type_id
       ELSE HRMS.fn_leave_type_id(lr.leave_type, applicant.com_id,
           CASE WHEN lr.leave_status IN ('P', 'D', 'F') THEN 1 ELSE 0 END) END
   AND b.leave_year = CASE WHEN posted.leave_id IS NOT NULL
       THEN posted.consum_year ELSE EXTRACT(YEAR FROM lr.l_start_date) END
  LEFT JOIN pending_step p
    ON p.leave_id = lr.leave_id AND lr.leave_status = 'F'
 WHERE lr.empid = :USER_ID;
