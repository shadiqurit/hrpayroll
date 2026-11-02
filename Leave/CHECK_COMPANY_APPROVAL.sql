-- Read-only diagnostics after INSTALL_COMPANY_APPROVAL.sql; no business DML.
SELECT object_name, object_type, status FROM user_objects
 WHERE object_name IN ('PKG_LEAVE_APPROVAL', 'V_LEAVE_APPROVAL_STEPS',
       'V_LEAVE_APPROVAL', 'V_EMP_LEAVE_TOTAL', 'TRG_LEAVE_REQUEST_PK',
       'TRG_LEAVE_APP_HISTORY_PK', 'TRG_LEAVE_REQUEST_STATUS');

SELECT name, type, line, position, text FROM user_errors
 WHERE name IN ('PKG_LEAVE_APPROVAL', 'V_LEAVE_APPROVAL_STEPS',
       'V_LEAVE_APPROVAL', 'V_EMP_LEAVE_TOTAL', 'TRG_LEAVE_REQUEST_PK',
       'TRG_LEAVE_APP_HISTORY_PK', 'TRG_LEAVE_REQUEST_STATUS')
 ORDER BY name, type, sequence;

-- HRD is required. Plant Head/MD are optional sources, but cannot be duplicated.
-- Each applicant must have at least one eligible higher-tier final candidate.
WITH companies AS (SELECT DISTINCT com_id FROM employees WHERE status = 1 AND com_id IS NOT NULL),
roles AS (SELECT 'PLANT_HEAD' role_code FROM dual UNION ALL
          SELECT 'MANAGING_DIRECTOR' FROM dual UNION ALL SELECT 'LEAVE_RECORD' FROM dual)
SELECT c.com_id, r.role_code, COUNT(v.id) AS assigned_count
  FROM companies c CROSS JOIN roles r LEFT JOIN v_leave_roles v
    ON v.company_id = c.com_id AND UPPER(TRIM(v.role_code)) = r.role_code
   AND UPPER(TRIM(v.active_yn)) = 'Y'
 GROUP BY c.com_id, r.role_code
HAVING (r.role_code = 'LEAVE_RECORD' AND COUNT(v.id) <> 1)
    OR (r.role_code <> 'LEAVE_RECORD' AND COUNT(v.id) > 1);

SELECT r.company_id, r.role_code, r.id, e.status AS employee_status
  FROM v_leave_roles r LEFT JOIN employees e ON e.id = r.id
 WHERE UPPER(TRIM(r.active_yn)) = 'Y'
   AND UPPER(TRIM(r.role_code)) IN ('PLANT_HEAD', 'MANAGING_DIRECTOR', 'LEAVE_RECORD')
   AND (e.id IS NULL OR NVL(e.status, 0) <> 1);

SELECT emp_id, COUNT(*) AS active_assignments FROM emp_rp
 WHERE UPPER(TRIM(status)) IN ('ACTIVE', '1', 'Y') AND rep_person_id IS NOT NULL
 GROUP BY emp_id HAVING COUNT(*) > 1;

SELECT r.emp_id, r.rep_person_id, a.com_id AS applicant_company,
       rp.com_id AS reporting_company, rp.status AS reporting_status
  FROM emp_rp r JOIN employees a ON a.id = r.emp_id
  LEFT JOIN employees rp ON rp.id = r.rep_person_id
 WHERE UPPER(TRIM(r.status)) IN ('ACTIVE', '1', 'Y') AND r.rep_person_id IS NOT NULL
   AND (rp.id IS NULL OR NVL(rp.status, 0) <> 1 OR rp.com_id IS NULL
        OR a.com_id IS NULL OR rp.com_id <> a.com_id OR rp.id = a.id);

-- Historical/inactive HOD assignments do not participate in routing.
SELECT h.dept_id, e.com_id, COUNT(*) AS assigned_count
  FROM hod h JOIN employees e ON e.id = h.hod_id
 WHERE UPPER(TRIM(h.status)) = 'ACTIVE'
 GROUP BY h.dept_id, e.com_id HAVING COUNT(*) > 1;

