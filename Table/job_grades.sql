DROP TABLE HRMS.JOB_GRADES CASCADE CONSTRAINTS;

CREATE TABLE HRMS.JOB_GRADES
(
  ID           NUMBER,
  GRADE_NAME   VARCHAR2(100 BYTE),
  MIN_SALARY   NUMBER,
  MAX_SALARY   NUMBER,
  DESCRIPTION  VARCHAR2(255 BYTE),
  ENT_DATE     DATE                             DEFAULT SYSDATE,
  UPD_DATE     DATE,
  ENT_BY       NUMBER,
  UPD_BY       NUMBER,
  SCALES       VARCHAR2(100 BYTE),
  GRADE_CODE   VARCHAR2(30 BYTE),
  GRADE_ORDER  NUMBER(3)
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


ALTER TABLE HRMS.JOB_GRADES ADD (
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


--  There is no statement for index HRMS.SYS_C0015828.
--  The object is created when the parent object is created.

CREATE OR REPLACE TRIGGER HRMS.TRG_job_grades_PK
    BEFORE INSERT OR UPDATE
    ON HRMS.JOB_GRADES
    FOR EACH ROW
BEGIN
    IF :new.id IS NULL
    THEN
        SELECT NVL (MAX (id), 0) + 1 INTO :new.id FROM job_grades;
    END IF;
END TRG_job_grades_PK;
/
