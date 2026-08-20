DROP TABLE HRMS.LEAVE_REQUEST CASCADE CONSTRAINTS;

CREATE TABLE HRMS.LEAVE_REQUEST
(
  LEAVE_ID       NUMBER,
  EMPID          NUMBER                         NOT NULL,
  LEAVE_TYPE     VARCHAR2(10 BYTE)              NOT NULL,
  LEAVE_BALANCE  NUMBER                         DEFAULT 10,
  LEAVE_TAKEN    NUMBER                         DEFAULT 0,
  APPLIED_DATE   DATE                           DEFAULT SYSDATE,
  L_START_DATE   DATE                           NOT NULL,
  L_END_DATE     DATE                           NOT NULL,
  PROPOSED_DAYS  NUMBER                         NOT NULL,
  LEAVE_PURPOSE  VARCHAR2(255 BYTE)             NOT NULL,
  LEAVE_ADDRESS  VARCHAR2(255 BYTE)             NOT NULL,
  LEAVE_STATUS   VARCHAR2(10 BYTE)              DEFAULT 'P',
  ENT_DATE       DATE                           DEFAULT SYSDATE,
  ENT_BY         NUMBER,
  UPD_DATE       DATE,
  UPD_BY         NUMBER,
  APP_LEAVE_TYP  VARCHAR2(30 BYTE),
  COMMENTS       VARCHAR2(200 BYTE)
)
TABLESPACE HRMS
PCTUSED    0
PCTFREE    10
INITRANS   1
MAXTRANS   255
STORAGE    (
            INITIAL          64K
            NEXT             1M
            MINEXTENTS       1
            MAXEXTENTS       UNLIMITED
            PCTINCREASE      0
            BUFFER_POOL      DEFAULT
           )
LOGGING 
NOCOMPRESS 
NOCACHE;


ALTER TABLE HRMS.LEAVE_REQUEST ADD (
  PRIMARY KEY
  (LEAVE_ID)
  USING INDEX
    TABLESPACE HRMS
    PCTFREE    10
    INITRANS   2
    MAXTRANS   255
    STORAGE    (
                INITIAL          64K
                NEXT             1M
                MINEXTENTS       1
                MAXEXTENTS       UNLIMITED
                PCTINCREASE      0
                BUFFER_POOL      DEFAULT
               )
  ENABLE VALIDATE);


--  There is no statement for index HRMS.SYS_C0020157.
--  The object is created when the parent object is created.

CREATE OR REPLACE TRIGGER HRMS.trg_leave_request_insert
    AFTER INSERT
    ON HRMS.LEAVE_REQUEST
    FOR EACH ROW
DECLARE
    -- Declare variables to hold approver IDs
    v_rep_person_id   NUMBER;
    v_hod_id          NUMBER;
    v_md_id           NUMBER := 222000789;                    -- Example MD ID
    v_hr_id           NUMBER := 200007478; -- HR ID, can be assigned as needed
BEGIN
    -- Get the Reporting Person (RP) ID from the emp_rp table
    BEGIN
        SELECT rep_person_id
          INTO v_rep_person_id
          FROM emp_rp
         WHERE emp_id = :NEW.empid AND status = '1';
    EXCEPTION
        WHEN NO_DATA_FOUND
        THEN
            v_rep_person_id := NULL; -- No reporting person, proceed without inserting RP approval history
    END;

    -- Insert RP approval history if Reporting Person exists
    IF v_rep_person_id IS NOT NULL
    THEN
        INSERT INTO leave_app_history (LEAVE_ID,
                                       approver_level,
                                       approver_id,
                                       approval_status,
                                       approval_date,
                                       comments,
                                       ent_date,
                                       ent_by)
             VALUES (:NEW.LEAVE_ID,
                     'RP',
                     v_rep_person_id,
                     'PENDING', -- Status is PENDING as it's waiting for RP approval
                     NULL,
                     'Waiting for Reporting Person approval',
                     SYSDATE,
                     :NEW.ent_by);
    ELSE
        -- Get HOD ID based on employee's department
        SELECT hod_id
          INTO v_hod_id
          FROM hod
         WHERE dept_id = (SELECT dept_id
                            FROM employees
                           WHERE id = :NEW.empid);

        -- If employee is not HOD, forward to HOD for approval
        IF v_hod_id <> :NEW.empid
        THEN
            INSERT INTO leave_app_history (LEAVE_ID,
                                           approver_level,
                                           approver_id,
                                           approval_status,
                                           approval_date,
                                           comments,
                                           ent_date,
                                           ent_by)
                 VALUES (:NEW.LEAVE_ID,
                         'HOD',
                         v_hod_id,
                         'PENDING', -- Status is PENDING as it's waiting for HOD approval
                         NULL,
                         'Waiting for Head of Department (HOD) approval',
                         SYSDATE,
                         :NEW.ent_by);
        -- If employee is HOD, forward to MD for approval
        ELSIF v_hod_id = :NEW.empid
        THEN
            INSERT INTO leave_app_history (LEAVE_ID,
                                           approver_level,
                                           approver_id,
                                           approval_status,
                                           approval_date,
                                           comments,
                                           ent_date,
                                           ent_by)
                 VALUES (:NEW.LEAVE_ID,
                         'MD',
                         v_md_id,
                         'PENDING', -- Status is PENDING as it's waiting for MD approval
                         NULL,
                         'Waiting for MD approval',
                         SYSDATE,
                         :NEW.ent_by);
        END IF;
    END IF;
END;
/


CREATE OR REPLACE TRIGGER HRMS.trg_leave_request_pk
    BEFORE INSERT OR UPDATE
    ON HRMS.LEAVE_REQUEST
    FOR EACH ROW
BEGIN
    IF :new.leave_id IS NULL
    THEN
        SELECT NVL (MAX (leave_id), 0) + 1
          INTO :new.leave_id
          FROM leave_request;
    END IF;
END;
/
