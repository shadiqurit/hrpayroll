DROP TABLE HRMS.EMPLOYEES CASCADE CONSTRAINTS;

CREATE TABLE HRMS.EMPLOYEES
(
  ID                       NUMBER,
  EMP_ID                   VARCHAR2(30 BYTE),
  F_NAME                   VARCHAR2(30 BYTE),
  L_NAME                   VARCHAR2(30 BYTE),
  DOB                      DATE,
  MOBILE                   VARCHAR2(30 BYTE),
  EMAIL                    VARCHAR2(50 BYTE),
  FATHER                   VARCHAR2(50 BYTE),
  MOTHER                   VARCHAR2(50 BYTE),
  GENDER                   VARCHAR2(10 BYTE),
  HEIGHT                   VARCHAR2(30 BYTE),
  WEIGHT                   VARCHAR2(30 BYTE),
  BLOOD                    VARCHAR2(15 BYTE),
  NID                      VARCHAR2(30 BYTE),
  ADDRESS                  VARCHAR2(300 BYTE),
  C_POST                   NUMBER,
  C_THANA                  NUMBER,
  C_DISTRICT               NUMBER,
  C_DIVISION               NUMBER,
  P_ADDRESS                VARCHAR2(300 BYTE),
  P_POST                   NUMBER,
  P_THANA                  NUMBER,
  P_DISTRICT               NUMBER,
  P_DIVISION               NUMBER,
  PHOTO                    BLOB,
  JOIN_DATE                DATE,
  MARITAL_STATUS           VARCHAR2(10 BYTE),
  EMP_TYPE                 VARCHAR2(30 BYTE),
  DEPT_ID                  NUMBER,
  LOC_ID                   NUMBER,
  BRANCH_ID                NUMBER,
  DESIG_ID                 NUMBER,
  COM_ID                   NUMBER,
  JOB_ID                   NUMBER,
  USER_GRP                 NUMBER(3)            DEFAULT 0,
  PASSW                    VARCHAR2(32 BYTE),
  ENT_BY                   NUMBER,
  ENT_DATE                 DATE,
  UPD_BY                   NUMBER,
  UPD_DATE                 DATE,
  STATUS                   NUMBER,
  MIME_TYPE                VARCHAR2(200 BYTE),
  FILE_NAME                VARCHAR2(200 BYTE),
  EMPNO                    VARCHAR2(15 BYTE),
  RELIGION                 VARCHAR2(30 BYTE),
  ATT_DEV_ID               NUMBER(30),
  SECTION_ID               NUMBER,
  MC_ID                    NUMBER,
  STR_ID                   NUMBER,
  EMPID                    NUMBER,
  RETIREMENT_DATE          DATE,
  RESP                     VARCHAR2(100 BYTE),
  SEP_DATE                 DATE,
  IS_SAME_ADD              VARCHAR2(1 BYTE),
  CONF_DATE                DATE,
  SPOUSE                   VARCHAR2(50 BYTE),
  PASSPORT                 VARCHAR2(30 BYTE),
  FATHER_C                 VARCHAR2(30 BYTE),
  MOTHER_C                 VARCHAR2(30 BYTE),
  SPOUSE_C                 VARCHAR2(30 BYTE),
  FIELD_FORCE              VARCHAR2(10 BYTE)    DEFAULT 'N',
  CONFIRMATION_DUE_DATE    DATE,
  PROBATION_PERIOD_MONTHS  NUMBER               DEFAULT 12,
  INCREMENT_CYCLE_MONTHS   NUMBER               DEFAULT 12,
  LAST_INCREMENT_DATE      DATE,
  NEXT_INCREMENT_DATE      DATE,
  INCREMENT_HOLD_STATUS    VARCHAR2(1 BYTE)     DEFAULT 'N',
  INCREMENT_HOLD_REASON    VARCHAR2(500 BYTE),
  INCREMENT_HOLD_DATE      DATE,
  EB_STATUS                VARCHAR2(20 BYTE)    DEFAULT 'NORMAL',
  GRADE                    VARCHAR2(30 BYTE)
)
LOB (PHOTO) STORE AS SECUREFILE (
  TABLESPACE  HRMS
  ENABLE      STORAGE IN ROW
  CHUNK       8192
  RETENTION
  NOCACHE
  LOGGING
  STORAGE    (
              INITIAL          104K
              NEXT             1M
              MINEXTENTS       1
              MAXEXTENTS       UNLIMITED
              PCTINCREASE      0
              BUFFER_POOL      DEFAULT
             ))
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


