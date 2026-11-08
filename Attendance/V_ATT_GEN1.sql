-- Historical office schedules. Replaces the current-month-only view.
-- Employee company/branch/machine mapping is current, as in the original view.
CREATE OR REPLACE VIEW HRMS.v_att_gen1
(
    id, mc_id, emp_id, branch_id, com_id, day_date,
    regular_in_time, regular_out_time
)
BEQUEATH DEFINER
AS
    WITH date_series (day_date) AS
    (
        SELECT MIN(TRUNC(o.schedule_start_date))
          FROM HRMS.office_schedule o
         WHERE o.schedule_start_date < TRUNC(SYSDATE) + 2
        HAVING COUNT(*) > 0

        UNION ALL

        SELECT day_date + 1
          FROM date_series
         WHERE day_date + 1 <= TRUNC(SYSDATE) + 1
    ),
    scheduled_days AS
    (
        SELECT e.id, e.mc_id, e.emp_id, e.branch_id, o.com_id, ds.day_date,
               CASE WHEN TRIM(o.office_start) IS NOT NULL THEN
                   TO_TIMESTAMP(TO_CHAR(ds.day_date, 'MM/DD/YYYY') || ' '
                       || TRIM(o.office_start), 'MM/DD/YYYY HH:MI AM')
               END AS scheduled_in,
               CASE WHEN TRIM(o.office_end) IS NOT NULL THEN
                   TO_TIMESTAMP(TO_CHAR(ds.day_date, 'MM/DD/YYYY') || ' '
                       || TRIM(o.office_end), 'MM/DD/YYYY HH:MI AM')
               END AS scheduled_out
          FROM date_series ds
          JOIN HRMS.office_schedule o
            ON ds.day_date BETWEEN TRUNC(o.schedule_start_date)
                               AND TRUNC(o.schedule_end_date)
          JOIN HRMS.employees e
            ON e.branch_id = o.location_id
           AND e.com_id = o.com_id
    )
    SELECT id, mc_id, emp_id, branch_id, com_id, day_date,
           scheduled_in AS regular_in_time,
           CASE WHEN scheduled_out <= scheduled_in
                THEN scheduled_out + INTERVAL '1' DAY
                ELSE scheduled_out
           END AS regular_out_time
      FROM scheduled_days;
/
