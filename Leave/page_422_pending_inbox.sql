-- Page 422 pending inbox (or the existing report that opens Page 422).
-- Preserve existing edit links. Pass LEAVE_ID to P422_LEAVE_ID;
-- if the form key is P422_DID, pass DID there too.
-- USER_ID is numeric EMPLOYEES.ID. HRD uses the same pending inbox.
SELECT a.*
  FROM v_leave_approval a
 WHERE a.com_id = :G_COM_ID
   AND a.approver_id = :USER_ID
   AND a.approval_status = 'PENDING'
   AND EXISTS (SELECT 1 FROM employees e
                WHERE e.id = a.empid AND e.com_id = :G_COM_ID)
   AND (
       (a.approver_level IN ('RP', 'HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR')
        AND a.leave_status = 'F' AND a.request_status = 'F')
       OR
       (a.approver_level = 'LEAVE_RECORD'
        AND a.leave_status = 'A' AND a.request_status = 'A')
   )
 ORDER BY a.leave_id, a.step_no;