CREATE UNIQUE INDEX HRMS.EMPLOYEES_U01 ON HRMS.EMPLOYEES
(MC_ID)
LOGGING
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
           );
CREATE UNIQUE INDEX HRMS.EMPLOYEES_U02 ON HRMS.EMPLOYEES
(EMPID)
LOGGING
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
           );
CREATE UNIQUE INDEX HRMS.EMPLOYESS_U01 ON HRMS.EMPLOYEES
(EMP_ID)
LOGGING
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
           );
CREATE UNIQUE INDEX HRMS.PK_EMPLOYESS ON HRMS.EMPLOYEES
(ID)
LOGGING
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
           );

ALTER TABLE HRMS.EMPLOYEES ADD (
  CONSTRAINT PK_EMPLOYESS
  PRIMARY KEY
  (ID)
  USING INDEX HRMS.PK_EMPLOYESS
  ENABLE VALIDATE
,  CONSTRAINT EMPLOYEES_U01
  UNIQUE (MC_ID)
  USING INDEX HRMS.EMPLOYEES_U01
  ENABLE VALIDATE
,  CONSTRAINT EMPLOYEES_U02
  UNIQUE (EMPID)
  USING INDEX HRMS.EMPLOYEES_U02
  ENABLE VALIDATE
,  CONSTRAINT EMPLOYESS_U01
  UNIQUE (EMP_ID)
  USING INDEX HRMS.EMPLOYESS_U01
  ENABLE VALIDATE
,  CONSTRAINT EMPLOYESS_U02
  UNIQUE (EMAIL)
  DISABLE NOVALIDATE
,  CONSTRAINT EMPLOYESS_U03
  UNIQUE (NID)
  DISABLE NOVALIDATE);


CREATE INDEX HRMS.IDX_EMPLOYEES_COMID ON HRMS.EMPLOYEES
(COM_ID)
LOGGING
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
           );

CREATE INDEX HRMS.IDX_EMPLOYEES_DEPT_DESIG ON HRMS.EMPLOYEES
(DEPT_ID, DESIG_ID, JOB_ID)
LOGGING
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
           );

CREATE INDEX HRMS.IDX_EMPLOYEES_LOCATION ON HRMS.EMPLOYEES
(C_DIVISION, C_DISTRICT, C_THANA, C_POST)
LOGGING
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
           );

CREATE INDEX HRMS.IDX_EMPLOYEES_PERMANENT ON HRMS.EMPLOYEES
(P_DIVISION, P_DISTRICT, P_THANA, P_POST)
LOGGING
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
           );

CREATE INDEX HRMS.IDX_EMPLOYEES_STATUS ON HRMS.EMPLOYEES
(STATUS, EMP_TYPE)
LOGGING
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
           );

CREATE OR REPLACE TRIGGER HRMS.TRG_EMPLOYEES_PK
    BEFORE INSERT OR UPDATE
    ON HRMS.EMPLOYEES
    FOR EACH ROW
BEGIN
    IF :new.id IS NULL
    THEN
        SELECT NVL (MAX (id), 0) + 1 INTO :new.id FROM employees;
    END IF;

    IF :NEW.is_same_add = 'Y'
    THEN
        :NEW.P_ADDRESS := :NEW.address;
        :NEW.p_post := :NEW.C_POST;
        :NEW.p_thana := :NEW.C_THANA;
        :NEW.p_district := :NEW.C_DISTRICT;
        :NEW.p_division := :NEW.C_DIVISION;
    END IF;
END TRG_EMPLOYEES_PK;
/


CREATE OR REPLACE TRIGGER HRMS.t_user_company_asgn
    AFTER INSERT
    ON HRMS.EMPLOYEES
    FOR EACH ROW
BEGIN
    INSERT INTO users_company (EMPID, com_id)
         VALUES (:new.id, 1);
END t_user_company_asgn;
/


ALTER TABLE HRMS.EMPLOYEES ADD (
  CONSTRAINT EMPLOYEES_R01 
  FOREIGN KEY (USER_GRP) 
  REFERENCES HRMS.USER_GROUP (ID)
  ENABLE VALIDATE);
