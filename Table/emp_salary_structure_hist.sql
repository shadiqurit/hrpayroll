DROP TABLE HRMS.EMP_SALARY_STRUCTURE_HIST CASCADE CONSTRAINTS;

CREATE TABLE HRMS.EMP_SALARY_STRUCTURE_HIST
(
  HIST_ID         NUMBER GENERATED ALWAYS AS IDENTITY ( START WITH 101 MAXVALUE 9999999999999999999999999999 MINVALUE 1 NOCYCLE CACHE 20 NOORDER NOKEEP NOSCALE) NOT NULL,
  ACTION_ID       NUMBER                        NOT NULL,
  EMP_ID          NUMBER                        NOT NULL,
  SALS_ID         NUMBER,
  SLNO            NUMBER,
  HEADCODE        VARCHAR2(30 BYTE),
  OLD_AMOUNT      NUMBER(14,2),
  NEW_AMOUNT      NUMBER(14,2),
  REVISION_TYPE   VARCHAR2(1 BYTE),
  EFFECTIVE_DATE  DATE,
  REMARKS         VARCHAR2(1000 BYTE),
  ENT_BY          NUMBER,
  ENT_DATE        DATE                          DEFAULT SYSDATE
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


ALTER TABLE HRMS.EMP_SALARY_STRUCTURE_HIST ADD (
  PRIMARY KEY
  (HIST_ID)
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


DROP SEQUENCE HRMS.ISEQ$$_226101;

-- Sequence ISEQ$$_226101 is created automatically by Oracle for use with an Identity column


--  There is no statement for index HRMS.SYS_C0024992.
--  The object is created when the parent object is created.
