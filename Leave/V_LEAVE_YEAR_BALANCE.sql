-- Gross allocations stay unchanged. UNION ALL avoids multiplying allocation
-- and consumption rows when summing the employee/type/start-year account.
CREATE OR REPLACE VIEW HRMS.v_leave_year_balance AS
SELECT t.empid, t.leave_type_id, t.leave_year,
       SUM(t.allocated_days) AS allocated_days,
       SUM(t.consumed_days) AS consumed_days,
       SUM(t.allocated_days) - SUM(t.consumed_days) AS balance_days
  FROM (
      SELECT empid, leave_type_id, allocation_year AS leave_year,
             allocated_days, 0 AS consumed_days
        FROM HRMS.leave_allocation
      UNION ALL
      SELECT empid, leave_type_id, consum_year AS leave_year,
             0 AS allocated_days, consumed_days
        FROM HRMS.leave_consumption
  ) t
 GROUP BY t.empid, t.leave_type_id, t.leave_year;
