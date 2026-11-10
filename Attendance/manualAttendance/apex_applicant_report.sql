-- Page 410 register / My Manual Attendance. Display STATUS_TEXT.
-- Link target: #REQUEST_URL#; hide the REQUEST_URL report column.
SELECT r.*,
       APEX_PAGE.GET_URL(p_page => 411, p_clear_cache => '411',
                         p_items => 'P411_ID', p_values => TO_CHAR(r.id)) AS request_url
  FROM HRMS.v_m_att_report r
 WHERE r.empid = :USER_ID AND r.com_id = :G_COM_ID
 ORDER BY r.ent_date DESC, r.id DESC;
