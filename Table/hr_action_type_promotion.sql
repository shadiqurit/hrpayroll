/* ============================================================
   HRMS PROMOTION ACTION TYPE
   ============================================================ */

MERGE INTO hr_action_type t
USING (SELECT 'PROMOTION' action_code, 'Employee Promotion' action_name FROM dual) s
   ON (t.action_code = s.action_code)
 WHEN NOT MATCHED THEN
      INSERT (action_code, action_name)
      VALUES (s.action_code, s.action_name);

