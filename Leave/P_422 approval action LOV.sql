-- Page 422, P422_APPROVAL_STATUS > List of Values > Type = SQL Query.
-- Action commands, not LEAVE_APP_HISTORY.APPROVAL_STATUS stored values.
SELECT 'APPROVE' AS display_value, 'APPROVE' AS return_value FROM dual
UNION ALL
SELECT 'REJECT' AS display_value, 'REJECT' AS return_value FROM dual;
