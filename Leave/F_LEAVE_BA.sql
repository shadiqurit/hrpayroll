-- Preserve the existing formatted API. All values come from one SQL snapshot.
CREATE OR REPLACE FUNCTION HRMS.f_leave_ba(
    p_empid IN NUMBER, p_leave_type_id IN NUMBER, p_year IN NUMBER)
    RETURN VARCHAR2 AUTHID DEFINER IS
    l_balance NUMBER;
    l_consumed NUMBER;
BEGIN
    SELECT NVL(MAX(balance_days), 0), NVL(MAX(consumed_days), 0)
      INTO l_balance, l_consumed
      FROM HRMS.v_leave_year_balance
     WHERE empid = p_empid AND leave_type_id = p_leave_type_id AND leave_year = p_year;
    RETURN 'Balance : ' || l_balance || ' Taken : ' || l_consumed;
EXCEPTION WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20001, 'Error calculating leave balance: ' || SQLERRM);
END f_leave_ba;
/
