-- Read-only SQL*Plus/SQLcl diagnostic. No rebuild, UPDATE or COMMIT.
-- Usage: @Attendance/DIAGNOSE_ATTENDANCE_DAY.sql 123 2026-09-02
-- 123 must be EMPLOYEES.ID (numeric database key), not the printed employee code.
SET VERIFY OFF
SET LINESIZE 240
SET PAGESIZE 200
DEFINE att_emp_id = '&1'
DEFINE att_day = '&2'

PROMPT 1. Current employee mapping and target-date source counts
SELECT e.id, e.emp_id AS employee_code, e.mc_id, e.com_id, e.branch_id,
       (SELECT COUNT(*) FROM HRMS.v_att_gen g
         WHERE g.emp_id = e.id
           AND g.attendance_date >= TO_DATE('&&att_day', 'YYYY-MM-DD')
           AND g.attendance_date < TO_DATE('&&att_day', 'YYYY-MM-DD') + 1)
           AS source_schedule_rows,
       (SELECT COUNT(*) FROM HRMS.attendance_details d
         WHERE d.emp_id = e.id
           AND d.attendance_date >= TO_DATE('&&att_day', 'YYYY-MM-DD')
           AND d.attendance_date < TO_DATE('&&att_day', 'YYYY-MM-DD') + 1)
           AS stored_attendance_rows
  FROM HRMS.employees e
 WHERE e.id = TO_NUMBER('&&att_emp_id');

PROMPT 2. Actual attendance, including neighbouring days
SELECT d.attendance_id, d.emp_id, d.mc_id,
       TO_CHAR(d.attendance_date, 'YYYY-MM-DD') AS attendance_day,
       TO_CHAR(d.regular_in_time, 'YYYY-MM-DD HH24:MI:SS') AS regular_in,
       TO_CHAR(d.regular_out_time, 'YYYY-MM-DD HH24:MI:SS') AS regular_out,
       TO_CHAR(d.in_time, 'YYYY-MM-DD HH24:MI:SS') AS actual_in,
       TO_CHAR(d.out_time, 'YYYY-MM-DD HH24:MI:SS') AS actual_out,
       d.status, d.duty_hours, d.late_in, d.early_out, d.remarks
  FROM HRMS.attendance_details d
 WHERE d.emp_id = TO_NUMBER('&&att_emp_id')
   AND d.attendance_date >= TO_DATE('&&att_day', 'YYYY-MM-DD') - 1
   AND d.attendance_date < TO_DATE('&&att_day', 'YYYY-MM-DD') + 2
 ORDER BY d.attendance_date, d.attendance_id;

PROMPT 3. Unranked source schedules in the rebuild context
SELECT g.emp_id, g.mc_id, g.com_id,
       TO_CHAR(g.attendance_date, 'YYYY-MM-DD') AS schedule_day,
       TO_CHAR(g.regular_in_time, 'YYYY-MM-DD HH24:MI:SS') AS regular_in,
       TO_CHAR(g.regular_out_time, 'YYYY-MM-DD HH24:MI:SS') AS regular_out
  FROM HRMS.v_att_gen g
 WHERE g.emp_id = TO_NUMBER('&&att_emp_id')
   AND g.attendance_date >= TO_DATE('&&att_day', 'YYYY-MM-DD') - 2
   AND g.attendance_date < TO_DATE('&&att_day', 'YYYY-MM-DD') + 3
 ORDER BY g.attendance_date, g.regular_in_time;

PROMPT 4. Deployed objects and procedure parameters
SELECT owner, object_name, object_type, status, last_ddl_time
  FROM all_objects
 WHERE owner = 'HRMS'
   AND object_name IN ('V_ATT_GEN1', 'V_ATT_GEN', 'V_ATT_GEN2', 'P_ATT_SCHEDULE',
                       'P_ATT_CONT_SHIFT_FAST', 'P_ATT_UPDATE_DETAILS', 'P_ATT_REBUILD_MACHINE')
 ORDER BY object_name;

SELECT object_name, argument_name, position, data_type, defaulted
  FROM all_arguments
 WHERE owner = 'HRMS'
   AND package_name IS NULL
   AND object_name IN ('P_ATT_SCHEDULE', 'P_ATT_UPDATE_DETAILS',
                       'P_ATT_CONT_SHIFT_FAST', 'P_ATT_REBUILD_MACHINE')
 ORDER BY object_name, sequence;

SELECT name, type, line, position, text
  FROM all_errors
 WHERE owner = 'HRMS'
   AND name IN ('V_ATT_GEN1', 'V_ATT_GEN', 'V_ATT_GEN2', 'P_ATT_SCHEDULE',
                'P_ATT_CONT_SHIFT_FAST', 'P_ATT_UPDATE_DETAILS', 'P_ATT_REBUILD_MACHINE')
   AND attribute = 'ERROR'
 ORDER BY name, sequence;

