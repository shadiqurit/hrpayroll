CREATE OR REPLACE PROCEDURE HRMS.p_att_update_details
(
    p_from_date IN DATE DEFAULT NULL,
    p_to_date   IN DATE DEFAULT NULL,
    p_commit    IN NUMBER DEFAULT 1
)
IS
    /*
       Default:
       Process yesterday through today.

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
    SAVEPOINT att_update_start;
    BEGIN
/* ================================================================
   1. Bridge missing boundaries BEFORE single-punch normalization

   Example:

   Shift 1:
   20-Jul 10:00 PM to 21-Jul 06:00 AM

   Shift 2:
   21-Jul 06:00 AM to 21-Jul 02:00 PM

   Actual punches:
   20-Jul 09:50 PM
   21-Jul 02:01 PM

   Derived result:
   Shift 1 OUT = 21-Jul 06:00 AM
   Shift 2 IN  = 21-Jul 06:00 AM
   ================================================================ */
MERGE INTO HRMS.attendance_details ad
USING
(
    WITH consecutive_pairs AS
    (
        SELECT previous_shift.attendance_id
                   AS previous_attendance_id,

               next_shift.attendance_id
                   AS next_attendance_id,

               CAST
               (
                   previous_shift.regular_out_time AS DATE
               ) AS shared_boundary_time

          FROM HRMS.attendance_details previous_shift

               JOIN HRMS.attendance_details next_shift
                   ON next_shift.emp_id =
                      previous_shift.emp_id

                  AND next_shift.attendance_id <>
                      previous_shift.attendance_id

                  /*
                     Previous shift OUT and next shift IN must be
                     the same scheduled time.

                     One-minute tolerance is used for differences
                     caused by seconds or datatype conversion.
                  */
                  AND ABS
                      (
                          (
                              CAST
                              (
                                  previous_shift.regular_out_time
                                  AS DATE
                              )
                              -
                              CAST
                              (
                                  next_shift.regular_in_time
                                  AS DATE
                              )
                          ) * 1440
                      ) <= 1

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
              Previous shift:
              actual IN exists but OUT is missing.
           */
           AND previous_shift.in_time IS NOT NULL
           AND previous_shift.out_time IS NULL

           /*
              Next shift:
              actual OUT exists but IN is missing.
           */
           AND next_shift.in_time IS NULL
           AND next_shift.out_time IS NOT NULL

           /*
              Previous actual IN must occur before the shared
              shift boundary.
           */
           AND CAST(previous_shift.in_time AS DATE)
               <=
               CAST(previous_shift.regular_out_time AS DATE)

           /*
              Next actual OUT must occur after the shared
              shift boundary.
           */
           AND CAST(next_shift.out_time AS DATE)
               >=
               CAST(next_shift.regular_in_time AS DATE)

           /*
              Previous actual IN cannot be excessively early.

              Current tolerance: maximum four hours before the
              previous scheduled IN.
           */
           AND CAST(previous_shift.in_time AS DATE)
               >=
               CAST(previous_shift.regular_in_time AS DATE)
               - (4 / 24)

           /*
              Next actual OUT cannot be excessively late.

              Current tolerance: maximum four hours after the
              next scheduled OUT.
           */
           AND CAST(next_shift.out_time AS DATE)
               <=
               CAST(next_shift.regular_out_time AS DATE)
               + (4 / 24)

           AND CAST(next_shift.out_time AS DATE)
               - CAST(previous_shift.in_time AS DATE) <= 1
    ),

    /*
       Generate one update row for each attendance row.

       Previous attendance:
       set derived OUT_TIME.

       Next attendance:
       set derived IN_TIME.
    */
    bridge_rows AS
    (
        SELECT previous_attendance_id
                   AS attendance_id,

               CAST(NULL AS DATE)
                   AS derived_in_time,

               shared_boundary_time
                   AS derived_out_time,

               'Derived OUT at consecutive shift boundary'
                   AS derived_remarks

          FROM consecutive_pairs

        UNION ALL

        SELECT next_attendance_id
                   AS attendance_id,

               shared_boundary_time
                   AS derived_in_time,

               CAST(NULL AS DATE)
                   AS derived_out_time,

               'Derived IN at consecutive shift boundary'
                   AS derived_remarks

          FROM consecutive_pairs
    ),

    /*
       Aggregate to prevent ORA-30926 when an employee has more than
       two consecutive shifts and a middle row requires both a
       derived IN and a derived OUT.
    */
    bridge_updates AS
    (
        SELECT attendance_id,
               MAX(derived_in_time)
                   AS derived_in_time,

               MAX(derived_out_time)
                   AS derived_out_time,

               MAX(derived_remarks)
                   AS derived_remarks

          FROM bridge_rows

      GROUP BY attendance_id
    )

    SELECT attendance_id,
           derived_in_time,
           derived_out_time,
           derived_remarks
      FROM bridge_updates
) src
   ON
   (
       ad.attendance_id = src.attendance_id
   )

