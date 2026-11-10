-- Page 411: SQL query returning rows; show entry/save buttons and enable inputs.
SELECT 1 FROM HRMS.employees e
 WHERE :P411_ID IS NULL AND e.id = :USER_ID AND e.com_id = :G_COM_ID AND e.status = 1
UNION ALL
SELECT 1 FROM HRMS.manual_att ma
 WHERE ma.id = :P411_ID AND ma.empid = :USER_ID AND ma.com_id = :G_COM_ID
   AND ma.workflow_version = 1 AND ma.request_status = 'D' AND ma.status IN ('D', 'P')
   AND NOT EXISTS (SELECT 1 FROM HRMS.m_att_app_history h WHERE h.m_att_id = ma.id);
