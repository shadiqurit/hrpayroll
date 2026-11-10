-- Page 410 HRD recorded region; open #REQUEST_URL# for the read-only detail.
SELECT a.*,
       APEX_PAGE.GET_URL(p_page => 418, p_clear_cache => '418',
                         p_items => 'P418_ID', p_values => TO_CHAR(a.id)) AS request_url
  FROM HRMS.v_m_att_approval a
 WHERE a.com_id = :G_COM_ID AND a.approver_id = :USER_ID
   AND a.workflow_version = 1 AND a.approver_level = 'LEAVE_RECORD'
   AND a.status = 'A' AND a.request_status = 'A' AND a.approval_status = 'RECORDED'
 ORDER BY a.approval_date DESC, a.id DESC;
