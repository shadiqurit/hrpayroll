-- ============================================================================
-- SHORT LEAVE & SHORT TOUR MODULE
-- 01_SHORT_LEAVE_TABLES.sql
-- Table definitions for Short Leave and Short Tour (Personal & Official)
-- ============================================================================

-- 1. Main Request Table: SHORT_LEAVE_TOUR_REQ
CREATE TABLE HRMS.SHORT_LEAVE_TOUR_REQ
(
  ID                  NUMBER                        NOT NULL,
  REQ_NO              VARCHAR2(30 BYTE),            -- Auto-generated readable code, e.g. SL-202611-001
  EMPID               NUMBER                        NOT NULL, -- FK to EMPLOYEES.ID
  EMPCODE             VARCHAR2(30 BYTE),            -- Character employee code (e.g. IPI-001375)
  COM_ID              NUMBER                        NOT NULL, -- Company ID
  
  -- Request Classification
  REQ_CATEGORY        VARCHAR2(20 BYTE)             NOT NULL, -- 'SHORT_LEAVE' or 'SHORT_TOUR'
  PURPOSE_TYPE        VARCHAR2(20 BYTE)             NOT NULL, -- 'PERSONAL' or 'OFFICIAL'
  
  -- Date and Timings
  REQ_DATE            DATE                          NOT NULL, -- Date of Short Leave / Tour
  OUT_TIME            DATE                          NOT NULL, -- From Time (Date with Time HH24:MI)
  IN_TIME             DATE                          NOT NULL, -- To Time (Date with Time HH24:MI)
  DURATION_MINUTES    NUMBER                        DEFAULT 0, -- Auto-calculated duration in minutes
  DURATION_DISPLAY    VARCHAR2(30 BYTE),            -- E.g. "1 hr 30 mins"
  
  -- Purpose and Destination Details
  REASON_PURPOSE      VARCHAR2(500 BYTE)            NOT NULL, -- Detailed reason
  DESTINATION_PLACE   VARCHAR2(250 BYTE),           -- For Short Tour or outside visit
  CONTACT_DURING_ABS  VARCHAR2(100 BYTE),           -- Emergency mobile / phone
  TRANSPORT_MODE      VARCHAR2(50 BYTE),            -- Transport used (Official Vehicle, Rickshaw, CNG, Personal)
  IS_EXPENSE_CLAIM    VARCHAR2(1 BYTE)  DEFAULT 'N',-- 'Y'/'N' (for official tours)
  ESTIMATED_EXPENSE   NUMBER(12,2)      DEFAULT 0,
  
  -- Workflow and Status
  STATUS              VARCHAR2(20 BYTE) DEFAULT 'D' NOT NULL, -- D=Draft, P=Pending, A=Approved, R=Rejected, C=Cancelled
  REQUEST_STATUS      VARCHAR2(1 BYTE)  DEFAULT 'D' NOT NULL, -- D=Draft, F=Forwarded, A=Approved, R=Rejected
  CURRENT_STAGE       VARCHAR2(50 BYTE) DEFAULT 'DRAFT',      -- DRAFT, PENDING_RP, PENDING_HOD, PENDING_HR, COMPLETED
  
  -- Security Gate Pass Info (Optional gate punch verification)
  GATE_PASS_NO        VARCHAR2(50 BYTE),
  ACTUAL_GATE_OUT     DATE,
  ACTUAL_GATE_IN      DATE,
  GATE_SECURITY_BY    NUMBER,                       -- Security personnel EMPID
  
  -- Audit Columns
  ENT_DATE            DATE              DEFAULT SYSDATE NOT NULL,
  ENT_BY              NUMBER            NOT NULL,
  UPD_DATE            DATE,
  UPD_BY              NUMBER,
  COMMENTS            VARCHAR2(500 BYTE)
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

-- Primary Key
ALTER TABLE HRMS.SHORT_LEAVE_TOUR_REQ ADD (
  CONSTRAINT PK_SHORT_LEAVE_TOUR_REQ PRIMARY KEY (ID)
  USING INDEX TABLESPACE HRMS
);

-- Foreign Key to EMPLOYEES
ALTER TABLE HRMS.SHORT_LEAVE_TOUR_REQ ADD (
  CONSTRAINT FK_SHORT_LEAVE_EMP FOREIGN KEY (EMPID)
  REFERENCES HRMS.EMPLOYEES (ID)
);

-- Check Constraints
ALTER TABLE HRMS.SHORT_LEAVE_TOUR_REQ ADD (
  CONSTRAINT CK_SL_REQ_CATEGORY CHECK (REQ_CATEGORY IN ('SHORT_LEAVE', 'SHORT_TOUR')),
  CONSTRAINT CK_SL_PURPOSE_TYPE CHECK (PURPOSE_TYPE IN ('PERSONAL', 'OFFICIAL')),
  CONSTRAINT CK_SL_REQUEST_STATUS CHECK (REQUEST_STATUS IN ('D', 'F', 'A', 'R', 'C')),
  CONSTRAINT CK_SL_STATUS CHECK (STATUS IN ('D', 'P', 'A', 'R', 'C'))
);

-- Comments
COMMENT ON TABLE HRMS.SHORT_LEAVE_TOUR_REQ IS 'Applications for Short Leave and Short Tour (Personal and Official) with monthly quotas';
COMMENT ON COLUMN HRMS.SHORT_LEAVE_TOUR_REQ.REQ_CATEGORY IS 'SHORT_LEAVE (hourly leave/gate pass) or SHORT_TOUR (short official/personal field duty)';
COMMENT ON COLUMN HRMS.SHORT_LEAVE_TOUR_REQ.PURPOSE_TYPE IS 'PERSONAL (strictly max 3/month for short leave) or OFFICIAL';
COMMENT ON COLUMN HRMS.SHORT_LEAVE_TOUR_REQ.REQUEST_STATUS IS 'D = Draft, F = Forwarded, A = Final Approved, R = Rejected, C = Cancelled';


-- 2. Approval History Table: SHORT_LEAVE_APP_HISTORY
CREATE TABLE HRMS.SHORT_LEAVE_APP_HISTORY
(
  ID                  NUMBER                        NOT NULL,
  REQ_ID              NUMBER                        NOT NULL, -- FK to SHORT_LEAVE_TOUR_REQ.ID
  STEP_NO             NUMBER                        DEFAULT 10,
  APPROVER_LEVEL      VARCHAR2(50 BYTE)             NOT NULL, -- RP, HOD, PLANT_HEAD, HRD, SECURITY
  APPROVER_ID         NUMBER,                                 -- Numeric EMPLOYEES.ID
  APPROVAL_STATUS     VARCHAR2(50 BYTE)             NOT NULL, -- PENDING, APPROVED, REJECTED, WAITING, FORWARDED
  APPROVAL_DATE       DATE,
  COMMENTS            VARCHAR2(500 BYTE),
  COM_ID              NUMBER,
  ENT_DATE            DATE                          DEFAULT SYSDATE,
  ENT_BY              NUMBER,
  UPD_DATE            DATE,
  UPD_BY              NUMBER
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

-- Primary Key
ALTER TABLE HRMS.SHORT_LEAVE_APP_HISTORY ADD (
  CONSTRAINT PK_SL_APP_HISTORY PRIMARY KEY (ID)
  USING INDEX TABLESPACE HRMS
);

-- Foreign Key to Main Request Table
ALTER TABLE HRMS.SHORT_LEAVE_APP_HISTORY ADD (
  CONSTRAINT FK_SL_HISTORY_REQ FOREIGN KEY (REQ_ID)
  REFERENCES HRMS.SHORT_LEAVE_TOUR_REQ (ID)
  ON DELETE CASCADE
);

-- Index on REQ_ID and APPROVER_ID for query speed
CREATE INDEX HRMS.IDX_SL_HIST_REQ ON HRMS.SHORT_LEAVE_APP_HISTORY(REQ_ID);
CREATE INDEX HRMS.IDX_SL_HIST_APPROVER ON HRMS.SHORT_LEAVE_APP_HISTORY(APPROVER_ID, APPROVAL_STATUS);
CREATE INDEX HRMS.IDX_SL_EMP_DATE ON HRMS.SHORT_LEAVE_TOUR_REQ(EMPID, REQ_DATE, STATUS);


-- 3. Sequences
CREATE SEQUENCE HRMS.SEQ_SHORT_LEAVE_TOUR_REQ
  START WITH 1
  INCREMENT BY 1
  NOCACHE
  NOCYCLE;

CREATE SEQUENCE HRMS.SEQ_SHORT_LEAVE_APP_HIST
  START WITH 1
  INCREMENT BY 1
  NOCACHE
  NOCYCLE;


-- 4. Triggers
CREATE OR REPLACE TRIGGER HRMS.TRG_SHORT_LEAVE_TOUR_PK
BEFORE INSERT ON HRMS.SHORT_LEAVE_TOUR_REQ
FOR EACH ROW
BEGIN
  IF :NEW.ID IS NULL THEN
    :NEW.ID := HRMS.SEQ_SHORT_LEAVE_TOUR_REQ.NEXTVAL;
  END IF;

  -- Generate human-friendly reference number: SL-YYYYMM-XXXX or ST-YYYYMM-XXXX
  IF :NEW.REQ_NO IS NULL THEN
    IF :NEW.REQ_CATEGORY = 'SHORT_LEAVE' THEN
      :NEW.REQ_NO := 'SL-' || TO_CHAR(:NEW.REQ_DATE, 'YYYYMM') || '-' || LPAD(:NEW.ID, 4, '0');
    ELSE
      :NEW.REQ_NO := 'ST-' || TO_CHAR(:NEW.REQ_DATE, 'YYYYMM') || '-' || LPAD(:NEW.ID, 4, '0');
    END IF;
  END IF;

  -- Calculate duration in minutes if OUT_TIME and IN_TIME are given
  IF :NEW.OUT_TIME IS NOT NULL AND :NEW.IN_TIME IS NOT NULL THEN
    :NEW.DURATION_MINUTES := ROUND((:NEW.IN_TIME - :NEW.OUT_TIME) * 24 * 60);
    IF :NEW.DURATION_MINUTES > 0 THEN
      :NEW.DURATION_DISPLAY := TRUNC(:NEW.DURATION_MINUTES / 60) || ' hr ' || 
                               MOD(:NEW.DURATION_MINUTES, 60) || ' min';
    END IF;
  END IF;
END;
/

CREATE OR REPLACE TRIGGER HRMS.TRG_SHORT_LEAVE_APP_HIST_PK
BEFORE INSERT ON HRMS.SHORT_LEAVE_APP_HISTORY
FOR EACH ROW
BEGIN
  IF :NEW.ID IS NULL THEN
    :NEW.ID := HRMS.SEQ_SHORT_LEAVE_APP_HIST.NEXTVAL;
  END IF;
END;
/
