/* ============================================================
   HRMS EMPLOYEE PROMOTION TABLE
   ============================================================ */

CREATE TABLE hr_employee_promotion
(
    promotion_id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    promotion_no          VARCHAR2 (30),
    emp_id                NUMBER NOT NULL REFERENCES employees (id),
    action_id             NUMBER,
    promotion_type        VARCHAR2 (20) DEFAULT 'REGULAR' NOT NULL,
    accelerated_count     NUMBER (3),
    promotion_date        DATE DEFAULT SYSDATE NOT NULL,
    effective_date        DATE NOT NULL,

    old_emp_type_id       NUMBER,
    new_emp_type_id       NUMBER,
    old_job_id            NUMBER,
    new_job_id            NUMBER NOT NULL,
    old_desig_id          NUMBER,
    new_desig_id          NUMBER NOT NULL,
    old_dept_id           NUMBER,
    new_dept_id           NUMBER,

    old_basic             NUMBER (14, 2),
    new_basic             NUMBER (14, 2) NOT NULL,
    old_gross             NUMBER (14, 2),
    new_gross             NUMBER (14, 2),
    increase_amount       NUMBER (14, 2),
    increase_percent      NUMBER (8, 2),

    reason                VARCHAR2 (1000),
    remarks               VARCHAR2 (1000),
    approval_status       VARCHAR2 (20) DEFAULT 'DRAFT' NOT NULL,

    proposed_by           NUMBER,
    proposed_date         DATE DEFAULT SYSDATE,
    checked_by            NUMBER,
    checked_date          DATE,
    approved_by           NUMBER,
    approved_date         DATE,
    posted_by             NUMBER,
    posted_date           DATE,

    ent_by                NUMBER,
    ent_date              DATE DEFAULT SYSDATE,
    upd_by                NUMBER,
    upd_date              DATE,

    CONSTRAINT uk_hr_emp_promotion_no UNIQUE (promotion_no),
    CONSTRAINT chk_hr_emp_promo_type CHECK
        (promotion_type IN ('REGULAR', 'ACCELERATED')),
    CONSTRAINT chk_hr_emp_promo_status CHECK
        (approval_status IN ('DRAFT', 'SUBMITTED', 'CHECKED', 'APPROVED', 'POSTED', 'CANCELLED')),
    CONSTRAINT chk_hr_emp_promo_salary CHECK (new_basic >= 0)
);

CREATE INDEX idx_hr_emp_promo_emp
    ON hr_employee_promotion (emp_id, effective_date);

CREATE INDEX idx_hr_emp_promo_status
    ON hr_employee_promotion (approval_status);

CREATE INDEX idx_hr_emp_promo_type
    ON hr_employee_promotion (emp_id, promotion_type, approval_status);

CREATE SEQUENCE hr_promotion_no_seq
    START WITH 1
    INCREMENT BY 1
    NOCACHE;

CREATE OR REPLACE TRIGGER trg_hr_emp_promotion_no
    BEFORE INSERT
    ON hr_employee_promotion
    FOR EACH ROW
BEGIN
    IF :new.promotion_no IS NULL
    THEN
        :new.promotion_no :=
               'PRO-'
            || TO_CHAR (NVL (:new.effective_date, SYSDATE), 'YYYY')
            || '-'
            || LPAD (hr_promotion_no_seq.NEXTVAL, 6, '0');
    END IF;
END;
/

