/*
  Oracle APEX Page 482 - PL/SQL Dynamic Content
  Region 2: Bengali confirmation letter for employee grades 15-20.

  Region Server-side Condition:
    Type: Rows returned
    SQL : SELECT 1
            FROM hr_confirmation c
           WHERE c.confirm_id = TO_NUMBER(:P482_CONFIRM_ID)
             AND c.grade_order BETWEEN 15 AND 20

  The database/application character set must support Unicode (AL32UTF8 is
  recommended) so the Bengali literals are stored and rendered correctly.
*/
DECLARE
    v_confirm_id       NUMBER;
    v_emp_id           NUMBER;
    v_grade_id           NUMBER;
    v_confirm_date     DATE;
    v_status           VARCHAR2(20);
    v_grade_order      NUMBER;
    v_emp_code         VARCHAR2(100);
    v_emp_name         VARCHAR2(300);
    v_grade            VARCHAR2(100);
    v_designation      VARCHAR2(300);
    v_department       VARCHAR2(300);
    v_department_en       VARCHAR2(300);
    v_location         VARCHAR2(300);
    v_location_code    VARCHAR2(50);
    v_scale_text       VARCHAR2(1000);
    v_total_earning    NUMBER := 0;
    v_letter_no        VARCHAR2(100);
    v_letter_date      DATE;
    v_created_date     DATE;
    v_submitted_date   DATE;
    v_approved_date    DATE;

    FUNCTION esc(p_value IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN apex_escape.html(NVL(p_value, '-'));
    END esc;

    FUNCTION bn_digits(p_value IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN TRANSLATE(p_value, '0123456789', '০১২৩৪৫৬৭৮৯');
    END bn_digits;

    FUNCTION bn_date(p_date IN DATE) RETURN VARCHAR2 IS
        /* Bengali characters can require multiple bytes in AL32UTF8. */
        v_month VARCHAR2(100);
    BEGIN
        IF p_date IS NULL THEN
            RETURN '-';
        END IF;

        v_month := CASE TO_CHAR(p_date, 'MM')
            WHEN '01' THEN 'জানুয়ারি'
            WHEN '02' THEN 'ফেব্রুয়ারি'
            WHEN '03' THEN 'মার্চ'
            WHEN '04' THEN 'এপ্রিল'
            WHEN '05' THEN 'মে'
            WHEN '06' THEN 'জুন'
            WHEN '07' THEN 'জুলাই'
            WHEN '08' THEN 'আগস্ট'
            WHEN '09' THEN 'সেপ্টেম্বর'
            WHEN '10' THEN 'অক্টোবর'
            WHEN '11' THEN 'নভেম্বর'
            WHEN '12' THEN 'ডিসেম্বর'
        END;

        RETURN bn_digits(TO_CHAR(p_date, 'DD'))
               || ' ' || v_month || ' '
               || bn_digits(TO_CHAR(p_date, 'YYYY'));
    END bn_date;

    FUNCTION bn_amount(p_amount IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN bn_digits(TO_CHAR(NVL(p_amount, 0), 'FM999G999G999G990D00'));
    END bn_amount;

    FUNCTION bn_head_name(p_head_name IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN CASE UPPER(TRIM(p_head_name))
            WHEN 'BASIC'                THEN 'মূল'
            WHEN 'BASIC SALARY'         THEN 'মূল মজূরী'
            WHEN 'HOUSE RENT'           THEN 'বাড়ি ভাড়া'
            WHEN 'HOUSE RENT ALLOWANCE' THEN 'বাড়ি ভাড়া ভাতা'
            WHEN 'MEDICAL'              THEN 'চিকিৎসা'
            WHEN 'MEDICAL ALLOWANCE'    THEN 'চিকিৎসা ভাতা'
            WHEN 'CONVEYANCE'           THEN 'যাতায়াত'
            WHEN 'CONVEYANCE ALLOWANCE' THEN 'যাতায়াত ভাতা'
            WHEN 'CO''S  CON. TO PF' THEN 'পি.এফ (কোম্পানী অংশ)'
            WHEN 'FOOD ALLOWANCE'       THEN 'খাদ্য ভাতা'
            WHEN 'SPECIAL ALLOWANCE'    THEN 'বিশেষ ভাতা'
            WHEN 'ALLOWANCE'    THEN 'অন্যান্য ভাতা'
            ELSE NVL(p_head_name, '-')
        END;
    END bn_head_name;
BEGIN
    v_confirm_id := TO_NUMBER(:P482_CONFIRM_ID);

    SELECT c.emp_id,
           c.confirm_date,
           c.status,
           c.grade_order,
           c.created_date,
           c.submitted_date,
           c.approved_date
      INTO v_emp_id,
           v_confirm_date,
           v_status,
           v_grade_order,
           v_created_date,
           v_submitted_date,
           v_approved_date
      FROM hr_confirmation c
     WHERE c.confirm_id = v_confirm_id
       AND c.grade_order BETWEEN 15 AND 20;

    SELECT NVL(v.empcode, '-'),
           NVL(TRIM(e.name_bn), NVL(v.fullname, '-')),
           NVL(v.grade, '-'),
           v.JOB_ID GRADE,
           NVL(TRIM(d.designation_bn), NVL(d.designation, NVL(v.designation, '-'))),
           NVL(TRIM(dp.dept_name_bn), NVL(dp.dept_name, NVL(v.department, '-'))),
           NVL(dp.dept_name, NVL(v.department, '-')),
           NVL(v.locationname, '-'),
           NVL(v.loccode, '-')
      INTO v_emp_code,
           v_emp_name,
           v_grade,
           v_grade_id,
           v_designation,
           v_department,
           v_department_en,
           v_location,
           v_location_code
      FROM v_emp v
      JOIN employees e ON e.id = v.emp_id
      LEFT JOIN designations d ON d.id = e.desig_id
      LEFT JOIN departments dp ON dp.id = e.dept_id
     WHERE v.emp_id = v_emp_id;

    BEGIN
        SELECT 'টাকা '
               || TRANSLATE(
                      TO_CHAR(m.start_basic, 'FM999G999G999G990'),
                      '0123456789', '০১২৩৪৫৬৭৮৯'
                  )
               || ' - '
               || TRANSLATE(
                      TO_CHAR(m.increment_1, 'FM999G999G990'),
                      '0123456789', '০১২৩৪৫৬৭৮৯'
                  )
               || ' × '
               || TRANSLATE(
                      TO_CHAR(m.steps_before_eb),
                      '0123456789', '০১২৩৪৫৬৭৮৯'
                  )
               || ' - '
               || TRANSLATE(
                      TO_CHAR(m.eb_basic, 'FM999G999G999G990'),
                      '0123456789', '০১২৩৪৫৬৭৮৯'
                  )
               || ' - '
               || TRANSLATE(
                      TO_CHAR(m.increment_2, 'FM999G999G990'),
                      '0123456789', '০১২৩৪৫৬৭৮৯'
                  )
               || ' × '
               || TRANSLATE(
                      TO_CHAR(m.steps_after_eb),
                      '0123456789', '০১২৩৪৫৬৭৮৯'
                  )
               || ' - '
               || TRANSLATE(
                      TO_CHAR(m.max_basic, 'FM999G999G999G990'),
                      '0123456789', '০১২৩৪৫৬৭৮৯'
                  )
          INTO v_scale_text
          FROM (
                SELECT p.*
                  FROM pay_scale_master p
                 WHERE p.grade_id = (
                           SELECT hc.job_id
                             FROM hr_confirmation hc
                            WHERE hc.confirm_id = v_confirm_id
                       )
                   AND NVL(p.is_active, 'Y') = 'Y'
                   AND TRUNC(v_confirm_date) >=
                       NVL(TRUNC(p.effective_from), DATE '1900-01-01')
                   AND TRUNC(v_confirm_date) <=
                       NVL(TRUNC(p.effective_to), DATE '2999-12-31')
                 ORDER BY NVL(p.effective_from, DATE '1900-01-01') DESC,
                          p.revision_no DESC
               ) m
         WHERE ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_scale_text := NULL;
    END;

    SELECT NVL(SUM(NVL(d.proposed_amount, 0)), 0)
      INTO v_total_earning
      FROM hr_confirmation_salary_dtl d
     WHERE d.confirm_id = v_confirm_id
       AND NVL(d.is_active, 'Y') = 'Y'
       AND NVL(d.show_in_letter, 'Y') = 'Y'
       AND d.head_type = 'EARNING';

    v_letter_date := NVL(v_approved_date, NVL(v_submitted_date, v_created_date));
    v_letter_no := 'HR/CONF/'
                   || TO_CHAR(NVL(v_letter_date, SYSDATE), 'YYYY')
                   || '/' || LPAD(v_confirm_id, 6, '0');

    htp.p(q'~
<div class="print-toolbar no-print">
  <button type="button" class="t-Button t-Button--hot" onclick="printBengaliConfirmation();">
    <span class="fa fa-print" aria-hidden="true"></span>
    Print Letter
  </button>
</div>
<div id="divToPrint" class="confirmation-letter bengali-letter" lang="bn">
<style>
* { box-sizing: border-box; }
.bengali-letter {
  width: 210mm;
  margin: 0 auto;
  background: #fff;
  color: #111;
  font-family: "Noto Sans Bengali", "Hind Siliguri", "SolaimanLipi",
               "Kalpurush", "Arial Unicode MS", sans-serif;
  font-size: 15px;
  line-height: 1.75;
}
.bengali-letter .letter-page {
  position: relative;
  width: 210mm;
  min-height: 297mm;
  margin: 10px auto;
  /* Keep the pre-printed company-pad header and page edges clear. */
  padding: 30mm 14mm 8mm;
  background: #fff;
}
.bengali-letter .letter-content { position: relative; z-index: 2; }
.print-toolbar { width: 210mm; margin: 10px auto; text-align: right; }
.bengali-letter .draft-watermark {
  position: absolute;
  top: 40%;
  left: 0;
  width: 100%;
  text-align: center;
  transform: rotate(-35deg);
  font-size: 58px;
  font-weight: 700;
  letter-spacing: 4px;
  color: rgba(180, 0, 0, .09);
  z-index: 10;
  pointer-events: none;
}
.bengali-letter .hr-department { margin-bottom: 8px; font-weight: 700; }
.bengali-letter .ref-row {
  display: flex;
  justify-content: space-between;
  gap: 20px;
  margin: 4px 0 20px;
}
.bengali-letter .employee-block { margin-bottom: 18px; }
.bengali-letter .employee-name { font-weight: 700; }
.bengali-letter .letter-title { margin: 18px 0 22px; font-weight: 700; }
.bengali-letter .letter-paragraph { margin: 10px 0; text-align: justify; }
.bengali-letter .terms-title { margin: 18px 0 8px; font-weight: 700; }
.bengali-letter .terms { margin: 0; padding-left: 30px; }
.bengali-letter .terms > li {
  margin-bottom: 10px;
  padding-left: 5px;
  text-align: justify;
  break-inside: avoid;
  page-break-inside: avoid;
}
.bengali-letter .salary-breakdown {
  width: auto;
  min-width: 410px;
  margin: 12px 0;
  border-collapse: collapse;
  break-inside: avoid;
  page-break-inside: avoid;
}
.bengali-letter .salary-breakdown td { padding: 3px 7px; vertical-align: top; }
.bengali-letter .salary-label { width: 220px; font-weight: 600; }
.bengali-letter .salary-colon { width: 15px; text-align: center; }
.bengali-letter .salary-amount { width: 145px; text-align: right; white-space: nowrap; }
.bengali-letter .salary-total td { border-top: 1px solid #333; font-weight: 700; }
.bengali-letter .signature-copy-row {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  gap: 30px;
  width: 100%;
  margin-top: 15px;
  break-inside: avoid;
  page-break-inside: avoid;
}
.bengali-letter .signature-block { flex: 0 0 45%; }
.bengali-letter .signature-space { height: 30px; }
.bengali-letter .signature-name { font-weight: 700; }
.bengali-letter .copy-section { flex: 0 0 48%; font-size: 11px; }
.bengali-letter .copy-section ol { margin: 4px 0 0; padding-left: 25px; }
.bengali-letter .copy-section li { margin: 0; line-height: 1.6; }
@media screen {
  .bengali-letter .letter-page { box-shadow: 0 2px 12px rgba(0,0,0,.15); }
}
@media print {
  @page {
    size: A4 portrait;
    /* Repeated on every physical company-pad page. */
   margin: 30mm 10mm 8mm 20mm;
  }
  html, body {
    width: 100% !important;
    margin: 0 !important;
    padding: 0 !important;
    background: #fff !important;
    color: #000 !important;
    -webkit-print-color-adjust: exact !important;
    print-color-adjust: exact !important;
  }
  #divToPrint,
  .confirmation-letter,
  .bengali-letter {
    display: block !important;
    width: 100% !important;
    margin: 0 !important;
    padding: 0 !important;
    background: #fff !important;
    color: #000 !important;
    font-family: "Noto Sans Bengali", "Hind Siliguri", "SolaimanLipi",
                 "Kalpurush", "Arial Unicode MS", sans-serif !important;
    font-size: 14px !important;
    line-height: 1.75 !important;
  }
  .bengali-letter .letter-page {
    width: 100% !important;
    min-height: auto !important;
    margin: 0 !important;
    /* @page supplies the repeating print clearance; avoid doubling it. */
    padding: 0 !important;
    box-shadow: none !important;
  }
  .bengali-letter .letter-content {
    position: relative !important;
    z-index: 2 !important;
    width: 100% !important;
  }
  .no-print, .print-toolbar { display: none !important; }
  .bengali-letter .draft-watermark {
    position: fixed !important;
    top: 42% !important;
    left: 0 !important;
    width: 100% !important;
    transform: rotate(-35deg) !important;
  }
  .bengali-letter .ref-row {
    display: flex !important;
    flex-direction: row !important;
    justify-content: space-between !important;
    align-items: center !important;
    width: 100% !important;
    gap: 20px !important;
  }
  .bengali-letter .letter-paragraph,
  .bengali-letter .terms > li {
    font-size: 14px !important;
    line-height: 1.75 !important;
  }
  .bengali-letter .salary-breakdown {
    display: table !important;
    width: auto !important;
    min-width: 410px !important;
    border-collapse: collapse !important;
    break-inside: avoid !important;
    page-break-inside: avoid !important;
  }
  .bengali-letter .salary-breakdown tr { display: table-row !important; }
  .bengali-letter .salary-breakdown td {
    display: table-cell !important;
    padding: 3px 7px !important;
    vertical-align: top !important;
  }
  .bengali-letter .salary-label { width: 220px !important; }
  .bengali-letter .salary-colon { width: 15px !important; text-align: center !important; }
  .bengali-letter .salary-amount {
    width: 145px !important;
    text-align: right !important;
    white-space: nowrap !important;
  }
  .bengali-letter .salary-total td {
    border-top: 1px solid #000 !important;
    font-weight: 700 !important;
  }
  .bengali-letter .signature-copy-row {
    display: flex !important;
    flex-direction: row !important;
    justify-content: space-between !important;
    align-items: flex-end !important;
    width: 100% !important;
    gap: 10px !important;
    break-inside: avoid !important;
    page-break-inside: avoid !important;
  }
  .bengali-letter .signature-block {
    display: block !important;
    flex: 0 0 45% !important;
    width: 45% !important;
    margin: 0 !important;
    padding: 0 !important;
  }
  .bengali-letter .copy-section {
    display: block !important;
    font-size: 11px;
    flex: 0 0 48% !important;
    width: 48% !important;
    margin: 0 !important;
    padding: 0 !important;
  }
  .bengali-letter p { orphans: 3; widows: 3; }
}
</style>
<div class="letter-page">
~');

    IF UPPER(NVL(v_status, '-')) = 'DRAFT' THEN
        htp.p('<div class="draft-watermark">খসড়া</div>');
    END IF;

    htp.p('<div class="letter-content">');
    htp.p('<div class="hr-department">Human Resource Department</div>');
    htp.p('<div class="ref-row">'
          || '<div><strong>REF: </strong> ' || esc(v_letter_no) || '</div>'
          || '<div><strong>তারিখ:</strong> '
          || esc(bn_date(NVL(v_letter_date, SYSDATE))) || '</div>'
          || '</div>');

    htp.p('<div class="employee-block">'
          || '<div class="employee-name">' || esc(v_emp_name) || '</div>'
          || '<div>স্টাফ আইডি: ' || esc(v_emp_code) || '</div>'
          || '<div>' || esc(v_designation) || '</div>'
          || '<div>' || esc(v_department) || '</div>'
          || '<div>' || esc(v_location) || '</div>'
          || '</div>');

    htp.p('<div class="letter-title">বিষয়: চাকরি স্থায়ীকরণ প্রসঙ্গে।</div>');
    htp.p(q'~
<p class="letter-paragraph">
  জনাব,<br>
  আসসালামু আলাইকুম ওয়া রাহমাতুল্লাহ।
</p>
~');

    htp.p('<p class="letter-paragraph">'
          || 'দি ইবনে সিনা ফার্মাসিউটিক্যাল ইন্ডাস্ট্রি পিএলসি (আইপিআই)-এর '
          || 'কর্তৃপক্ষ আনন্দের সঙ্গে জানাচ্ছে যে, '
          || '<strong>' || esc(bn_date(v_confirm_date)) || '</strong> তারিখ হতে '
          || '<strong>' || esc(v_designation) || '</strong> পদে আপনার চাকরি '
          || 'নিম্নোক্ত শর্তাবলি সাপেক্ষে স্থায়ী করা হলো।'
          || '</p>');

    htp.p('<div class="terms-title">শর্তাবলিঃ </div>');
    htp.p('<ol class="terms" style="list-style-type: bengali;">');
    htp.p('<li>আপনাকে আইপিআই বেতন স্কেলের গ্রেড  '|| esc(bn_digits(v_grade_id)) ||' <strong>('
          || esc((v_grade)) || ') </strong> ');

    IF v_scale_text IS NOT NULL THEN
        htp.p(' (' || esc(v_scale_text) || ')');
    END IF;

    htp.p(' অনুযায়ী মাসিক বেতন প্রদান করা হবে। আপনার বেতনের বিবরণ নিম্নরূপ:');
    htp.p('<table class="salary-breakdown">');

    FOR r IN (
        SELECT d.head_name,
               d.proposed_amount,
               d.display_order,
               d.slno
          FROM hr_confirmation_salary_dtl d
         WHERE d.confirm_id = v_confirm_id
           AND NVL(d.is_active, 'Y') = 'Y'
           AND NVL(d.show_in_letter, 'Y') = 'Y'
           AND d.head_type = 'EARNING'
           AND NVL(d.proposed_amount, 0) <> 0
         ORDER BY NVL(d.display_order, d.slno), d.slno
    ) LOOP
        htp.p('<tr>'
              || '<td class="salary-label">' || esc(bn_head_name(r.head_name)) || '</td>'
              || '<td class="salary-colon">:</td>'
              || '<td class="salary-amount">' || esc(bn_amount(r.proposed_amount)) || '</td>'
              || '</tr>');
    END LOOP;

    htp.p('<tr class="salary-total">'
          || '<td>মোট</td><td class="salary-colon">:</td>'
          || '<td class="salary-amount">' || esc(bn_amount(v_total_earning)) || '</td>'
          || '</tr></table></li>');

    htp.p(q'~
<li>কোম্পানির প্রচলিত নীতিমালা অনুযায়ী আপনি বিধিবদ্ধ ছুটি ও অন্যান্য ছুটির সুবিধা ভোগ করবেন ;</li>
<li>কর্তৃপক্ষের প্রয়োজনে আপনাকে কোম্পানির কার্যপরিধির অন্তর্ভুক্ত যেকোনো স্থানে এবং যেকোনো কাজের দায়িত্ব প্রদান করা যেতে পারে ;</li>
<li>আপনি প্রতি বছর মূল মজূরীর সমপরিমাণ ০২ (দুই)টি উৎসব বোনাস প্রাপ্য হবেন ;</li>
<li>আপনি কোম্পানির কর্মচারী ভবিষ্য তহবিলের সদস্য হিসেবে অন্তর্ভুক্ত হবেন এবং প্রচলিত বিধি অনুযায়ী এর সুবিধা প্রাপ্য হবেন ;</li>
<li>কোম্পানির প্রচলিত বিধি অনুযায়ী আপনি কর্মচারী গ্র্যাচুইটি তহবিলের সুবিধা প্রাপ্য হবেন ;</li>
<li>আপনি কোম্পানির সুপারঅ্যানুয়েশন তহবিলের সদস্য হিসেবে অন্তর্ভুক্ত হবেন এবং প্রচলিত বিধি অনুযায়ী এর সুবিধা প্রাপ্য হবেন ;</li>
<li>আপনি প্রতি বছর কোম্পানির মুনাফা অংশগ্রহণ তহবিল (WPPF) থেকে আনুপাতিক হারে লভ্যাংশ প্রাপ্য হবেন ;</li>
<li>আপনি চাকরি থেকে পদত্যাগ করলে অথবা কোম্পানি আপনার চাকরির অবসান ঘটালে, সংশ্লিষ্ট পক্ষকে চাকরিবিধি অনুযায়ী নোটিশ প্রদান করতে হবে অথবা মূল মজূরীর ভিত্তিতে নোটিশের পরিবর্তে অর্থ প্রদান করতে হবে ;</li>
<li>আপনি কোম্পানির বর্তমানে প্রচলিত এবং পরিচালনা পর্ষদ কর্তৃক সময়ে সময়ে সংশোধিত সকল নিয়মকানুন মেনে চলতে বাধ্য থাকবেন।</li>
</ol>
<p class="letter-paragraph" style="margin-top:30px;">
  মহান আল্লাহ আমাদের সবাইকে নিজ নিজ দায়িত্ব ও কর্তব্য সর্বোত্তমভাবে পালনের তৌফিক দান করুন।
</p>
<p class="letter-paragraph" style="margin-top:25px;">মা'আসসালাম।</p>
<div class="signature-copy-row">
  <div class="signature-block">
    <div class="signature-space"></div>
~');

    IF UPPER(TRIM(v_location_code)) = 'HO' THEN
        htp.p(q'~
    <div class="signature-name">প্রফেসর ডা. এ. কে. এম. সদরুল ইসলাম</div>
    <div>ব্যবস্থাপনা পরিচালক</div>
~');
    ELSIF UPPER(TRIM(v_location_code)) = 'FAC' THEN
        htp.p(q'~
    <div class="signature-name">মোঃ কবির হোসেন</div>
    <div>নির্বাহী পরিচালক (প্ল্যান্টস)</div>
~');
    ELSE
        htp.p(q'~
    <div class="signature-name">মোঃ ইয়ানুর রহমান</div>
    <div>নির্বাহী পরিচালক (প্রশাসন)</div>
~');
    END IF;

    htp.p(q'~
  </div>
  <div class="copy-section">
    <strong>অনুলিপি:</strong>
    <ol>
~');

    IF UPPER(TRIM(v_location_code)) = 'FAC' THEN
        htp.p(q'~
      <li>নির্বাহী পরিচালক ও প্ল্যান্টস প্রধান</li>
      <li>সংশ্লিষ্ট বিভাগীয় প্রধান</li>
      <li>মানবসম্পদ বিভাগ (প্ল্যান্টস)</li>
      <li>হিসাব বিভাগ</li>
      <li>ব্যক্তিগত নথি</li>
      <li>অফিস কপি</li>
~');
    ELSIF UPPER(TRIM(v_location_code)) = 'HO' THEN
        htp.p(q'~
      <li>বিভাগীয় প্রধান</li>
      <li>হিসাব বিভাগ</li>
      <li>ব্যক্তিগত নথি</li>
      <li>অফিস কপি</li>
~');
    ELSIF UPPER(TRIM(v_department)) = 'SALES' THEN
        htp.p(q'~
      <li>বিক্রয় বিভাগীয় প্রধান</li>
      <li>গ্রুপ লিডার</li>
      <li>হিসাব বিভাগ</li>
      <li>ব্যক্তিগত নথি</li>
      <li>অফিস কপি</li>
~');
    ELSE
        htp.p(q'~
      <li>সংশ্লিষ্ট বিভাগীয় প্রধান</li>
      <li>হিসাব বিভাগ</li>
      <li>ব্যক্তিগত নথি</li>
      <li>অফিস কপি</li>
~');
    END IF;

    htp.p(q'~
    </ol>
  </div>
</div>
</div>
</div>
</div>
~');

    /* Print only the letter in a clean window so APEX theme CSS and page
       regions cannot change its layout. The style element inside divToPrint
       is copied with the letter. */
    htp.p(q'~
<script>
function printBengaliConfirmation() {
  var letter = document.getElementById('divToPrint');

  if (!letter) {
    return;
  }

  var printWindow = window.open('', '_blank', 'width=1000,height=800');

  if (!printWindow) {
    window.print();
    return;
  }

  printWindow.document.open();
  printWindow.document.write(
    '<!doctype html>' +
    '<html lang="bn"><head><meta charset="UTF-8">' +
    '<meta name="viewport" content="width=device-width,initial-scale=1">' +
    '<title>নিশ্চিতকরণ পত্র</title></head><body>' +
    letter.outerHTML +
    '</body></html>'
  );
  printWindow.document.close();

  var startPrint = function () {
    window.setTimeout(function () {
      printWindow.focus();
      printWindow.print();
    }, 250);
  };

  printWindow.onafterprint = function () {
    printWindow.close();
  };

  if (printWindow.document.fonts && printWindow.document.fonts.ready) {
    printWindow.document.fonts.ready.then(startPrint, startPrint);
  } else {
    startPrint();
  }
}
</script>
~');
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        htp.p(q'~
<div class="t-Alert t-Alert--danger t-Alert--defaultIcons">
  <div class="t-Alert-wrap"><div class="t-Alert-content">
    <div class="t-Alert-header"><h2 class="t-Alert-title">
      ১৫-২০ গ্রেডের নিশ্চিতকরণ তথ্য পাওয়া যায়নি।
    </h2></div>
  </div></div>
</div>
~');
    WHEN VALUE_ERROR THEN
        htp.p('<div class="t-Alert t-Alert--danger t-Alert--defaultIcons">'
              || '<div class="t-Alert-wrap"><div class="t-Alert-content">'
              || '<div class="t-Alert-header"><h2 class="t-Alert-title">'
              || 'তথ্যের মান অথবা দৈর্ঘ্যে সমস্যা হয়েছে: '
              || apex_escape.html(SQLERRM)
              || '</h2></div></div></div></div>');
    WHEN OTHERS THEN
        htp.p('<div class="t-Alert t-Alert--danger t-Alert--defaultIcons">'
              || '<div class="t-Alert-wrap"><div class="t-Alert-content">'
              || '<div class="t-Alert-header"><h2 class="t-Alert-title">'
              || apex_escape.html(SQLERRM)
              || '</h2></div></div></div></div>');
END;
