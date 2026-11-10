-- Page 410 pending region; both approvers and HRD use this inbox.
-- Open #REQUEST_URL# on Page 418. WAITING candidates are not actionable.
SELECT a.*,
       APEX_PAGE.GET_URL(p_page => 418, p_clear_cache => '418',
                         p_items => 'P418_ID', p_values => TO_CHAR(a.id)) AS request_url
  FROM HRMS.v_m_att_approval a
 WHERE a.com_id = :G_COM_ID AND a.approver_id = :USER_ID
   AND a.workflow_version = 1 AND a.approval_status = 'PENDING'
   AND EXISTS (SELECT 1 FROM HRMS.employees e
                WHERE e.id = a.empid AND e.com_id = :G_COM_ID)
   AND ((a.approver_level IN ('RP', 'HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR')
         AND a.status = 'F' AND a.request_status = 'F')
        OR (a.approver_level = 'LEAVE_RECORD' AND a.status = 'A' AND a.request_status = 'A'))
 ORDER BY a.id, a.step_no;
