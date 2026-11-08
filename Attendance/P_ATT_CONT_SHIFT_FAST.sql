CREATE OR REPLACE PROCEDURE HRMS.p_att_cont_shift_fast
(
    p_from_date IN DATE DEFAULT NULL,
    p_to_date   IN DATE DEFAULT NULL,
    p_emp_id    IN NUMBER DEFAULT NULL,
    p_commit    IN NUMBER DEFAULT 1
)
IS
    /*
       Default:
       Yesterday through today.

       p_to_date is inclusive.

       This procedure does not read ATT_MCDATA.
       It processes only continuous shift pairs already generated
       in ATTENDANCE_DETAILS.
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
    SAVEPOINT att_cont_shift_start;
    BEGIN
    /* ============================================================
       Continuous shift rule

       Previous shift REGULAR_OUT_TIME and next shift
       REGULAR_IN_TIME must represent the same boundary.

       Middle punch is ignored whether it is:

       - Missing
       - Exactly at boundary
       - Early or late, such as 06:32 AM

       Outer punches prove that the employee worked across both
       continuous shifts.
       ============================================================ */
    MERGE INTO HRMS.attendance_details ad
    USING
    (
        WITH continuous_pairs AS
        (
            SELECT previous_shift.attendance_id
                       AS previous_attendance_id,

                   next_shift.attendance_id
                       AS next_attendance_id,

                   previous_shift.emp_id,

                   CAST
                   (
                       previous_shift.regular_in_time AS DATE
                   ) AS previous_regular_in,

                   CAST
                   (
                       previous_shift.regular_out_time AS DATE
                   ) AS shared_boundary_time,

                   CAST
                   (
                       next_shift.regular_in_time AS DATE
                   ) AS next_regular_in,

                   CAST
                   (
                       next_shift.regular_out_time AS DATE
                   ) AS next_regular_out,

                   CAST
                   (
                       previous_shift.in_time AS DATE
                   ) AS first_outer_punch,

                   CAST
                   (
                       next_shift.out_time AS DATE
                   ) AS last_outer_punch

              FROM HRMS.attendance_details previous_shift

                   JOIN HRMS.attendance_details next_shift
                     ON next_shift.emp_id =
                        previous_shift.emp_id

                    /*
                       The next attendance row belongs to the date
                       on which the previous night shift ends.
                    */
                    AND next_shift.attendance_date =
                        TRUNC
                        (
                            CAST
                            (
                                previous_shift.regular_out_time
                                AS DATE
                            )
                        )

                    AND next_shift.attendance_id <>
                        previous_shift.attendance_id

                    /*
                       Both shifts must have the same scheduled
                       continuous boundary.

                       One-minute tolerance handles seconds.
                    */
                    AND CAST
                        (
                            next_shift.regular_in_time AS DATE
                        )
                        >=
                        CAST
                        (
                            previous_shift.regular_out_time AS DATE
                        ) - (1 / 1440)

                    AND CAST
                        (
                            next_shift.regular_in_time AS DATE
                        )
                        <=
                        CAST
                        (
                            previous_shift.regular_out_time AS DATE
                        ) + (1 / 1440)

             WHERE previous_shift.attendance_date >= l_from_date
               AND previous_shift.attendance_date <  l_to_date

               AND next_shift.attendance_date >= l_from_date
               AND next_shift.attendance_date <  l_to_date

               /* Both must be working shifts */
               AND previous_shift.regular_in_time IS NOT NULL
               AND previous_shift.regular_out_time IS NOT NULL

               AND next_shift.regular_in_time IS NOT NULL
               AND next_shift.regular_out_time IS NOT NULL

               /*
                  The first outer punch must exist.

                  Example:
                  20-Jul 09:50 PM
               */
               AND previous_shift.in_time IS NOT NULL

               /*
                  The last outer punch must exist.

                  Example:
                  21-Jul 02:01 PM
               */
               AND next_shift.out_time IS NOT NULL

               AND
                   (
                       p_emp_id IS NULL
                       OR previous_shift.emp_id = p_emp_id
                   )
        ),

        valid_pairs AS
        (
            SELECT p.previous_attendance_id,
                   p.next_attendance_id,
                   p.shared_boundary_time

              FROM continuous_pairs p

             WHERE
                   /*
                      First outer punch must be before the shared
                      shift boundary.
                   */
                   p.first_outer_punch <
                   p.shared_boundary_time

                   /*
                      Last outer punch must be after the shared
                      shift boundary.
                   */
               AND p.last_outer_punch >
                   p.shared_boundary_time

                   /*
                      First punch tolerance:
                      Maximum four hours before first scheduled IN.
                   */
               AND p.first_outer_punch >=
                   p.previous_regular_in - (4 / 24)

                   /*
                      Do not use a punch after the first shift's
                      scheduled boundary as its outer IN.
                   */
               AND p.first_outer_punch <=
                   p.shared_boundary_time

                   /*
                      Last punch tolerance:
                      Maximum four hours after second scheduled OUT.
                   */
               AND p.last_outer_punch <=
                   p.next_regular_out + (4 / 24)

                   /*
                      The final outer punch must occur after the
                      start of the second shift.
                   */
               AND p.last_outer_punch >=
                   p.next_regular_in

                   /*
                      Prevent unrelated punches from being joined.

                      Maximum continuous attendance span: 24 hours.
                   */
               AND
                   (
                       p.last_outer_punch -
                       p.first_outer_punch
                   ) <= 1
        ),

        boundary_rows AS
        (
            /*
               First/night shift:

               Always force OUT_TIME to the scheduled shared
               boundary, even when an actual middle punch such as
               06:32 AM already exists.
            */
            SELECT v.previous_attendance_id
                       AS attendance_id,

                   CAST(NULL AS DATE)
                       AS new_in_time,

                   v.shared_boundary_time
                       AS new_out_time

              FROM valid_pairs v

            UNION ALL

            /*
               Second/day shift:

               Always force IN_TIME to the scheduled shared
               boundary, even when an actual middle punch such as
               06:32 AM already exists.
            */
            SELECT v.next_attendance_id
                       AS attendance_id,

                   v.shared_boundary_time
                       AS new_in_time,

                   CAST(NULL AS DATE)
                       AS new_out_time

              FROM valid_pairs v
        ),

        boundary_updates AS
        (
            /*
               Supports three or more continuous shifts.

               A middle attendance row may need:

               - derived IN from the previous pair
               - derived OUT for the next pair
            */
            SELECT attendance_id,
                   MAX(new_in_time)  AS new_in_time,
                   MAX(new_out_time) AS new_out_time

              FROM boundary_rows

          GROUP BY attendance_id
        )

        SELECT attendance_id,
               new_in_time,
               new_out_time

          FROM boundary_updates
    ) src
       ON
       (
           ad.attendance_id = src.attendance_id
       )

    WHEN MATCHED THEN
        UPDATE
           SET ad.in_time =
                   CASE
                       WHEN src.new_in_time IS NOT NULL
                       THEN src.new_in_time
                       ELSE ad.in_time
                   END,

               ad.out_time =
                   CASE
                       WHEN src.new_out_time IS NOT NULL
                       THEN src.new_out_time
                       ELSE ad.out_time
                   END

         /*
            Reduce redo/archive generation:

            Update only when the current boundary value is different.
         */
         WHERE
                  (
                      src.new_in_time IS NOT NULL

                      AND DECODE
                          (
                              ad.in_time,
                              src.new_in_time,
                              0,
                              1
                          ) = 1
                  )

               OR
                  (
                      src.new_out_time IS NOT NULL

                      AND DECODE
                          (
                              ad.out_time,
                              src.new_out_time,
                              0,
                              1
                          ) = 1
                  );

    IF p_commit = 1 THEN
        COMMIT;
    END IF;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO att_cont_shift_start;
            RAISE;
    END;
END;
/