WHEN MATCHED THEN
    UPDATE
       SET ad.in_time =
               CASE
                   WHEN src.derived_in_time IS NOT NULL
                   THEN src.derived_in_time
                   ELSE ad.in_time
               END,

           ad.out_time =
               CASE
                   WHEN src.derived_out_time IS NOT NULL
                   THEN src.derived_out_time
                   ELSE ad.out_time
               END,

           /*
              Preserve existing/manual remarks.

              Remove this assignment if you do not want to show
              derived-punch information in the report.
           */
           ad.remarks =
               CASE
                   WHEN ad.remarks IS NULL
                   THEN src.derived_remarks
                   ELSE ad.remarks
               END

     WHERE
              (
                  src.derived_in_time IS NOT NULL
                  AND ad.in_time IS NULL
              )
           OR (
                  src.derived_out_time IS NOT NULL
                  AND ad.out_time IS NULL
              );


    /* 2. Calculate metrics after final punch boundaries are established. */
    MERGE INTO HRMS.attendance_details ad
    USING
    (
        WITH base_data AS
        (
            SELECT d.attendance_id,
                   d.emp_id,
                   d.com_id,
                   d.attendance_date,
                   d.dayofweek,
                   d.in_time  AS original_in_time,
                   d.out_time AS original_out_time,
                   d.regular_in_time,
                   d.regular_out_time,
                   d.remarks,
                   /* =================================================
                      Effective IN_TIME

                      Only OUT punch exists:
                      IN_TIME = OUT_TIME

                      Example:
                      Regular shift = 02:00 PM to 10:00 PM
                      Only punch    = 10:03 PM

                      Effective IN  = 10:03 PM
                      Late          = 483 minutes
                      ================================================= */
                   CASE
                       WHEN d.in_time IS NULL
                        AND d.out_time IS NOT NULL
                       THEN d.out_time

                       ELSE d.in_time
                   END AS new_in_time,

                   /* =================================================
                      Effective OUT_TIME

                      Only IN punch exists:
                      OUT_TIME = IN_TIME

                      Example:
                      Regular shift = 06:00 AM to 02:00 PM
                      Only punch    = 06:05 AM

                      Effective OUT = 06:05 AM
                      Early out     = 475 minutes
                      ================================================= */
                   CASE
                       WHEN d.out_time IS NULL
                        AND d.in_time IS NOT NULL
                       THEN d.in_time

                       /*
                          Safety for invalid historical data.

                          Proper night-shift OUT_TIME contains the next
                          calendar date, so it will be greater than IN.
                       */
                       WHEN d.in_time IS NOT NULL
                        AND d.out_time IS NOT NULL
                        AND d.out_time < d.in_time
                       THEN d.in_time

                       ELSE d.out_time
                   END AS new_out_time,

                   /* Single-punch classification */
                   CASE
                       WHEN d.in_time IS NULL
                        AND d.out_time IS NOT NULL
                       THEN 'IN_MISSING'

                       WHEN d.in_time IS NOT NULL
                        AND d.out_time IS NULL
                       THEN 'OUT_MISSING'

                       WHEN d.in_time IS NOT NULL
                        AND d.out_time IS NOT NULL
                        AND d.out_time < d.in_time
                       THEN 'INVALID_OUT'

                       ELSE 'NORMAL'
                   END AS punch_condition,

                   /* =================================================
                      Government holiday
                      ================================================= */
                   CASE
                       WHEN EXISTS
                       (
                           SELECT 1
                             FROM HRMS.t_holiday th
                            WHERE
                                  (
                                      th.is_recurring = 0
                                      AND TRUNC(th.holiday_date) =
                                          TRUNC(d.attendance_date)
                                  )
                               OR
                                  (
                                      th.is_recurring = 1
                                      AND TO_CHAR
                                          (
                                              th.holiday_date,
                                              'MMDD'
                                          ) =
                                          TO_CHAR
                                          (
                                              d.attendance_date,
                                              'MMDD'
                                          )
                                  )
                       )
                       THEN 1
                       ELSE 0
                   END AS govt_holiday_flag,

                   /* =================================================
                      Company office weekly holiday
                      ================================================= */
                   CASE
                       WHEN EXISTS
                       (
                           SELECT 1
                             FROM HRMS.office_schedule os
                            WHERE os.com_id = d.com_id
                              AND os.location_id =
                                  (SELECT e.branch_id
                                     FROM HRMS.employees e
                                    WHERE e.id = d.emp_id)

                              AND TRUNC(d.attendance_date)
                                  BETWEEN
                                      TRUNC(os.schedule_start_date)
                                  AND
                                      TRUNC(os.schedule_end_date)

                              AND
                                  (
                                      UPPER(TRIM(d.dayofweek)) =
                                          UPPER(TRIM(os.weekend1))

                                      OR

                                      UPPER(TRIM(d.dayofweek)) =
                                          UPPER(TRIM(os.weekend2))
                                  )
                       )
                       THEN 1
                       ELSE 0
                   END AS office_weekend_flag,

                   /* =================================================
                      Shift holiday rank

                      2 = Shifting Holiday
                      1 = Weekly Holiday
                      0 = Office Day
                      ================================================= */
                   NVL
                   (
                       (
                           SELECT MAX
                                  (
                                      CASE
                                          WHEN vg.hflag =
                                               'Shifting Holiday'
                                          THEN 2

                                          WHEN vg.hflag =
                                               'Weekly Holiday'
                                          THEN 1

                                          ELSE 0
                                      END
                                  )
                             FROM HRMS.v_att_gen2 vg
                            WHERE vg.emp_id = d.emp_id

                              AND TRUNC(vg.attendance_date) =
                                  TRUNC(d.attendance_date)

                              AND vg.hflag IN
                                  (
                                      'Weekly Holiday',
                                      'Shifting Holiday'
                                  )
                       ),
                       0
                   ) AS shift_holiday_rank

              FROM HRMS.attendance_details d

             WHERE d.attendance_date >= l_from_date
               AND d.attendance_date <  l_to_date
        ),

        calculated_data AS
        (
            SELECT b.*,

                   /* =================================================
                      Duty minutes

                      A single punch produces:

                      NEW_IN_TIME  = same punch
                      NEW_OUT_TIME = same punch
                      DUTY         = zero
                      ================================================= */
                   CASE
                       WHEN b.new_in_time IS NOT NULL
                        AND b.new_out_time IS NOT NULL
                       THEN
                           GREATEST
                           (
                               ROUND
                               (
                                   (
                                       CAST(b.new_out_time AS DATE)
                                       -
                                       CAST(b.new_in_time AS DATE)
                                   ) * 1440
                               ),
                               0
                           )

                       ELSE NULL
                   END AS duty_minutes,

                   /* =================================================
                      Late-in calculation with 10-minute grace

                      This calculation uses NEW_IN_TIME.

                      Therefore, when only OUT punch exists, that punch
                      becomes IN_TIME and is calculated as late-in.
                      ================================================= */
                   CASE
                       WHEN b.new_in_time IS NOT NULL
                        AND b.regular_in_time IS NOT NULL

                        AND ROUND
                            (
                                (
                                    CAST(b.new_in_time AS DATE)
                                    -
                                    CAST(b.regular_in_time AS DATE)
                                ) * 1440
                            ) > 10
                       THEN
                           ROUND
                           (
                               (
                                   CAST(b.new_in_time AS DATE)
                                   -
                                   CAST(b.regular_in_time AS DATE)
                               ) * 1440
                           )

                       ELSE 0
                   END AS new_late_in,

                   /* =================================================
                      Early-out calculation

                      This calculation uses NEW_OUT_TIME.

                      Therefore, when only IN punch exists, that punch
                      becomes OUT_TIME and is calculated as early-out.
                      ================================================= */
                   CASE
                       WHEN b.new_out_time IS NOT NULL
                        AND b.regular_out_time IS NOT NULL
                       THEN
                           GREATEST
                           (
                               ROUND
                               (
                                   (
                                       CAST(b.regular_out_time AS DATE)
                                       -
                                       CAST(b.new_out_time AS DATE)
                                   ) * 1440
                               ),
                               0
                           )

                       ELSE 0
                   END AS new_early_out

              FROM base_data b
        ),

        final_data AS
        (
            SELECT c.attendance_id,
                   c.new_in_time,
                   c.new_out_time,
                   c.punch_condition,

                   /* Duty hours in H:MI format */
                   CASE
                       WHEN c.duty_minutes IS NOT NULL
                       THEN
                              TRUNC(c.duty_minutes / 60)
                           || ':'
                           || LPAD
                              (
                                  MOD(c.duty_minutes, 60),
                                  2,
                                  '0'
                              )

                       ELSE NULL
                   END AS new_duty_hours,

                   c.new_late_in,
                   c.new_early_out,

                   /* =============================================
                      Attendance status priority
                      ============================================= */
                   CASE
                       WHEN c.shift_holiday_rank = 2
                       THEN 'H'

                       WHEN c.shift_holiday_rank = 1
                       THEN 'W'

                       WHEN c.office_weekend_flag = 1
                       THEN 'W'

                       WHEN c.govt_holiday_flag = 1
                       THEN 'G'

                       WHEN c.new_in_time IS NOT NULL
                       THEN 'P'

                       ELSE 'A'
                   END AS new_status,

                   /* =============================================
                      Remarks

                      Existing manual remarks are preserved.
                      ============================================= */
                   CASE
                       WHEN c.shift_holiday_rank = 2
                       THEN 'Shifting Holiday'

                       WHEN c.shift_holiday_rank = 1
                       THEN 'Weekly Holiday'

                       WHEN c.office_weekend_flag = 1
                       THEN 'Weekly Holiday'

                       WHEN c.govt_holiday_flag = 1
                       THEN 'Govt. Holiday'

                       WHEN c.new_in_time IS NULL
                       THEN 'Absent'

                       /*
                          Existing generated remarks are cleared when
                          the employee becomes present.
                       */
                       WHEN c.remarks IN
                            (
                                'Absent',
                                'Govt. Holiday',
                                'Weekly Holiday',
                                'Shifting Holiday',
                                'Single Punch',
                                'IN Punch Missing',
                                'OUT Punch Missing'
                            )
                       THEN NULL

                       ELSE c.remarks
                   END AS new_remarks

              FROM calculated_data c
        )

        SELECT f.attendance_id,
               f.new_in_time,
               f.new_out_time,
               f.new_duty_hours,
               f.new_late_in,
               f.new_early_out,
               f.new_status,
               f.new_remarks
          FROM final_data f
    ) src
       ON
       (
           ad.attendance_id = src.attendance_id
       )

    WHEN MATCHED THEN
        UPDATE
           SET ad.in_time    = src.new_in_time,
               ad.out_time   = src.new_out_time,
               ad.duty_hours = src.new_duty_hours,
               ad.late_in    = src.new_late_in,
               ad.early_out  = src.new_early_out,
               ad.status     = src.new_status,
               ad.remarks    = src.new_remarks

         WHERE
                  DECODE
                  (
                      ad.in_time,
                      src.new_in_time,
                      0,
                      1
                  ) = 1

               OR DECODE
                  (
                      ad.out_time,
                      src.new_out_time,
                      0,
                      1
                  ) = 1

               OR DECODE
                  (
                      ad.duty_hours,
                      src.new_duty_hours,
                      0,
                      1
                  ) = 1

               OR DECODE
                  (
                      ad.late_in,
                      src.new_late_in,
                      0,
                      1
                  ) = 1

               OR DECODE
                  (
                      ad.early_out,
                      src.new_early_out,
                      0,
                      1
                  ) = 1

               OR DECODE
                  (
                      ad.status,
                      src.new_status,
                      0,
                      1
                  ) = 1

               OR DECODE
                  (
                      ad.remarks,
                      src.new_remarks,
                      0,
                      1
                  ) = 1;


    IF p_commit = 1 THEN
        COMMIT;
    END IF;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO att_update_start;
            RAISE;
    END;
END;
/
