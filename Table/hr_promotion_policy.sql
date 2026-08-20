/* ============================================================
   HRMS PROMOTION POLICY TABLE
   ============================================================ */

CREATE TABLE hr_promotion_policy
(
    policy_id                    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    policy_code                  VARCHAR2 (30) NOT NULL UNIQUE,
    policy_name                  VARCHAR2 (150) NOT NULL,
    max_accelerated_promotions   NUMBER (3) DEFAULT 2 NOT NULL,
    is_active                    VARCHAR2 (1) DEFAULT 'Y' NOT NULL,
    effective_from               DATE DEFAULT TRUNC (SYSDATE),
    effective_to                 DATE,
    remarks                      VARCHAR2 (1000),
    ent_by                       NUMBER,
    ent_date                     DATE DEFAULT SYSDATE,
    upd_by                       NUMBER,
    upd_date                     DATE,
    CONSTRAINT chk_hr_promo_policy_active CHECK (is_active IN ('Y', 'N')),
    CONSTRAINT chk_hr_promo_policy_limit CHECK (max_accelerated_promotions >= 0),
    CONSTRAINT chk_hr_promo_policy_dates CHECK
        (effective_to IS NULL OR effective_to >= effective_from)
);

INSERT INTO hr_promotion_policy
            (policy_code,
             policy_name,
             max_accelerated_promotions,
             remarks)
     SELECT 'DEFAULT',
            'Default Promotion Policy',
            2,
            'Accelerated promotion is allowed maximum two times in whole service career.'
       FROM dual
      WHERE NOT EXISTS
                (SELECT 1
                   FROM hr_promotion_policy
                  WHERE policy_code = 'DEFAULT');

