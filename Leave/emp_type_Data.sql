CREATE TABLE T_EMP_TYP
(
  ID           NUMBER,
  ETYPE        VARCHAR2(100 BYTE),
  DESCRIPTION  VARCHAR2(100 BYTE),
  ENT_BY       NUMBER,
  ENT_DATE     DATE                             DEFAULT SYSDATE,
  UPD_BY       NUMBER,
  UPD_DATE     DATE
);


CREATE UNIQUE INDEX PK_T_EMP_TYP ON T_EMP_TYP
(ID);

ALTER TABLE T_EMP_TYP ADD (
  CONSTRAINT PK_T_EMP_TYP
  PRIMARY KEY
  (ID));


CREATE OR REPLACE TRIGGER trg_t_emp_typ_pk
    BEFORE INSERT OR UPDATE
    ON t_emp_typ
    FOR EACH ROW
BEGIN
    IF :new.id IS NULL
    THEN
        SELECT NVL (MAX (id), 0) + 1 INTO :new.id FROM t_emp_typ;
    END IF;
END trg_t_emp_typ_pk;
/



SET DEFINE OFF;
Insert into T_EMP_TYP
   (ID, ETYPE, DESCRIPTION, ENT_BY, ENT_DATE, 
    UPD_BY, UPD_DATE)
 Values
   (0, 'Reguler', NULL, NULL, TO_DATE('9/22/2024', 'MM/DD/YYYY'), 
    NULL, NULL);
Insert into T_EMP_TYP
   (ID, ETYPE, DESCRIPTION, ENT_BY, ENT_DATE, 
    UPD_BY, UPD_DATE)
 Values
   (1, 'Probation', 'On Probation', NULL, TO_DATE('9/22/2024', 'MM/DD/YYYY'), 
    NULL, NULL);
Insert into T_EMP_TYP
   (ID, ETYPE, DESCRIPTION, ENT_BY, ENT_DATE, 
    UPD_BY, UPD_DATE)
 Values
   (2, 'Confirmed', 'Confirmational', NULL, TO_DATE('9/22/2024', 'MM/DD/YYYY'), 
    NULL, NULL);
Insert into T_EMP_TYP
   (ID, ETYPE, DESCRIPTION, ENT_BY, ENT_DATE, 
    UPD_BY, UPD_DATE)
 Values
   (3, 'Contractual', 'Contractual', NULL, TO_DATE('9/22/2024', 'MM/DD/YYYY'), 
    NULL, NULL);
Insert into T_EMP_TYP
   (ID, ETYPE, DESCRIPTION, ENT_BY, ENT_DATE, 
    UPD_BY, UPD_DATE)
 Values
   (4, 'Casual', NULL, NULL, TO_DATE('9/22/2024', 'MM/DD/YYYY'), 
    NULL, NULL);
COMMIT;
