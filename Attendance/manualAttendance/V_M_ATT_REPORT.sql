-- One row per request, including drafts (which have no approval history).
-- Pending names use the saved route; LEFT JOIN preserves missing employee names.
CREATE OR REPLACE VIEW HRMS.v_m_att_report AS
WITH pending_people AS (
    SELECT h.m_att_id,
           LISTAGG(NVL(TRIM(e.f_name || ' ' || e.l_name),
                       'Employee ID ' || TO_CHAR(h.approver_id)) ||
                   ' (' || h.approver_level_text || ')', ', ')
               WITHIN GROUP (ORDER BY h.id) AS pending_with
      FROM HRMS.v_m_att_approval_steps h
      LEFT JOIN HRMS.employees e ON e.id = h.approver_id
     WHERE UPPER(TRIM(h.approval_status)) IN ('PENDING', 'P')
     GROUP BY h.m_att_id
), recording AS (
    SELECT m_att_id,
           MAX(CASE WHEN approver_level = 'LEAVE_RECORD' AND approval_status = 'RECORDED'
                    THEN 1 ELSE 0 END) AS recorded
      FROM HRMS.m_att_app_history GROUP BY m_att_id
)
SELECT ma.*,
       v.fullname, v.department, v.designation,
       CASE UPPER(TRIM(ma.status))
           WHEN 'D' THEN 'Draft'
           WHEN 'DRAFT' THEN 'Draft'
           WHEN 'P' THEN CASE WHEN ma.request_status = 'D' THEN 'Draft' ELSE 'Pending' END
           WHEN 'F' THEN CASE WHEN ma.workflow_version = 0 THEN 'Pending - administrator review'
                             WHEN p.pending_with IS NOT NULL THEN 'Pending with ' || p.pending_with
                             ELSE 'Pending - route review required' END
           WHEN 'PENDING' THEN 'Pending - administrator review'
           WHEN 'A' THEN 'Approved'
           WHEN 'APPROVED' THEN 'Approved'
           WHEN 'R' THEN 'Rejected'
           WHEN 'REJECTED' THEN 'Rejected'
           ELSE 'Administrator review required'
       END AS status_text,
       CASE ma.request_status WHEN 'D' THEN 'Draft' WHEN 'F' THEN 'Forwarded'
                              WHEN 'A' THEN 'Final' END AS request_status_text,
       p.pending_with,
       CASE WHEN ma.workflow_version = 0 THEN 'Legacy - administrator review'
            WHEN ma.status = 'A' AND NVL(r.recorded, 0) = 1 THEN 'Recorded'
            WHEN ma.status = 'A' THEN 'Pending HRD recording'
            WHEN ma.status = 'R' THEN 'Not required'
            ELSE 'Awaiting approval' END AS recording_status
  FROM HRMS.manual_att ma
  LEFT JOIN HRMS.v_emp v ON v.emp_id = ma.empid
  LEFT JOIN pending_people p ON p.m_att_id = ma.id
  LEFT JOIN recording r ON r.m_att_id = ma.id;
