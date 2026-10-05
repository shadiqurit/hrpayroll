-- Run after PKG_EL_HISTORY.STAGE_REFERENCE. Read-only checks of the copy.
SELECT source_id, source_empcode, source_empid, match_count, empid
  FROM HRMS.v_el_legacy_source WHERE match_count <> 1;

SELECT ld.source_id, ld.empcode AS source_code, ld.legacy_empid AS source_empid,
       e.id AS candidate_empid, e.emp_id AS candidate_code, e.empid AS candidate_legacy_id
  FROM HRMS.hr_el_legacy_ref ld JOIN HRMS.employees e
    ON TRIM(ld.empcode) = TRIM(e.emp_id) OR ld.legacy_empid = e.id OR ld.legacy_empid = e.empid
 WHERE ld.active_flag = 'Y' AND UPPER(TRIM(ld.leave_type)) = 'EL' AND EXISTS (
    SELECT 1 FROM HRMS.v_el_legacy_source s
     WHERE s.source_id = ld.source_id AND s.match_count <> 1
 );

SELECT source_id, empid, event_kind, event_date, end_date, source_days, event_year
  FROM HRMS.v_el_legacy_source
 WHERE event_kind IS NULL OR event_kind NOT IN ('OPENING', 'LEAVE', 'ENCASHMENT')
    OR event_date IS NULL OR end_date IS NULL OR end_date < event_date
    OR source_days IS NULL OR (source_days < 0 AND event_kind <> 'OPENING') OR event_year IS NULL
    OR event_year <> EXTRACT(YEAR FROM event_date);

SELECT empid, event_date, COUNT(*) AS snapshot_count
  FROM HRMS.v_el_legacy_source WHERE event_kind = 'OPENING'
 GROUP BY empid, event_date HAVING COUNT(*) > 1;

-- Identical business rows need review; source IDs preserve distinct records.
SELECT empid, event_kind, event_date, end_date, source_days, COUNT(*) AS row_count
  FROM HRMS.v_el_legacy_source
 GROUP BY empid, event_kind, event_date, end_date, source_days HAVING COUNT(*) > 1;

SELECT e.id, e.emp_id, e.join_date, e.sep_date, e.status, e.emp_type
  FROM HRMS.employees e LEFT JOIN HRMS.t_emp_typ et ON TO_CHAR(et.id) = TRIM(e.emp_type)
 WHERE e.join_date IS NULL OR et.id IS NULL
    OR (NVL(e.status, 0) <> 1 AND e.sep_date IS NULL)
    OR e.sep_date < e.join_date;

SELECT s.source_id, s.source_empcode, e.join_date, e.sep_date, s.event_date
  FROM HRMS.v_el_legacy_source s JOIN HRMS.employees e ON e.id = s.empid
 WHERE s.event_date < TRUNC(e.join_date) OR s.event_date > TRUNC(e.sep_date);

-- Review all native consumption in ERP years: different dates/aggregation
-- can conceal prior imports. Do not count the same leave in both sources.
SELECT lc.* FROM HRMS.leave_consumption lc
  JOIN HRMS.leave_types lt ON lt.lt_id = lc.leave_type_id
 WHERE UPPER(TRIM(lt.short_code)) IN ('EL', 'EC') AND EXISTS (
    SELECT 1 FROM HRMS.v_el_legacy_source s
     WHERE s.empid = lc.empid AND s.event_year = lc.consum_year
       AND s.event_kind IN ('LEAVE', 'ENCASHMENT')
 );

SELECT * FROM HRMS.v_el_year_balance ORDER BY empid, leave_year;
SELECT lc.* FROM HRMS.leave_consumption lc
  JOIN HRMS.leave_types lt ON lt.lt_id = lc.leave_type_id
  JOIN HRMS.employees e ON e.id = lc.empid
 WHERE UPPER(TRIM(lt.short_code)) IN ('EL', 'EC')
   AND (lc.consum_year IS NULL OR lc.consum_year <> TRUNC(lc.consum_year)
     OR lc.consumed_days < 0 OR NVL(lc.start_date, lc.consumption_date) IS NULL
     OR lc.consum_year <> EXTRACT(YEAR FROM NVL(lc.start_date, lc.consumption_date))
     OR TRUNC(NVL(lc.start_date, lc.consumption_date)) < TRUNC(e.join_date)
     OR TRUNC(NVL(lc.start_date, lc.consumption_date)) > TRUNC(e.sep_date));

SELECT la.* FROM HRMS.leave_allocation la
  JOIN HRMS.leave_types lt ON lt.lt_id = la.leave_type_id
  JOIN HRMS.employees e ON e.id = la.empid
 WHERE UPPER(TRIM(lt.short_code)) = 'EL' AND la.allocated_days <> 0
   AND (la.allocation_year IS NULL OR la.allocation_year < EXTRACT(YEAR FROM e.join_date)
        OR la.allocated_date IS NULL
        OR TRUNC(la.allocated_date) > LEAST(TRUNC(SYSDATE), NVL(TRUNC(e.sep_date), TRUNC(SYSDATE))));

SELECT * FROM HRMS.v_el_balance WHERE el_balance < 0;
