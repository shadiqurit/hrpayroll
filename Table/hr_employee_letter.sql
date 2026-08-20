/* ============================================================
   HRMS EMPLOYEE LETTER TABLE
   ============================================================ */

CREATE TABLE hr_employee_letter
(
    letter_id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    emp_id             NUMBER NOT NULL REFERENCES employees (id),
    action_id          NUMBER,
    promotion_id       NUMBER REFERENCES hr_employee_promotion (promotion_id),
    template_id        NUMBER REFERENCES hr_letter_template (template_id),
    letter_no          VARCHAR2 (30),
    letter_date        DATE DEFAULT SYSDATE NOT NULL,
    subject_text       VARCHAR2 (500),
    body_html          CLOB NOT NULL,
    body_text          CLOB,
    status             VARCHAR2 (20) DEFAULT 'DRAFT' NOT NULL,
    generated_by       NUMBER,
    generated_date     DATE DEFAULT SYSDATE,
    approved_by        NUMBER,
    approved_date      DATE,
    issued_by          NUMBER,
    issued_date        DATE,
    CONSTRAINT uk_hr_emp_letter_no UNIQUE (letter_no),
    CONSTRAINT chk_hr_emp_letter_status CHECK
        (status IN ('DRAFT', 'APPROVED', 'ISSUED', 'CANCELLED'))
);

