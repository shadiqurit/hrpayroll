-- RECORD button: Server-side Condition > SQL Query (returns rows).
-- Also suitable for an optional HRD-only remarks region.
SELECT 1
  FROM v_leave_approval a
 WHERE a.leave_id = :P422_LEAVE_ID
   AND a.com_id = :G_COM_ID
   AND a.approver_id = :USER_ID
   AND a.approver_level = 'LEAVE_RECORD'
   AND a.approval_status = 'PENDING'
   AND a.leave_status = 'A'
   AND a.request_status = 'A'
   AND EXISTS (SELECT 1 FROM employees e
                WHERE e.id = a.empid AND e.com_id = :G_COM_ID);
