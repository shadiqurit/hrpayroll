/*
  Install or update the two grade-based promotion-letter templates.

  PROMOTION_EN : promoted grade order 1-14
  PROMOTION_BN : promoted grade order 15-20

  BODY_TEMPLATE contains narrative only. Salary amounts are never saved in the
  template or HR_EMPLOYEE_LETTER.BODY_HTML. Page 483 replaces the
  #SALARY_DETAILS# marker with a borderless promoted-salary breakdown,
  including earning salary heads 025 and 026.

  No COMMIT is included. Review and commit through the deployment transaction.
*/

MERGE INTO hr_letter_template t
USING (
    SELECT 'PROMOTION_EN' AS template_code,
           'Promotion Letter - English (Grade 1-14)' AS template_name,
           'PROMOTION' AS action_type,
           'Promotion' AS subject_template,
           TO_CLOB(q'~<p>Dear #EMP_NAME#,</p>
<p>We are pleased to inform you that the management of #COMPANY_NAME# has promoted you from <strong>#OLD_DESIGNATION#</strong> to <strong>#NEW_DESIGNATION#</strong> in the <strong>#DEPARTMENT#</strong> Department. This decision will take effect from <strong>#EFFECTIVE_DATE#</strong>.</p>
<p>You will now receive salary and allowances under IPI Service Rule Grade <strong>#GRADE#</strong> (<strong>#PAY_SCALE# Taka pay scale</strong>).</p>
<p>The details of your revised monthly salary and allowances are given below:</p>
#SALARY_DETAILS#
<p>For the needs of the company, you may be assigned at any time to work at any place within the scope of the company&rsquo;s operations.</p>
<p>We congratulate you and wish you continued success in your new role.</p>
<p>Yours sincerely,</p>~') AS body_template
      FROM dual
) s
ON (t.template_code = s.template_code)
WHEN MATCHED THEN
    UPDATE SET t.template_name     = s.template_name,
               t.action_type      = s.action_type,
               t.subject_template = s.subject_template,
               t.body_template    = s.body_template,
               t.is_active        = 'Y',
               t.upd_date         = SYSDATE
WHEN NOT MATCHED THEN
    INSERT (
        template_code, template_name, action_type, subject_template,
        body_template, is_active, ent_date
    ) VALUES (
        s.template_code, s.template_name, s.action_type, s.subject_template,
        s.body_template, 'Y', SYSDATE
    );

MERGE INTO hr_letter_template t
USING (
    SELECT 'PROMOTION_BN' AS template_code,
           'Promotion Letter - Bengali (Grade 15-20)' AS template_name,
           'PROMOTION' AS action_type,
           'পদোন্নতি।' AS subject_template,
           TO_CLOB(q'~<p>জনাব,<br>আস্সালামু আলাইকুম ওয়া রাহমাতুল্লাহ।</p>
<p>আমরা আনন্দের সাথে জানাচ্ছি যে, #COMPANY_NAME_BN#-এর ব্যবস্থাপনা কর্তৃপক্ষ আপনাকে <strong>#DEPARTMENT#</strong> বিভাগে <strong>#NEW_DESIGNATION#</strong> পদে পদোন্নতি প্রদান করেছেন। কর্তৃপক্ষের এ সিদ্ধান্ত <strong>#EFFECTIVE_DATE_BN#</strong> তারিখ থেকে কার্যকর হিসেবে গণ্য হবে। এখন থেকে আপনি আইপিআই সার্ভিস রুলের <strong>#GRADE_BN#</strong> নং গ্রেডে (<strong>#PAY_SCALE_BN# টাকা পে-স্কেলে</strong>) বেতন-ভাতা পাবেন।</p>
<p>নিম্নে আপনার মাসিক বেতন-ভাতার বিবরণী দেয়া হলো :</p>
#SALARY_DETAILS#~')
           || TO_CLOB(q'~<p>কোম্পানির প্রয়োজনে আপনাকে যে কোন সময় কোম্পানির কাজের আওতাভুক্ত যে কোন স্থানে কর্মে নিয়োজিত করা যেতে পারে।</p>
<p>সর্বশক্তিমান আল্লাহ তা'আলা আমাদের সবাইকে নিজ নিজ দায়িত্ব ও কর্তব্য যথাযথ ভাবে পালন করার তাওফিক দান করুন। আমীন।</p>
<p>ওয়াস্সালাম।</p>~') AS body_template
      FROM dual
) s
ON (t.template_code = s.template_code)
WHEN MATCHED THEN
    UPDATE SET t.template_name     = s.template_name,
               t.action_type      = s.action_type,
               t.subject_template = s.subject_template,
               t.body_template    = s.body_template,
               t.is_active        = 'Y',
               t.upd_date         = SYSDATE
WHEN NOT MATCHED THEN
    INSERT (
        template_code, template_name, action_type, subject_template,
        body_template, is_active, ent_date
    ) VALUES (
        s.template_code, s.template_name, s.action_type, s.subject_template,
        s.body_template, 'Y', SYSDATE
    );
