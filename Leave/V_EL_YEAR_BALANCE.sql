CREATE OR REPLACE VIEW HRMS.v_el_year_balance AS
WITH allocations AS (
    SELECT la.empid, la.allocation_year AS leave_year,
           SUM(la.allocated_days) AS earned_days, MAX(la.allocated_date) AS as_of_date
      FROM HRMS.leave_allocation la
      JOIN HRMS.leave_types lt ON lt.lt_id = la.leave_type_id
     WHERE UPPER(TRIM(lt.short_code)) = 'EL'
       AND la.allocation_year <= EXTRACT(YEAR FROM la.allocated_date)
     GROUP BY la.empid, la.allocation_year
), legacy AS (
    SELECT l.empid, l.event_year,
           SUM(CASE WHEN l.event_kind = 'OPENING' THEN l.adjustment_days ELSE 0 END) AS opening_adjustment,
           SUM(CASE WHEN l.event_kind = 'LEAVE' THEN l.source_days ELSE 0 END) AS legacy_leave_days,
           SUM(CASE WHEN l.event_kind = 'ENCASHMENT' THEN l.source_days ELSE 0 END) AS encashment_days
      FROM HRMS.hr_el_legacy_event l
      JOIN allocations a ON a.empid = l.empid AND a.leave_year = l.event_year
     WHERE l.active_flag = 'Y' AND l.event_date <= TRUNC(a.as_of_date)
     GROUP BY l.empid, l.event_year
), native AS (
    SELECT lc.empid, lc.consum_year,
           SUM(CASE WHEN UPPER(TRIM(lt.short_code)) = 'EL' THEN lc.consumed_days ELSE 0 END) AS native_leave_days,
           SUM(CASE WHEN UPPER(TRIM(lt.short_code)) = 'EC' THEN lc.consumed_days ELSE 0 END) AS native_encashment_days
      FROM HRMS.leave_consumption lc
      JOIN HRMS.leave_types lt ON lt.lt_id = lc.leave_type_id
      JOIN allocations a ON a.empid = lc.empid AND a.leave_year = lc.consum_year
     WHERE UPPER(TRIM(lt.short_code)) IN ('EL', 'EC')
       AND TRUNC(NVL(lc.start_date, lc.consumption_date)) <= TRUNC(a.as_of_date)
     GROUP BY lc.empid, lc.consum_year
), amounts AS (
    SELECT a.empid, a.leave_year, a.as_of_date, a.earned_days,
           NVL(l.opening_adjustment, 0) AS opening_adjustment,
           NVL(l.legacy_leave_days, 0) AS legacy_leave_days,
           NVL(l.encashment_days, 0) AS encashment_days,
           NVL(n.native_leave_days, 0) AS native_leave_days,
           NVL(n.native_encashment_days, 0) AS native_encashment_days,
           a.earned_days + NVL(l.opening_adjustment, 0)
             - NVL(l.legacy_leave_days, 0) - NVL(l.encashment_days, 0)
             - NVL(n.native_leave_days, 0) - NVL(n.native_encashment_days, 0) AS year_change
      FROM allocations a
      LEFT JOIN legacy l ON l.empid = a.empid AND l.event_year = a.leave_year
      LEFT JOIN native n ON n.empid = a.empid AND n.consum_year = a.leave_year
)
SELECT a.empid, e.emp_id AS empcode, a.leave_year, a.as_of_date,
       NVL(SUM(a.year_change) OVER (PARTITION BY a.empid ORDER BY a.leave_year
           ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS opening_balance,
       a.earned_days, a.opening_adjustment, a.legacy_leave_days,
       a.encashment_days, a.native_leave_days, a.native_encashment_days,
       SUM(a.year_change) OVER (PARTITION BY a.empid ORDER BY a.leave_year
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS closing_balance
  FROM amounts a JOIN HRMS.employees e ON e.id = a.empid;

CREATE OR REPLACE VIEW HRMS.v_el_balance AS
SELECT empid, empcode, leave_year, as_of_date, closing_balance AS el_balance
  FROM (
    SELECT y.*, ROW_NUMBER() OVER (PARTITION BY empid ORDER BY leave_year DESC) AS rn
      FROM HRMS.v_el_year_balance y
  ) WHERE rn = 1;
