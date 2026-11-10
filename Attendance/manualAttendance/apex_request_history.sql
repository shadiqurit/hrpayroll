SELECT a.* FROM HRMS.v_m_att_approval a
 WHERE a.id = :P411_ID AND a.com_id = :G_COM_ID
   AND (a.empid = :USER_ID OR EXISTS (
       SELECT 1 FROM HRMS.m_att_app_history h
        WHERE h.m_att_id = a.id AND h.com_id = :G_COM_ID AND h.approver_id = :USER_ID))
 ORDER BY a.step_no, a.did;
