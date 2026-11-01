CREATE TABLE LEAVE_REQUEST
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
  REQUEST_STATUS VARCHAR2(1 BYTE)               DEFAULT 'D' NOT NULL,
  ENT_DATE       DATE                           DEFAULT SYSDATE,
  ENT_BY         NUMBER,
  UPD_DATE       DATE,
  UPD_BY         NUMBER,
  APP_LEAVE_TYP  VARCHAR2(30 BYTE),
  COMMENTS       VARCHAR2(200 BYTE)
);


ALTER TABLE LEAVE_REQUEST ADD (
  PRIMARY KEY
  (LEAVE_ID));

ALTER TABLE LEAVE_REQUEST ADD (
  CONSTRAINT CK_LEAVE_REQUEST_STATUS CHECK (REQUEST_STATUS IN ('D', 'F', 'A')));

COMMENT ON COLUMN LEAVE_REQUEST.REQUEST_STATUS
  IS 'D = Draft, F = Forwarded, A = Final';


--  There is no statement for index HRMS.SYS_C0020157.
--  The object is created when the parent object is created.

-- Approval history is created on FORWARD by PKG_LEAVE_APPROVAL, not on draft INSERT.
@@TRG_LEAVE_REQUEST_PK.sql
