CREATE TABLE MANUAL_ATT
(
  ID         NUMBER                             NOT NULL,
  EMPID      NUMBER,
  EMPCODE    VARCHAR2(30 BYTE),
  REASON     VARCHAR2(200 BYTE)                 NOT NULL,
  M_INTIME   DATE,
  M_OUTTIME  DATE,
  STATUS     VARCHAR2(20 BYTE),
  COMMENTS   VARCHAR2(1000 BYTE),
  COM_ID     NUMBER,
  ENT_DATE   DATE                               DEFAULT SYSDATE,
  ENT_BY     NUMBER,
  UPD_DATE   DATE,
  UPD_BY     NUMBER,
  ATT_DATE   DATE
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


ALTER TABLE MANUAL_ATT ADD (
  PRIMARY KEY
  (ID)
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


--  There is no statement for index HRMS.SYS_C0020020.
--  The object is created when the parent object is created.

CREATE OR REPLACE TRIGGER trg_manual_att_date
    BEFORE INSERT OR UPDATE
    ON MANUAL_ATT
    FOR EACH ROW
BEGIN
    :NEW.ATT_DATE := TO_DATE (NVL (:NEW.M_INTIME, :NEW.M_OUTTIME));
END;
/


CREATE OR REPLACE TRIGGER trg_manual_att_insert
    AFTER INSERT
    ON MANUAL_ATT
    FOR EACH ROW
DECLARE
    -- Declare variables to hold approver IDs
    v_rep_person_id   NUMBER;
    v_hod_id          NUMBER;
    v_md_id           NUMBER := 222000789; -- Example MD ID
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
        INSERT INTO m_att_app_history (m_att_id,
                                       approver_level,
                                       approver_id,
                                       approval_status,
                                       approval_date,
                                       comments,
                                       ent_date,
                                       ent_by)
             VALUES (:NEW.id,
                     'RP',
                     v_rep_person_id,
                     'PENDING',  -- Status is PENDING as it's waiting for RP approval
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
            INSERT INTO m_att_app_history (m_att_id,
                                           approver_level,
                                           approver_id,
                                           approval_status,
                                           approval_date,
                                           comments,
                                           ent_date,
                                           ent_by)
                 VALUES (:NEW.id,
                         'HOD',
                         v_hod_id,
                         'PENDING',  -- Status is PENDING as it's waiting for HOD approval
                         NULL,
                         'Waiting for Head of Department (HOD) approval',
                         SYSDATE,
                         :NEW.ent_by);

        -- If employee is HOD, forward to MD for approval
        ELSIF v_hod_id = :NEW.empid
        THEN
            INSERT INTO m_att_app_history (m_att_id,
                                           approver_level,
                                           approver_id,
                                           approval_status,
                                           approval_date,
                                           comments,
                                           ent_date,
                                           ent_by)
                 VALUES (:NEW.id,
                         'MD',
                         v_md_id,
                         'PENDING',  -- Status is PENDING as it's waiting for MD approval
                         NULL,
                         'Waiting for MD approval',
                         SYSDATE,
                         :NEW.ent_by);
            END IF;
--            -- After MD approval, forward to HR for final approval
--            INSERT INTO m_att_app_history (m_att_id,
--                                           approver_level,
--                                           approver_id,
--                                           approval_status,
--                                           approval_date,
--                                           comments,
--                                           ent_date,
--                                           ent_by)
--                 VALUES (:NEW.id,
--                         'HR',
--                         v_hr_id,  -- HR ID needs to be set
--                         'PENDING',  -- Status is PENDING as it's waiting for HR approval
--                         NULL,
--                         'Waiting for HR approval',
--                         SYSDATE,
--                         :NEW.ent_by);
        
    END IF;
END trg_manual_att_insert;
/


CREATE OR REPLACE TRIGGER trg_manual_att_pk
    BEFORE INSERT OR UPDATE
    ON manual_att
    FOR EACH ROW
DECLARE
    v_count   NUMBER;
BEGIN
    IF :new.id IS NULL
    THEN
        SELECT NVL (MAX (id), 0) + 1 INTO :new.id FROM manual_att;
    END IF;
--    SELECT COUNT (*)
--      INTO v_count
--      FROM MANUAL_ATT
--     WHERE     EMPID = :NEW.EMPID
--           AND (   TRUNC (M_INTIME) = TRUNC (:NEW.M_INTIME)
--                OR TRUNC (M_OUTTIME) = TRUNC (:NEW.M_OUTTIME)
--                OR TRUNC (M_INTIME) = TRUNC (:NEW.M_OUTTIME)
--                OR TRUNC (M_OUTTIME) = TRUNC (:NEW.M_INTIME));
--
--    -- If a duplicate exists, raise an exception to prevent the insert
--    IF v_count > 0
--    THEN
--        RAISE_APPLICATION_ERROR (
--            -20001,'Employee cannot apply on the same date twice.');
--    END IF;
END;
/


ALTER TABLE MANUAL_ATT ADD (
  FOREIGN KEY (EMPID) 
  REFERENCES EMPLOYEES (ID)
  ENABLE VALIDATE);