PROMPT 5. Machine punch filters and exact boundary ownership
-- The production boundary/assignment CTEs are inserted below. The date context
-- matches rebuilding the single requested day through P_ATT_REBUILD_MACHINE.
WITH source_schedule AS
        (
            /*
               Include neighbouring schedules because a night shift
               starts on one date and ends on the following date.
            */
            SELECT emp_id,
                   mc_key,
                   attendance_date,
                   regular_in_time,
                   regular_out_time
              FROM
              (
                  SELECT g.emp_id,

                         TRIM(TO_CHAR(g.mc_id))
                             AS mc_key,

                         TRUNC(g.attendance_date)
                             AS attendance_date,

                         CAST(g.regular_in_time AS DATE)
                             AS regular_in_time,

                         CAST(g.regular_out_time AS DATE)
                             AS regular_out_time,

                         ROW_NUMBER() OVER
                         (
                             PARTITION BY
                                 g.emp_id,
                                 TRUNC(g.attendance_date)

                             ORDER BY
                                 CASE
                                     WHEN g.regular_in_time IS NULL
                                     THEN 2
                                     ELSE 1
                                 END,
                                 g.regular_in_time
                         ) AS rn

                    FROM HRMS.v_att_gen g

                   WHERE g.emp_id = TO_NUMBER('&&att_emp_id')
                     AND g.attendance_date >= (TO_DATE('&&att_day', 'YYYY-MM-DD') - 1) - 1
                     AND g.attendance_date <  (TO_DATE('&&att_day', 'YYYY-MM-DD') + 2) + 1
              )
             WHERE rn = 1
        ),

        /* Every shift creates one IN boundary and one OUT boundary */
        schedule_boundaries AS
        (
            SELECT s.emp_id,
                   s.mc_key,
                   s.attendance_date,
                   'I' AS boundary_type,
                   1   AS boundary_order,
                   s.regular_in_time AS target_time
              FROM source_schedule s
             WHERE s.regular_in_time IS NOT NULL
               AND s.regular_out_time IS NOT NULL

            UNION ALL

            SELECT s.emp_id,
                   s.mc_key,
                   s.attendance_date,
                   'O' AS boundary_type,
                   2   AS boundary_order,
                   s.regular_out_time AS target_time
              FROM source_schedule s
             WHERE s.regular_in_time IS NOT NULL
               AND s.regular_out_time IS NOT NULL
        ),

        /* Find previous and next scheduled boundaries */
        ordered_boundaries AS
        (
            SELECT b.*,

                   LAG(b.target_time) OVER
                   (
                       PARTITION BY b.mc_key
                       ORDER BY b.target_time,
                                b.boundary_order,
                                b.attendance_date
                   ) AS previous_target,

                   LEAD(b.target_time) OVER
                   (
                       PARTITION BY b.mc_key
                       ORDER BY b.target_time,
                                b.boundary_order,
                                b.attendance_date
                   ) AS next_target

              FROM schedule_boundaries b
        ),

        /*
           Each boundary owns the time between the midpoint of its
           previous boundary and the midpoint of its next boundary.

           Example:

           21-Jul OUT target = 10:00 PM
           22-Jul IN target  = 06:00 AM

           Midpoint = 02:00 AM

           Therefore:
           - Punch before 02:00 AM belongs to 21-Jul OUT
           - Punch after 02:00 AM belongs to 22-Jul IN
        */
        boundary_windows AS
        (
            SELECT o.emp_id,
                   o.mc_key,
                   o.attendance_date,
                   o.boundary_type,
                   o.target_time,

                   CASE
                       WHEN o.previous_target IS NULL
                       THEN o.target_time - (8 / 24)

                       ELSE
                           GREATEST
                           (
                               o.target_time - (8 / 24),

                               o.previous_target
                               +
                               (
                                   o.target_time -
                                   o.previous_target
                               ) / 2
                           )
                   END AS window_start,

                   CASE
                       WHEN o.next_target IS NULL
                       THEN o.target_time + (8 / 24)

                       ELSE
                           LEAST
                           (
                               o.target_time + (8 / 24),

                               o.target_time
                               +
                               (
                                   o.next_target -
                                   o.target_time
                               ) / 2
                           )
                   END AS window_end

              FROM ordered_boundaries o
        ),

        /* Read every raw fingerprint punch separately */
        raw_punches AS
        (
            SELECT DISTINCT
                   TRIM(TO_CHAR(m.userid)) AS mc_key,
                   CAST(m.atttime AS DATE) AS punch_time

              FROM HRMS.att_mcdata m

             WHERE m.atttime >= (TO_DATE('&&att_day', 'YYYY-MM-DD') - 1) - 1
               AND m.atttime <  (TO_DATE('&&att_day', 'YYYY-MM-DD') + 2) + 1

               /* Keep only successful/active punches */
               AND TRIM(TO_CHAR(m.status)) = '1'
        ),

        /*
           Assign each punch to one non-overlapping boundary window.
        */
        punch_candidates AS
        (
            SELECT b.emp_id,
                   b.mc_key,
                   b.attendance_date,
                   b.boundary_type,
                   b.target_time,
                   p.punch_time,

                   ABS
                   (
                       p.punch_time -
                       b.target_time
                   ) AS distance_from_target

              FROM boundary_windows b

                   JOIN raw_punches p
                       ON p.mc_key = b.mc_key

                      AND p.punch_time >= b.window_start
                      AND p.punch_time <  b.window_end
        ),

        /*
           If multiple punches exist near the same IN or OUT boundary,
           choose the punch nearest to the scheduled time.
        */
        boundary_ranked AS
        (
            SELECT c.*,

                   ROW_NUMBER() OVER
                   (
                       PARTITION BY
                           c.emp_id,
                           c.attendance_date,
                           c.boundary_type

                       ORDER BY
                           c.distance_from_target,

                           CASE
                               WHEN c.boundary_type = 'I'
                               THEN c.punch_time
                               ELSE NULL
                           END,

                           CASE
                               WHEN c.boundary_type = 'O'
                               THEN c.punch_time
                               ELSE NULL
                           END DESC
                   ) AS rn

              FROM punch_candidates c
        ),

        selected_boundaries AS
        (
            SELECT emp_id,
                   attendance_date,
                   boundary_type,
                   punch_time
              FROM boundary_ranked
             WHERE rn = 1
        ),

        /* Convert boundary rows into attendance IN and OUT columns */
        assigned_punches AS
        (
            SELECT emp_id,
                   attendance_date,

                   MAX
                   (
                       CASE
                           WHEN boundary_type = 'I'
                           THEN punch_time
                       END
                   ) AS selected_in_time,

                   MAX
                   (
                       CASE
                           WHEN boundary_type = 'O'
                           THEN punch_time
                       END
                   ) AS selected_out_time

              FROM selected_boundaries
             GROUP BY emp_id,
                      attendance_date
        ),

