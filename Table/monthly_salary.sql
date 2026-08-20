DROP TABLE HRMS.MONTHLY_SALARY CASCADE CONSTRAINTS;

CREATE TABLE HRMS.MONTHLY_SALARY
(
  MS_ID            NUMBER GENERATED ALWAYS AS IDENTITY ( START WITH 78241 MAXVALUE 9999999999999999999999999999 MINVALUE 1 NOCYCLE CACHE 20 NOORDER NOKEEP NOSCALE) NOT NULL,
  EMPLOYEE_ID      NUMBER                       NOT NULL,
  SALARY_MONTH     NUMBER(6)                    NOT NULL,
  PROCESS_DATE     DATE                         DEFAULT SYSDATE,
  TOTAL_EARNING    NUMBER(12,2)                 DEFAULT 0,
  TOTAL_DEDUCTION  NUMBER(12,2)                 DEFAULT 0,
  NET_SALARY       NUMBER(12,2)                 DEFAULT 0,
  STATUS           VARCHAR2(20 BYTE)            DEFAULT 'DRAFT',
  CREATED_BY       NUMBER,
  CREATED_DATE     DATE                         DEFAULT SYSDATE,
  UPDATED_BY       NUMBER,
  UPDATED_DATE     DATE
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


CREATE UNIQUE INDEX HRMS.UQ_EMP_MONTH ON HRMS.MONTHLY_SALARY
(EMPLOYEE_ID, SALARY_MONTH)
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

ALTER TABLE HRMS.MONTHLY_SALARY ADD (
  PRIMARY KEY
  (MS_ID)
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
,  CONSTRAINT UQ_EMP_MONTH
  UNIQUE (EMPLOYEE_ID, SALARY_MONTH)
  USING INDEX HRMS.UQ_EMP_MONTH
  ENABLE VALIDATE);


DROP SEQUENCE HRMS.ISEQ$$_220336;

-- Sequence ISEQ$$_220336 is created automatically by Oracle for use with an Identity column


--  There is no statement for index HRMS.SYS_C0024433.
--  The object is created when the parent object is created.
