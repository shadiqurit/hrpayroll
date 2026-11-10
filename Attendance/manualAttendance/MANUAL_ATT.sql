-- New database definition only. For existing data run INSTALL_MANUAL_APPROVAL.sql.
CREATE TABLE MANUAL_ATT
(
  ID         NUMBER                             NOT NULL,
  EMPID      NUMBER,
  EMPCODE    VARCHAR2(30 BYTE),
  REASON     VARCHAR2(200 BYTE)                 NOT NULL,
  M_INTIME   DATE,
  M_OUTTIME  DATE,
  STATUS     VARCHAR2(20 BYTE) DEFAULT 'D',
  REQUEST_STATUS VARCHAR2(1 BYTE) DEFAULT 'D' NOT NULL,
  WORKFLOW_VERSION NUMBER DEFAULT 1 NOT NULL,
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

@@TRG_MANUAL_ATT_DATE.sql
@@TRG_MANUAL_ATT_PK.sql
ALTER TABLE MANUAL_ATT ADD (
  FOREIGN KEY (EMPID)
  REFERENCES EMPLOYEES (ID)
  ENABLE VALIDATE);
