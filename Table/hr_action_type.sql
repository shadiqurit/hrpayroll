DROP TABLE HRMS.HR_ACTION_TYPE CASCADE CONSTRAINTS;

CREATE TABLE HRMS.HR_ACTION_TYPE
(
  ACTION_TYPE_ID  NUMBER GENERATED ALWAYS AS IDENTITY ( START WITH 21 MAXVALUE 9999999999999999999999999999 MINVALUE 1 NOCYCLE CACHE 20 NOORDER NOKEEP NOSCALE) NOT NULL,
  ACTION_CODE     VARCHAR2(30 BYTE)             NOT NULL,
  ACTION_NAME     VARCHAR2(100 BYTE)            NOT NULL,
  IS_ACTIVE       VARCHAR2(1 BYTE)              DEFAULT 'Y',
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


ALTER TABLE HRMS.HR_ACTION_TYPE ADD (
  PRIMARY KEY
  (ACTION_TYPE_ID)
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
,  UNIQUE (ACTION_CODE)
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


DROP SEQUENCE HRMS.ISEQ$$_226094;

-- Sequence ISEQ$$_226094 is created automatically by Oracle for use with an Identity column


--  There is no statement for index HRMS.SYS_C0024981.
--  The object is created when the parent object is created.

--  There is no statement for index HRMS.SYS_C0024982.
--  The object is created when the parent object is created.
