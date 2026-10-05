CREATE OR REPLACE PACKAGE HRMS.pkg_el_history AUTHID DEFINER AS
    PROCEDURE stage_reference;
    PROCEDURE reconcile (
        p_as_of_date IN DATE DEFAULT SYSDATE,
        p_empid      IN NUMBER DEFAULT NULL,
        p_refresh_reference IN NUMBER DEFAULT 1
    );
END pkg_el_history;
/

CREATE OR REPLACE PACKAGE BODY HRMS.pkg_el_history AS
    PROCEDURE stage_reference IS
    BEGIN
        SAVEPOINT el_reference_start;
        LOCK TABLE HRMS.hr_el_legacy_ref IN EXCLUSIVE MODE;
        UPDATE HRMS.hr_el_legacy_ref SET active_flag = 'N';

        -- Read the eight supplied legacy fields only. Keys live in our copy;
        -- repeated identical rows retain distinct occurrence numbers.
        MERGE INTO HRMS.hr_el_legacy_ref t
        USING (
            WITH fingerprints AS (
                SELECT ld.empcode, ld.leave_type, ld.date_from, ld.date_to,
                       ld.duration, ld.year AS legacy_year, ld.leaveadtype,
                       ld.empid AS legacy_empid,
                       HRMS.fn_el_source_key(ld.empcode, ld.leave_type,
                           ld.date_from, ld.date_to, ld.duration, ld.year,
                           ld.leaveadtype, ld.empid) AS source_key
                  FROM HRMS.leave_data ld
                 WHERE UPPER(TRIM(ld.leave_type)) = 'EL'
            )
            SELECT f.*, ROW_NUMBER() OVER (
                PARTITION BY source_key ORDER BY source_key
            ) AS occurrence_no FROM fingerprints f
        ) s ON (t.source_key = s.source_key AND t.occurrence_no = s.occurrence_no)
        WHEN MATCHED THEN UPDATE SET t.active_flag = 'Y', t.copied_at = SYSDATE
        WHEN NOT MATCHED THEN INSERT
            (source_key, occurrence_no, empcode, leave_type, date_from, date_to,
             duration, legacy_year, leaveadtype, legacy_empid, active_flag)
        VALUES (s.source_key, s.occurrence_no, s.empcode, s.leave_type,
            s.date_from, s.date_to, s.duration, s.legacy_year, s.leaveadtype,
            s.legacy_empid, 'Y');
    EXCEPTION WHEN OTHERS THEN
        ROLLBACK TO el_reference_start;
        RAISE;
    END stage_reference;

    PROCEDURE reconcile (
        p_as_of_date IN DATE DEFAULT SYSDATE,
        p_empid      IN NUMBER DEFAULT NULL,
        p_refresh_reference IN NUMBER DEFAULT 1
    ) IS
        v_count NUMBER;
        v_lt_id NUMBER;
        v_cutoff DATE;
        v_end DATE;
        v_year_start DATE;
        v_earned NUMBER;
        v_earned_before NUMBER;
        v_last_earned NUMBER;
        v_native_before NUMBER;
        v_last_native NUMBER;
        v_native_total NUMBER;
        v_balance NUMBER;
        v_adjustment NUMBER;
        v_type NUMBER;
    BEGIN
        SAVEPOINT el_history_start;
        IF p_as_of_date IS NULL OR EXTRACT(YEAR FROM p_as_of_date) > 9998 THEN
            RAISE_APPLICATION_ERROR(-20071, 'A valid reconciliation date is required.');
        END IF;
        IF p_refresh_reference IS NULL OR p_refresh_reference NOT IN (0, 1) THEN
            RAISE_APPLICATION_ERROR(-20087, 'p_refresh_reference must be 0 or 1.');
        END IF;
        -- Serialize imports and snapshot edits with ordinary allocation and
        -- consumption writes. All locks are held only until caller commit.
        LOCK TABLE HRMS.hr_el_legacy_ref IN EXCLUSIVE MODE;
        LOCK TABLE HRMS.hr_el_legacy_event IN EXCLUSIVE MODE;
        LOCK TABLE HRMS.leave_allocation IN EXCLUSIVE MODE;
        LOCK TABLE HRMS.leave_consumption IN SHARE MODE;
        IF p_refresh_reference = 1 THEN
            stage_reference;
        END IF;

        SELECT COUNT(*) INTO v_count FROM HRMS.v_el_legacy_source
         WHERE (p_empid IS NULL OR empid = p_empid OR match_count <> 1)
           AND (match_count <> 1 OR event_kind IS NULL
             OR event_kind NOT IN ('OPENING', 'LEAVE', 'ENCASHMENT')
             OR event_date IS NULL OR end_date IS NULL OR end_date < event_date
             OR source_days IS NULL OR (source_days < 0 AND event_kind <> 'OPENING')
             OR event_year IS NULL OR event_year <> TRUNC(event_year)
             OR event_year <> EXTRACT(YEAR FROM event_date));
        IF v_count > 0 THEN
            RAISE_APPLICATION_ERROR(-20072,
                'Invalid or ambiguous EL source rows. Run DIAGNOSE_EL_HISTORY.sql.');
        END IF;

        SELECT COUNT(*) INTO v_count FROM (
            SELECT empid, event_date FROM HRMS.v_el_legacy_source
             WHERE event_kind = 'OPENING'
               AND (p_empid IS NULL OR empid = p_empid)
             GROUP BY empid, event_date HAVING COUNT(*) > 1
        );
        IF v_count > 0 THEN
            RAISE_APPLICATION_ERROR(-20073, 'Multiple Opening snapshots exist for an employee on the same day.');
        END IF;

        SELECT COUNT(*) INTO v_count FROM HRMS.employees e
          LEFT JOIN HRMS.t_emp_typ et ON TRIM(e.emp_type) = TO_CHAR(et.id)
         WHERE (p_empid IS NULL OR e.id = p_empid)
           AND (e.join_date IS NULL OR et.id IS NULL
                OR (NVL(e.status, 0) <> 1 AND e.sep_date IS NULL)
                OR (e.sep_date IS NOT NULL AND TRUNC(e.sep_date) < TRUNC(e.join_date)));
        IF v_count > 0 THEN
            RAISE_APPLICATION_ERROR(-20074, 'Employees need JOIN_DATE, a valid type, and SEP_DATE when inactive.');
        END IF;
        IF p_empid IS NOT NULL THEN
            SELECT COUNT(*) INTO v_count FROM HRMS.employees WHERE id = p_empid;
            IF v_count = 0 THEN
                RAISE_APPLICATION_ERROR(-20075, 'Employee primary-key ID was not found.');
            END IF;
        END IF;

        SELECT COUNT(*) INTO v_count
          FROM HRMS.v_el_legacy_source s JOIN HRMS.employees e ON e.id = s.empid
         WHERE (p_empid IS NULL OR e.id = p_empid)
           AND (s.event_date < TRUNC(e.join_date)
                OR (e.sep_date IS NOT NULL AND s.event_date > TRUNC(e.sep_date)));
        IF v_count > 0 THEN
            RAISE_APPLICATION_ERROR(-20076, 'Legacy EL dates fall outside recorded employment dates; review JOIN_DATE/SEP_DATE.');
        END IF;

        IF p_empid IS NOT NULL THEN
            SELECT COUNT(*) INTO v_count
              FROM HRMS.hr_el_legacy_event l JOIN HRMS.v_el_legacy_source s ON s.source_id = l.source_id
             WHERE l.empid <> s.empid AND p_empid IN (l.empid, s.empid);
            IF v_count > 0 THEN
                RAISE_APPLICATION_ERROR(-20083, 'ERP employee mapping changed; reconcile all employees to refresh both balances.');
            END IF;
        END IF;
        SELECT COUNT(*) INTO v_count FROM HRMS.employees e
         WHERE (p_empid IS NULL OR e.id = p_empid) AND TRUNC(e.join_date) <= TRUNC(p_as_of_date)
           AND (SELECT COUNT(*) FROM HRMS.leave_types lt
                 WHERE UPPER(TRIM(lt.short_code)) = 'EL' AND lt.active_flag = 'Y'
                   AND (lt.com_id = e.com_id OR (lt.com_id IS NULL AND NOT EXISTS (
                        SELECT 1 FROM HRMS.leave_types local_lt
                         WHERE UPPER(TRIM(local_lt.short_code)) = 'EL'
                           AND local_lt.active_flag = 'Y' AND local_lt.com_id = e.com_id
                   )))) <> 1;
        IF v_count > 0 THEN
            RAISE_APPLICATION_ERROR(-20077, 'Each employee needs exactly one effective active EL leave type.');
        END IF;

        -- Refresh only this import's ledger. Removed/out-of-cutoff source rows
        -- are retained as inactive for audit, never as additional debits.
        UPDATE HRMS.hr_el_legacy_event SET active_flag = 'N', adjustment_days = 0
         WHERE p_empid IS NULL OR empid = p_empid;

        -- Normalize and map the source once. Subsequent year/event reads use
        -- the indexed ledger rather than repeatedly scanning LEAVE_DATA.
        MERGE INTO HRMS.hr_el_legacy_event t
        USING (
            SELECT s.*, lt.lt_id
              FROM HRMS.v_el_legacy_source s
              JOIN HRMS.employees e ON e.id = s.empid
              JOIN HRMS.leave_types lt ON UPPER(TRIM(lt.short_code)) = 'EL'
               AND lt.active_flag = 'Y'
               AND (lt.com_id = e.com_id OR (lt.com_id IS NULL AND NOT EXISTS (
                    SELECT 1 FROM HRMS.leave_types local_lt
                     WHERE UPPER(TRIM(local_lt.short_code)) = 'EL'
                       AND local_lt.active_flag = 'Y' AND local_lt.com_id = e.com_id
               )))
             WHERE (p_empid IS NULL OR e.id = p_empid)
               AND s.event_date <= LEAST(TRUNC(p_as_of_date), NVL(TRUNC(e.sep_date), TRUNC(p_as_of_date)))
        ) s ON (t.source_id = s.source_id)
        WHEN MATCHED THEN UPDATE SET t.empid = s.empid, t.leave_type_id = s.lt_id,
            t.event_year = s.event_year, t.event_date = s.event_date, t.end_date = s.end_date,
            t.event_kind = s.event_kind, t.source_days = s.source_days,
            t.adjustment_days = 0, t.active_flag = 'Y', t.imported_at = SYSDATE
        WHEN NOT MATCHED THEN INSERT
            (source_id, empid, leave_type_id, event_year, event_date, end_date,
             event_kind, source_days, adjustment_days, active_flag)
        VALUES (s.source_id, s.empid, s.lt_id, s.event_year, s.event_date, s.end_date,
            s.event_kind, s.source_days, 0, 'Y');

        FOR e IN (
            SELECT id, emp_id, com_id, join_date, sep_date, dob, emp_type, conf_date
              FROM HRMS.employees
             WHERE (p_empid IS NULL OR id = p_empid)
               AND TRUNC(join_date) <= TRUNC(p_as_of_date)
             ORDER BY id
        ) LOOP
            v_cutoff := LEAST(TRUNC(p_as_of_date), NVL(TRUNC(e.sep_date), TRUNC(p_as_of_date)));
            SELECT COUNT(*), MIN(lt.lt_id) INTO v_count, v_lt_id
              FROM HRMS.leave_types lt
             WHERE UPPER(TRIM(lt.short_code)) = 'EL' AND lt.active_flag = 'Y'
               AND (lt.com_id = e.com_id OR (lt.com_id IS NULL AND NOT EXISTS (
                    SELECT 1 FROM HRMS.leave_types local_lt
                     WHERE UPPER(TRIM(local_lt.short_code)) = 'EL'
                       AND local_lt.active_flag = 'Y' AND local_lt.com_id = e.com_id
               )));
            IF v_count <> 1 THEN
                RAISE_APPLICATION_ERROR(-20077, 'Employee ' || e.id || ' needs exactly one effective active EL leave type.');
            END IF;
            SELECT id INTO v_type FROM HRMS.t_emp_typ WHERE TO_CHAR(id) = TRIM(e.emp_type);

            SELECT COUNT(*) INTO v_count
              FROM HRMS.leave_allocation la JOIN HRMS.leave_types lt ON lt.lt_id = la.leave_type_id
             WHERE la.empid = e.id AND UPPER(TRIM(lt.short_code)) = 'EL'
               AND la.allocated_days <> 0
               AND (la.allocation_year IS NULL
                    OR la.allocation_year < EXTRACT(YEAR FROM e.join_date)
                    OR la.allocated_date IS NULL OR TRUNC(la.allocated_date) > v_cutoff
                    OR la.allocation_year > EXTRACT(YEAR FROM v_cutoff));
            IF v_count > 0 THEN
                RAISE_APPLICATION_ERROR(-20080, 'Employee ' || e.id || ' has EL allocations beyond this cutoff; reconcile forward in time.');
            END IF;

            SELECT COUNT(*) INTO v_count
              FROM HRMS.leave_allocation la JOIN HRMS.leave_types lt ON lt.lt_id = la.leave_type_id
             WHERE la.empid = e.id AND UPPER(TRIM(lt.short_code)) = 'EL'
               AND la.leave_type_id <> v_lt_id;
            IF v_count > 0 THEN
                RAISE_APPLICATION_ERROR(-20078, 'Employee ' || e.id || ' has allocations under another EL type ID. Review before importing.');
            END IF;
            SELECT COUNT(*) INTO v_count
              FROM HRMS.leave_consumption lc JOIN HRMS.leave_types lt ON lt.lt_id = lc.leave_type_id
             WHERE lc.empid = e.id AND UPPER(TRIM(lt.short_code)) IN ('EL', 'EC')
               AND (lc.consum_year IS NULL OR lc.consum_year <> TRUNC(lc.consum_year)
                 OR lc.consumed_days < 0
                 OR NVL(lc.start_date, lc.consumption_date) IS NULL
                 OR lc.consum_year <> EXTRACT(YEAR FROM NVL(lc.start_date, lc.consumption_date))
                 OR TRUNC(NVL(lc.start_date, lc.consumption_date)) < TRUNC(e.join_date)
                 OR (e.sep_date IS NOT NULL AND
                     TRUNC(NVL(lc.start_date, lc.consumption_date)) > TRUNC(e.sep_date)));
            IF v_count > 0 THEN
                RAISE_APPLICATION_ERROR(-20079, 'Employee ' || e.id || ' has invalid native EL consumption dates/year.');
            END IF;

            SELECT COUNT(*) INTO v_count
              FROM HRMS.leave_consumption lc
              JOIN HRMS.leave_types lt ON lt.lt_id = lc.leave_type_id
              JOIN HRMS.hr_el_legacy_event s ON s.empid = lc.empid AND s.active_flag = 'Y'
               AND s.event_year = lc.consum_year AND s.event_kind IN ('LEAVE', 'ENCASHMENT')
               AND s.event_date = TRUNC(NVL(lc.start_date, lc.consumption_date))
               AND s.end_date = TRUNC(lc.end_date) AND s.source_days = lc.consumed_days
             WHERE lc.empid = e.id AND UPPER(TRIM(lt.short_code)) IN ('EL', 'EC');
            IF v_count > 0 THEN
                RAISE_APPLICATION_ERROR(-20081, 'Employee ' || e.id || ' has matching native/ERP consumption; resolve overlap before importing.');
            END IF;

            v_balance := 0;
            FOR y IN EXTRACT(YEAR FROM e.join_date) .. EXTRACT(YEAR FROM v_cutoff) LOOP
                v_year_start := TO_DATE(TO_CHAR(y, 'FM0000') || '0101', 'YYYYMMDD');
                v_end := LEAST(v_cutoff, ADD_MONTHS(v_year_start, 12) - 1);
                v_earned := HRMS.fn_el_entitlement(y, v_end, e.join_date, e.dob, v_type, e.conf_date);

                MERGE INTO HRMS.leave_allocation la
                USING (SELECT e.id empid, v_lt_id lt_id, y alloc_year FROM dual) s
                   ON (la.empid = s.empid AND la.leave_type_id = s.lt_id
                       AND la.allocation_year = s.alloc_year)
                WHEN MATCHED THEN UPDATE SET la.allocated_days = v_earned,
                    la.allocated_date = v_end, la.com_id = e.com_id, la.upd_date = SYSDATE
                WHEN NOT MATCHED THEN INSERT
                    (empid, leave_type_id, allocated_days, allocation_year, allocated_date, com_id)
                VALUES (s.empid, s.lt_id, v_earned, s.alloc_year, v_end, e.com_id);

                v_last_earned := 0;
                v_last_native := 0;
                FOR r IN (
                    SELECT * FROM HRMS.hr_el_legacy_event
                     WHERE empid = e.id AND event_year = y AND event_date <= v_end
                       AND active_flag = 'Y'
                     ORDER BY event_date, CASE event_kind WHEN 'OPENING' THEN 0 ELSE 1 END, source_id
                ) LOOP
                    -- Opening is the balance at START of DATE_FROM, before
                    -- that day's earned EL, leave taken, or encashment.
                    v_earned_before := HRMS.fn_el_entitlement(
                        y, r.event_date - 1, e.join_date, e.dob, v_type, e.conf_date);
                    SELECT NVL(SUM(lc.consumed_days), 0) INTO v_native_before
                      FROM HRMS.leave_consumption lc
                      JOIN HRMS.leave_types lt ON lt.lt_id = lc.leave_type_id
                     WHERE lc.empid = e.id AND lc.consum_year = y
                       AND UPPER(TRIM(lt.short_code)) IN ('EL', 'EC')
                       AND TRUNC(NVL(lc.start_date, lc.consumption_date)) < r.event_date;
                    v_balance := v_balance + v_earned_before - v_last_earned
                        - (v_native_before - v_last_native);
                    v_last_earned := v_earned_before;
                    v_last_native := v_native_before;

                    v_adjustment := 0;
                    IF r.event_kind = 'OPENING' THEN
                        v_adjustment := r.source_days - v_balance;
                        v_balance := r.source_days;
                    ELSE
                        v_balance := v_balance - r.source_days;
                    END IF;
                    UPDATE HRMS.hr_el_legacy_event
                       SET adjustment_days = v_adjustment, imported_at = SYSDATE
                     WHERE source_id = r.source_id;
                END LOOP;

                SELECT NVL(SUM(lc.consumed_days), 0) INTO v_native_total
                  FROM HRMS.leave_consumption lc
                  JOIN HRMS.leave_types lt ON lt.lt_id = lc.leave_type_id
                 WHERE lc.empid = e.id AND lc.consum_year = y
                   AND UPPER(TRIM(lt.short_code)) IN ('EL', 'EC')
                   AND TRUNC(NVL(lc.start_date, lc.consumption_date)) <= v_end;
                v_balance := v_balance + v_earned - v_last_earned
                    - (v_native_total - v_last_native);
            END LOOP;
        END LOOP;
        -- All business changes stay in the caller's transaction.
    EXCEPTION WHEN OTHERS THEN
        ROLLBACK TO el_history_start;
        RAISE;
    END reconcile;
END pkg_el_history;
/
