-- Read-only diagnostics. Run after installing.
SELECT name, type, line, position, text FROM user_errors
 WHERE name IN ('PKG_M_ATT_APPROVAL', 'POST_MANUAL_ATTENDANCE', 'P_ATT_REBUILD_MANUAL',
                'P_ATT_UPDATE_DETAILS', 'TRG_MANUAL_ATT_GUARD', 'TRG_MANUAL_ATT_DATE',
                'V_M_ATT_REPORT', 'V_M_ATT_APPROVAL', 'V_M_ATT_APPROVAL_STEPS')
 ORDER BY name, sequence;

SELECT ma.id, ma.empid, ma.att_date, ma.status, ma.request_status, COUNT(h.id) AS history_rows
  FROM manual_att ma LEFT JOIN m_att_app_history h ON h.m_att_id = ma.id
 WHERE ma.workflow_version = 0
 GROUP BY ma.id, ma.empid, ma.att_date, ma.status, ma.request_status ORDER BY ma.id;

SELECT empid, TRUNC(att_date) AS att_date, COUNT(*) AS overlapping_requests
  FROM manual_att WHERE UPPER(TRIM(status)) IN ('F', 'A', 'PENDING', 'APPROVED')
 GROUP BY empid, TRUNC(att_date) HAVING COUNT(*) > 1;

SELECT ma.id, ma.com_id AS request_company, e.com_id AS current_company
  FROM manual_att ma LEFT JOIN employees e ON e.id = ma.empid
 WHERE ma.com_id IS NULL OR e.com_id IS NULL OR ma.com_id <> e.com_id;

SELECT ma.id, ma.empid, ma.att_date, COUNT(d.attendance_id) AS attendance_rows
  FROM manual_att ma LEFT JOIN attendance_details d
    ON d.emp_id = ma.empid AND d.com_id = ma.com_id
   AND d.attendance_date >= TRUNC(ma.att_date) AND d.attendance_date < TRUNC(ma.att_date) + 1
 WHERE ma.workflow_version = 1 AND ma.status IN ('F', 'A')
 GROUP BY ma.id, ma.empid, ma.att_date HAVING COUNT(d.attendance_id) <> 1;

SELECT id, empid, status_text, pending_with, recording_status FROM v_m_att_report
 WHERE workflow_version = 1 AND status IN ('F', 'A') ORDER BY id;
