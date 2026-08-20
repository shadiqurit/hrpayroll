CREATE OR REPLACE FORCE VIEW V_ACTIVE_PAY_SCALE
AS
      SELECT g.id            grade_id,
             g.grade_code,
             g.grade_name,
             g.grade_order,
             s.scale_id,
             s.revision_no,
             s.revision_name,
             s.start_basic,
             s.increment_1,
             s.steps_before_eb,
             s.eb_basic,
             s.increment_2,
             s.steps_after_eb,
             s.steps_before_eb + s.steps_after_eb AS total_increment_steps,
             s.max_basic,
             hr,
             cpf,
             PFCONT,
             CONV,
             MEDICAL,
             ALLOWANCE,
             SAF,
             s.effective_from,
             s.approved_by,
                START_BASIC
             || '-'
             || INCREMENT_1
             || 'x'
             || STEPS_BEFORE_EB
             || '-'
             || EB_BASIC
             || '-EB-'
             || INCREMENT_2
             || 'x'
             || STEPS_AFTER_EB
             || '-'
             || MAX_BASIC    AS payscale
        FROM job_grades g
             JOIN pay_scale_master s ON g.id = s.grade_id AND s.is_active = 'Y'
    ORDER BY g.grade_order;
