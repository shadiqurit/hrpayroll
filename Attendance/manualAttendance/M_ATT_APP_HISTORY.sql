CREATE TABLE M_ATT_APP_HISTORY
(
  ID               NUMBER                       NOT NULL,
  M_ATT_ID         NUMBER,
  APPROVER_LEVEL   VARCHAR2(50 BYTE),
  APPROVER_ID      NUMBER,
  APPROVAL_DATE    DATE,
  APPROVAL_STATUS  VARCHAR2(50 BYTE),
  COMMENTS         VARCHAR2(300 BYTE),
  COM_ID           NUMBER,
  ENT_DATE         DATE                         DEFAULT SYSDATE,
  ENT_BY           NUMBER,
  UPD_DATE         DATE,
  UPD_BY           NUMBER
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


ALTER TABLE M_ATT_APP_HISTORY ADD (
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


--  There is no statement for index HRMS.SYS_C0020023.
--  The object is created when the parent object is created.

CREATE OR REPLACE TRIGGER trg_m_att_app_history_pk
    BEFORE INSERT OR UPDATE
    ON m_att_app_history
    FOR EACH ROW
BEGIN
    IF :new.id IS NULL
    THEN
        SELECT NVL (MAX (id), 0) + 1 INTO :new.id FROM m_att_app_history;
    END IF;
END;
/


ALTER TABLE M_ATT_APP_HISTORY ADD (
  FOREIGN KEY (M_ATT_ID) 
  REFERENCES MANUAL_ATT (ID)
  ENABLE VALIDATE);