diagnostic_raw AS
        (
            SELECT DISTINCT m.userid, TRIM(TO_CHAR(m.userid)) AS mc_key,
                   m.atttime AS punch_time, m.status, m.device_id, m.flag,
                   e.mc_id AS current_mc_id
              FROM HRMS.att_mcdata m
              JOIN HRMS.employees e ON e.id = TO_NUMBER('&&att_emp_id')
             WHERE m.atttime >= TO_DATE('&&att_day', 'YYYY-MM-DD') - 2
               AND m.atttime < TO_DATE('&&att_day', 'YYYY-MM-DD') + 3
               AND (m.userid = e.mc_id OR EXISTS
                   (SELECT 1 FROM HRMS.attendance_details d
                     WHERE d.emp_id = e.id AND d.mc_id = m.userid
                       AND d.attendance_date >= TO_DATE('&&att_day', 'YYYY-MM-DD') - 1
                       AND d.attendance_date < TO_DATE('&&att_day', 'YYYY-MM-DD') + 2))
        )
        SELECT r.userid, r.device_id, r.flag, r.status AS raw_status,
               TO_CHAR(r.punch_time, 'YYYY-MM-DD HH24:MI:SS') AS raw_punch,
               CASE WHEN r.userid = r.current_mc_id THEN 'CURRENT_EMPLOYEE_MC_ID'
                    ELSE 'STORED_ATTENDANCE_MC_ID_ONLY' END AS mapping,
               CASE WHEN TRIM(TO_CHAR(r.status)) = '1' THEN 'ACCEPTED'
                    ELSE 'EXCLUDED_STATUS' END AS status_gate,
               TO_CHAR(b.attendance_date, 'YYYY-MM-DD') AS assigned_day,
               b.boundary_type,
               TO_CHAR(b.target_time, 'YYYY-MM-DD HH24:MI:SS') AS boundary_target,
               TO_CHAR(b.window_start, 'YYYY-MM-DD HH24:MI:SS') AS window_start,
               TO_CHAR(b.window_end, 'YYYY-MM-DD HH24:MI:SS') AS window_end,
               CASE WHEN b.target_time IS NULL THEN 'NO_MATCHING_WINDOW'
                    WHEN TRIM(TO_CHAR(r.status)) = '1' AND chosen.punch_time IS NOT NULL
                    THEN 'SELECTED' ELSE 'NOT_SELECTED' END AS selection
          FROM diagnostic_raw r
          LEFT JOIN boundary_windows b
            ON b.mc_key = r.mc_key
           AND r.punch_time >= b.window_start
           AND r.punch_time < b.window_end
          LEFT JOIN selected_boundaries chosen
            ON chosen.emp_id = b.emp_id
           AND chosen.attendance_date = b.attendance_date
           AND chosen.boundary_type = b.boundary_type
           AND chosen.punch_time = r.punch_time
         ORDER BY r.punch_time, r.device_id, b.attendance_date, b.boundary_type;

UNDEFINE att_emp_id
UNDEFINE att_day
