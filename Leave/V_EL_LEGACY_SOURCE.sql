CREATE OR REPLACE VIEW HRMS.v_el_legacy_source AS
WITH matches AS (
    SELECT ld.source_id, COUNT(DISTINCT e.id) match_count, MIN(e.id) target_empid
      FROM HRMS.hr_el_legacy_ref ld
      LEFT JOIN HRMS.employees e
        ON TRIM(ld.empcode) = TRIM(e.emp_id)
        OR ld.legacy_empid = e.id
        OR ld.legacy_empid = e.empid
     WHERE UPPER(TRIM(ld.leave_type)) = 'EL' AND ld.active_flag = 'Y'
     GROUP BY ld.source_id
)
SELECT ld.source_id,
       ld.empcode AS source_empcode, ld.legacy_empid AS source_empid,
       m.match_count,
       CASE WHEN m.match_count = 1 THEN m.target_empid END AS empid,
       UPPER(TRIM(ld.leaveadtype)) AS event_kind,
       TRUNC(ld.date_from) AS event_date, TRUNC(ld.date_to) AS end_date,
       ld.duration AS source_days, ld.legacy_year AS event_year
  FROM HRMS.hr_el_legacy_ref ld
  JOIN matches m ON m.source_id = ld.source_id;
