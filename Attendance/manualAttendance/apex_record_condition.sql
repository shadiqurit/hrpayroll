-- Page 418: SQL query returning rows; show RECORD for the assigned HRD user.
SELECT 1 FROM HRMS.manual_att ma
  JOIN HRMS.m_att_app_history h ON h.m_att_id = ma.id AND h.com_id = ma.com_id
 WHERE ma.id = :P418_ID AND ma.com_id = :G_COM_ID
   AND ma.workflow_version = 1 AND ma.status = 'A' AND ma.request_status = 'A'
   AND h.approver_id = :USER_ID AND h.approval_status = 'PENDING'
   AND h.approver_level = 'LEAVE_RECORD'
   AND EXISTS (SELECT 1 FROM HRMS.employees e WHERE e.id = ma.empid AND e.com_id = :G_COM_ID);