SELECT h.dept_id, h.hod_id, e.com_id, e.status
  FROM hod h LEFT JOIN employees e ON e.id = h.hod_id
 WHERE UPPER(TRIM(h.status)) = 'ACTIVE'
   AND (e.id IS NULL OR NVL(e.status, 0) <> 1);

-- RP must be pending alone, or ALL alternative final candidates are pending.
-- Multiple distinct final candidates pending together are valid.
-- Legacy sequential routes are retained and must be reviewed, not deleted.
SELECT lr.leave_id, COUNT(h.id) AS step_count,
       COUNT(CASE WHEN h.approval_status = 'PENDING' THEN 1 END) AS pending_count,
       COUNT(CASE WHEN h.approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR') THEN 1 END) AS final_candidates,
       COUNT(CASE WHEN h.approver_level = 'LEAVE_RECORD' THEN 1 END) AS hrd_count
  FROM leave_request lr LEFT JOIN leave_app_history h ON h.leave_id = lr.leave_id
 WHERE lr.leave_status = 'F' AND lr.request_status = 'F'
 GROUP BY lr.leave_id
HAVING COUNT(CASE WHEN h.approver_level = 'LEAVE_RECORD' THEN 1 END) <> 1
    OR COUNT(CASE WHEN h.approver_level = 'LEAVE_RECORD' AND h.approval_status = 'WAITING' THEN 1 END) <> 1
    OR COUNT(CASE WHEN h.approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR') THEN 1 END) = 0
    OR NOT (
        (COUNT(CASE WHEN h.approver_level = 'RP' AND h.approval_status = 'PENDING' THEN 1 END) = 1
         AND COUNT(CASE WHEN h.approval_status = 'PENDING' THEN 1 END) = 1
         AND COUNT(CASE WHEN h.approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR') AND h.approval_status = 'WAITING' THEN 1 END)
           = COUNT(CASE WHEN h.approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR') THEN 1 END))
        OR
        (COUNT(CASE WHEN h.approver_level = 'RP' THEN 1 END)
           = COUNT(CASE WHEN h.approver_level = 'RP' AND h.approval_status = 'APPROVED' THEN 1 END)
         AND COUNT(CASE WHEN h.approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR') AND h.approval_status = 'PENDING' THEN 1 END)
           = COUNT(CASE WHEN h.approver_level IN ('HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR') THEN 1 END)));

-- Ordinary employees must not have an MD approval step under the new policy.
SELECT lr.leave_id, lr.empid, h.approver_id AS legacy_md_id
  FROM leave_request lr JOIN leave_app_history h ON h.leave_id = lr.leave_id
 WHERE lr.leave_status = 'F' AND h.approver_level = 'MANAGING_DIRECTOR'
   AND NOT EXISTS (SELECT 1 FROM hod hd WHERE hd.hod_id = lr.empid
                    AND UPPER(TRIM(hd.status)) = 'ACTIVE')
   AND NOT EXISTS (SELECT 1 FROM v_leave_roles r
                    JOIN employees e ON e.com_id = r.company_id AND e.id = lr.empid
                   WHERE r.id = lr.empid AND UPPER(TRIM(r.role_code)) = 'PLANT_HEAD'
                     AND UPPER(TRIM(r.active_yn)) = 'Y');

SELECT leave_id, approver_level, COUNT(*) AS duplicate_steps FROM leave_app_history
 GROUP BY leave_id, approver_level HAVING COUNT(*) > 1;

-- One employee must not receive repeated approval steps in a saved route.
-- HRD's separate recording action is intentionally excluded.
SELECT leave_id, approver_id, COUNT(*) AS repeated_approval_assignments
  FROM leave_app_history
 WHERE approver_level IN ('RP', 'HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR')
 GROUP BY leave_id, approver_id HAVING COUNT(*) > 1;

SELECT lr.leave_id, lr.empid, lr.leave_status, lr.request_status,
       h.approver_level, h.approver_id, h.approval_status, h.com_id, h.step_no
  FROM leave_request lr JOIN v_leave_approval_steps h ON h.leave_id = lr.leave_id
 WHERE h.approval_status = 'PENDING'
 ORDER BY h.com_id, lr.leave_id, h.step_no;
