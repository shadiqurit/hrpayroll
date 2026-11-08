CREATE OR REPLACE PROCEDURE HRMS.p_att_schedule
(
    p_from_date IN DATE DEFAULT NULL,
    p_to_date   IN DATE DEFAULT NULL,
    p_commit    IN NUMBER DEFAULT 1
)
IS
    /*
       Default processing:
       Yesterday through today.

       p_to_date is inclusive.
    */
    l_from_date DATE := TRUNC(NVL(p_from_date, SYSDATE - 1));
    l_to_date   DATE := TRUNC(NVL(p_to_date, SYSDATE)) + 1;
BEGIN
    IF l_to_date <= l_from_date THEN
        RAISE_APPLICATION_ERROR(-20901, 'Attendance end date must be on or after start date.');
    END IF;
    IF p_commit IS NULL OR p_commit NOT IN (0, 1) THEN
        RAISE_APPLICATION_ERROR(-20902, 'p_commit must be 0 or 1.');
    END IF;
    SAVEPOINT att_schedule_start;
    BEGIN
    /* ============================================================
       1. Generate employee schedule rows
       ============================================================ */
    MERGE INTO HRMS.attendance_details ad
    USING
    (
        SELECT emp_id,
               mc_id,
               attendance_date,
               dayofweek,
               regular_in_time,
               regular_out_time,
               com_id
          FROM
          (
              SELECT g.emp_id,
                     g.mc_id,
                     TRUNC(g.attendance_date) AS attendance_date,
                     g.dayofweek,
                     CAST(g.regular_in_time AS DATE)
                         AS regular_in_time,
                     CAST(g.regular_out_time AS DATE)
                         AS regular_out_time,
                     g.com_id,

                     ROW_NUMBER() OVER
                     (
                         PARTITION BY g.emp_id,
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
               WHERE g.attendance_date >= l_from_date
                 AND g.attendance_date <  l_to_date
          )
         WHERE rn = 1
    ) src
       ON
       (
              ad.emp_id = src.emp_id
          AND TRUNC(ad.attendance_date) = src.attendance_date
       )

    WHEN MATCHED THEN
        UPDATE
           SET ad.mc_id            = src.mc_id,
               ad.dayofweek        = src.dayofweek,
               ad.com_id           = src.com_id,
               ad.regular_in_time  = src.regular_in_time,
               ad.regular_out_time = src.regular_out_time
         WHERE    DECODE(ad.mc_id,
                         src.mc_id, 0, 1) = 1
               OR DECODE(ad.dayofweek,
                         src.dayofweek, 0, 1) = 1
               OR DECODE(ad.com_id,
                         src.com_id, 0, 1) = 1
               OR DECODE(ad.regular_in_time,
                         src.regular_in_time, 0, 1) = 1
               OR DECODE(ad.regular_out_time,
                         src.regular_out_time, 0, 1) = 1

    WHEN NOT MATCHED THEN
        INSERT
        (
            attendance_id,
            emp_id,
            mc_id,
            attendance_date,
            dayofweek,
            regular_in_time,
            regular_out_time,
            com_id
        )
        VALUES
        (
            HRMS.s_attdata.NEXTVAL,
            src.emp_id,
            src.mc_id,
            src.attendance_date,
            src.dayofweek,
            src.regular_in_time,
            src.regular_out_time,
            src.com_id
        );

    /* ============================================================
       2. Assign every raw ATT_MCDATA punch shift-wise

       Do not use V_FPUNCH_LPUNC here because it loses intermediate
       punches when an employee changes shifts.
       ============================================================ */
    MERGE INTO HRMS.attendance_details ad
    USING
    (
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

                   WHERE g.attendance_date >= l_from_date - 1
                     AND g.attendance_date <  l_to_date + 1
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

             WHERE m.atttime >= l_from_date - 1
               AND m.atttime <  l_to_date + 1

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

        /*
           Include every requested schedule row, including holidays.

           LEFT JOIN ensures an old incorrectly assigned punch is
           cleared when rebuilding attendance history.
        */
        rebuild_source AS
        (
            SELECT d.attendance_id,
                   a.selected_in_time,
                   a.selected_out_time

              FROM HRMS.attendance_details d

                   JOIN source_schedule s
                       ON s.emp_id = d.emp_id
                      AND s.attendance_date =
                          TRUNC(d.attendance_date)

                   LEFT JOIN assigned_punches a
                       ON a.emp_id = s.emp_id
                      AND a.attendance_date =
                          s.attendance_date

             WHERE d.attendance_date >= l_from_date
               AND d.attendance_date <  l_to_date
        )

        SELECT attendance_id,
               selected_in_time,
               selected_out_time
          FROM rebuild_source
    ) punch_src
       ON
       (
           ad.attendance_id = punch_src.attendance_id
       )

    WHEN MATCHED THEN
        UPDATE
           SET ad.in_time  = punch_src.selected_in_time,
               ad.out_time = punch_src.selected_out_time

         WHERE    DECODE
                  (
                      ad.in_time,
                      punch_src.selected_in_time,
                      0,
                      1
                  ) = 1

               OR DECODE
                  (
                      ad.out_time,
                      punch_src.selected_out_time,
                      0,
                      1
                  ) = 1;

    IF p_commit = 1 THEN
        COMMIT;
    END IF;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO att_schedule_start;
            RAISE;
    END;
END;
/
