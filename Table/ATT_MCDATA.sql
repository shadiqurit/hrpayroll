CREATE TABLE ATT_MCDATA
(
  USERID     NUMBER                             NOT NULL,
  ATTTIME    DATE                               NOT NULL,
  DEVICE_ID  NUMBER                             NOT NULL,
  FLAG       VARCHAR2(1 BYTE)                   DEFAULT 'N',
  STATUS     NUMBER
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


CREATE INDEX IDX_ATT_MCDATA_FLAG ON ATT_MCDATA
(USERID)
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

CREATE INDEX IDX_ATT_MCDATA_TIME ON ATT_MCDATA
(ATTTIME)
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

CREATE INDEX IDX_ATT_MCDATA_USERID_ATTTIME_FLAG ON ATT_MCDATA
(USERID, ATTTIME, FLAG)
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

CREATE INDEX IDX_ATT_MCDATA_USER_ATTTIME ON ATT_MCDATA
(USERID, ATTTIME)
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
