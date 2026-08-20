DROP TABLE HRMS.EMP_SALARY_STRUCTURE CASCADE CONSTRAINTS;

CREATE TABLE HRMS.EMP_SALARY_STRUCTURE
(
  SALS_ID        NUMBER GENERATED ALWAYS AS IDENTITY ( START WITH 51961 MAXVALUE 9999999999999999999999999999 MINVALUE 1 NOCYCLE CACHE 20 NOORDER NOKEEP NOSCALE) NOT NULL,
  EMPLOYEE_ID    NUMBER,
  SLNO           NUMBER,
  HEADCODE       VARCHAR2(20 BYTE),
  AMOUNT         NUMBER(12,2)                   DEFAULT 0,
  REVISION_TYPE  VARCHAR2(1 BYTE)               DEFAULT 'J',
  IS_ACTIVE      VARCHAR2(1 BYTE)               DEFAULT 'Y',
  CREATED_BY     NUMBER,
  CREATED_DATE   DATE                           DEFAULT SYSDATE,
  UPDATED_BY     NUMBER,
  UPDATED_DATE   DATE
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


ALTER TABLE HRMS.EMP_SALARY_STRUCTURE ADD (
  CHECK (revision_type IN ('J',
                                               'I',
                                               'P',
                                               'R'))
  ENABLE VALIDATE
,  CHECK (is_active IN ('Y', 'N'))
  ENABLE VALIDATE
,  PRIMARY KEY
  (SALS_ID)
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
  ENABLE VALIDATE
,  CONSTRAINT EMP_SALARY_STRUCTURE_U01
  UNIQUE (EMPLOYEE_ID, SLNO)
  USING INDEX HRMS.IDX_ESS_EMP_HEAD
  ENABLE VALIDATE);


DROP SEQUENCE HRMS.ISEQ$$_217725;

-- Sequence ISEQ$$_217725 is created automatically by Oracle for use with an Identity column


CREATE INDEX HRMS.IDX_ESS_EMP_ACTIVE ON HRMS.EMP_SALARY_STRUCTURE
(EMPLOYEE_ID, IS_ACTIVE)
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

CREATE INDEX HRMS.IDX_ESS_EMP_HEAD ON HRMS.EMP_SALARY_STRUCTURE
(SLNO, EMPLOYEE_ID, HEADCODE)
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

--  There is no statement for index HRMS.SYS_C0024164.
--  The object is created when the parent object is created.

ALTER TABLE HRMS.EMP_SALARY_STRUCTURE ADD (
  FOREIGN KEY (EMPLOYEE_ID) 
  REFERENCES HRMS.EMPLOYEES (ID)
  ENABLE VALIDATE);
