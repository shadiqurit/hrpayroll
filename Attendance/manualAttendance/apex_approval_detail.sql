-- Page 418 approval/detail region.
-- Authorize the detail form before rendering, including tampered ID links.
-- Applicants and saved-route participants can inspect the request and its history.
SELECT r.* FROM HRMS.v_m_att_report r
 WHERE r.id = :P418_ID AND r.com_id = :G_COM_ID
   AND (r.empid = :USER_ID OR EXISTS (
       SELECT 1 FROM HRMS.m_att_app_history h
        WHERE h.m_att_id = r.id AND h.com_id = :G_COM_ID AND h.approver_id = :USER_ID));
