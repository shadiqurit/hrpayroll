-- SQL*Plus / SQLcl: run this file as a script in the HRMS schema.
-- For an existing database only. Oracle DDL commits the current transaction.
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

ALTER TABLE HRMS.leave_request ADD (
    request_status VARCHAR2(1 BYTE) DEFAULT 'D' NOT NULL
);

-- Preserve the stage of existing requests rather than making all rows drafts.
UPDATE HRMS.leave_request
   SET request_status = CASE UPPER(TRIM(leave_status))
                            WHEN 'P' THEN 'D'
                            WHEN 'D' THEN 'D'
                            WHEN 'A' THEN 'A'
                            ELSE 'F'
                        END;

ALTER TABLE HRMS.leave_request ADD (
    CONSTRAINT ck_leave_request_status
    CHECK (request_status IN ('D', 'F', 'A'))
);

COMMENT ON COLUMN HRMS.leave_request.request_status
  IS 'D = Draft, F = Forwarded, A = Final';

@@TRG_LEAVE_REQUEST_STATUS.sql
@@TRG_LEAVE_REQUEST_DELETE.sql
@@DELETE_LEAVE_REQUEST.sql
@@V_LEAVE_REPORT.sql
@@V_LEAVE_APPROVAL.sql

-- CREATE OR REPLACE can leave an invalid object without stopping SQL*Plus.
DECLARE
    v_errors NUMBER;
BEGIN
    SELECT COUNT(*)
      INTO v_errors
      FROM all_errors
     WHERE owner = 'HRMS'
       AND name IN ('TRG_LEAVE_REQUEST_STATUS', 'TRG_LEAVE_REQUEST_DELETE',
                    'DELETE_LEAVE_REQUEST',
                    'V_LEAVE_REPORT', 'V_LEAVE_APPROVAL')
       AND attribute = 'ERROR';

    IF v_errors > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20004,
            'Leave upgrade has compilation errors. Check ALL_ERRORS for HRMS leave objects.'
        );
    END IF;
END;
/

WHENEVER SQLERROR CONTINUE NONE
