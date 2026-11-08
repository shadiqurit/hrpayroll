-- Machine-only entry point. Does not apply leave, short leave or manual overrides.
-- Dates are mandatory and inclusive. Processes neighbouring dates as well.
CREATE OR REPLACE PROCEDURE HRMS.p_att_rebuild_machine
(
    p_from_date IN DATE,
    p_to_date   IN DATE,
    p_commit    IN NUMBER DEFAULT 1
)
IS
    l_from_date DATE;
    l_to_date   DATE;
BEGIN
    IF p_from_date IS NULL OR p_to_date IS NULL
       OR TRUNC(p_to_date) < TRUNC(p_from_date) THEN
        RAISE_APPLICATION_ERROR(-20901, 'Supply a valid attendance date range.');
    END IF;
    IF p_commit IS NULL OR p_commit NOT IN (0, 1) THEN
        RAISE_APPLICATION_ERROR(-20902, 'p_commit must be 0 or 1.');
    END IF;

    -- Include both sides of overnight/continuous pairs at the requested edges.
    l_from_date := TRUNC(p_from_date) - 1;
    l_to_date := TRUNC(p_to_date) + 1;

    SAVEPOINT att_rebuild_machine_start;
    BEGIN
        HRMS.p_att_schedule(l_from_date, l_to_date, p_commit => 0);
        HRMS.p_att_cont_shift_fast(l_from_date, l_to_date, p_commit => 0);
        HRMS.p_att_update_details(l_from_date, l_to_date, p_commit => 0);

        IF p_commit = 1 THEN
            COMMIT;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO att_rebuild_machine_start;
            RAISE;
    END;
END;
/
