/*
  Oracle APEX Page 503
  Region Type : PL/SQL Dynamic Content
  Purpose     : Print one or all Salary Done (POSTED) increment letters.

  Required/protected page items:
    P503_COM_ID          NUMBER, required
    P503_SALARY_MONTH    NUMBER(6), required, for example 202608
    P503_INCREMENT_ID    NUMBER, optional (one letter when supplied)

  Use a Printer Friendly / Minimal page template. The company name/address are
  selected from COMPANY through P503_COM_ID, and the logo is loaded from the
  application's supplied static-file URL. The print stylesheet isolates the
  letter and hides the APEX header, navigation, breadcrumbs, page title,
  footer, region chrome and print toolbar.
*/

DECLARE
    c_logo_url       CONSTANT VARCHAR2(4000) :=
        'http://10.30.25.8:9001/ords/hrm/r/103/files/static/v82/ipi.png';
    l_letter_count  PLS_INTEGER := 0;
    l_total_letters PLS_INTEGER := 0;
    l_salary_rows   PLS_INTEGER;
    l_arrear_months PLS_INTEGER;
    l_arrear_days   PLS_INTEGER;
    l_arrear_amount NUMBER;
    l_month_start   DATE;
    l_next_month    DATE;
    l_is_bengali    BOOLEAN := FALSE;

    FUNCTION esc(p_text IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN apex_escape.html(NVL(p_text, ''));
    END esc;

    FUNCTION shown(p_text IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN apex_escape.html(NVL(TRIM(p_text), '-'));
    END shown;

    FUNCTION money(p_amount IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(
            ROUND(NVL(p_amount, 0)),
            'FM999G999G999G999G990',
            'NLS_NUMERIC_CHARACTERS=''.,'''
        );
    END money;

    FUNCTION bn_digits(p_value IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN TRANSLATE(p_value, '0123456789', '০১২৩৪৫৬৭৮৯');
    END bn_digits;

    FUNCTION display_money(p_amount IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        IF l_is_bengali THEN
            RETURN bn_digits(money(p_amount));
        END IF;
        RETURN money(p_amount);
    END display_money;

    FUNCTION display_date(p_date IN DATE) RETURN VARCHAR2 IS
    BEGIN
        IF p_date IS NULL THEN
            RETURN '-';
        ELSIF l_is_bengali THEN
            RETURN bn_digits(TO_CHAR(p_date, 'DD.MM.YYYY')) || ' খ্রি.';
        END IF;

        RETURN TO_CHAR(
            p_date,
            'DD-MON-RR',
            'NLS_DATE_LANGUAGE=English'
        );
    END display_date;

    FUNCTION bn_head_name(
        p_headcode IN VARCHAR2,
        p_head_name IN VARCHAR2
    ) RETURN VARCHAR2 IS
        l_code VARCHAR2(3) := LPAD(TRIM(p_headcode), 3, '0');
        l_name VARCHAR2(100) := UPPER(TRIM(p_head_name));
    BEGIN
        RETURN CASE l_code
            WHEN '001' THEN 'মূল বেতন'
            WHEN '005' THEN 'বাড়ি ভাড়া ভাতা'
            WHEN '007' THEN 'যাতায়াত ভাতা'
            WHEN '010' THEN 'চিকিৎসা ভাতা'
            WHEN '013' THEN 'পি.এফ (কোম্পানির অংশ)'
            WHEN '025' THEN 'অন্যান্য ভাতা'
            WHEN '026' THEN 'বিশেষ অর্জন ভাতা'
            WHEN '057' THEN 'পি.এফ (কর্মচারীর অংশ)'
            ELSE CASE l_name
                WHEN 'BASIC'                THEN 'মূল বেতন'
                WHEN 'BASIC SALARY'         THEN 'মূল বেতন'
                WHEN 'HOUSE RENT'           THEN 'বাড়ি ভাড়া ভাতা'
                WHEN 'HOUSE RENT ALLOWANCE' THEN 'বাড়ি ভাড়া ভাতা'
                WHEN 'CONVEYANCE'           THEN 'যাতায়াত ভাতা'
                WHEN 'CONVEYANCE ALLOWANCE' THEN 'যাতায়াত ভাতা'
                WHEN 'MEDICAL'              THEN 'চিকিৎসা ভাতা'
                WHEN 'MEDICAL ALLOWANCE'    THEN 'চিকিৎসা ভাতা'
                WHEN 'FOOD ALLOWANCE'       THEN 'খাদ্য ভাতা'
                WHEN 'SPECIAL ALLOWANCE'    THEN 'বিশেষ ভাতা'
                WHEN 'OTHER ALLOWANCE'      THEN 'অন্যান্য ভাতা'
                ELSE NVL(p_head_name, p_headcode)
            END
        END;
    END bn_head_name;
BEGIN
    IF :P503_COM_ID IS NULL OR :P503_SALARY_MONTH IS NULL THEN
        htp.p('<div class="t-Alert t-Alert--warning">Company and salary month are required.</div>');
        RETURN;
    END IF;

    SELECT COUNT(*)
      INTO l_total_letters
      FROM hr_employee_increment i
     WHERE i.status = 'POSTED'
       AND i.com_id = TO_NUMBER(:P503_COM_ID)
       AND i.salary_month = TO_NUMBER(:P503_SALARY_MONTH)
       AND (
           :P503_INCREMENT_ID IS NULL
           OR i.increment_id = TO_NUMBER(:P503_INCREMENT_ID)
       );

    htp.p(q'~
<div id="increment-letter-print-root">
<style>
  * { box-sizing: border-box; }
  #increment-letter-print-root {
    color: #050505; font-family: Arial, Helvetica, sans-serif;
  }
  .inc-print-toolbar {
    width: 210mm; margin: 0 auto 12px; text-align: right;
  }
  .inc-print-button {
    border: 0; border-radius: 4px; padding: 9px 18px;
    background: #1f5f99; color: #fff; font-weight: 700; cursor: pointer;
  }
  .increment-letter-page {
    position: relative; width: 210mm; min-height: 297mm;
    margin: 0 auto 18px; padding: 20px 10mm 22mm;
    background: #fff; border: 1px solid #d6d6d6;
    box-shadow: 0 3px 16px rgba(0,0,0,.10);
    font-size: 11.5px; line-height: 1.28;
    break-after: page; page-break-after: always;
  }
  .increment-letter-page:last-of-type {
    break-after: auto; page-break-after: auto;
  }
  .increment-letter-page.bn {
    font-family: "Noto Sans Bengali", "Hind Siliguri", "SolaimanLipi",
                 "Kalpurush", "Arial Unicode MS", sans-serif;
    font-size: 12px; line-height: 1.38;
  }
  .bn .company-name { font-family: Arial, Helvetica, sans-serif; }
  .bn .employee-lines, .bn .letter-greeting, .bn .letter-body,
  .bn .allowance-lead, .bn .blessing, .bn .closing { font-size: 12px; }
  .bn .salary-table { font-size: 10.5px; }
  .bn .salary-table thead th { font-size: 11px; }
  .company-letterhead {
    display: grid; grid-template-columns: 23mm 1fr;
    gap: 4mm; align-items: center; min-height: 19mm;
    padding-bottom: 2.5mm; border-bottom: 1px solid #111;
  }
  .letter-logo {
    display: block; width: 20mm; height: 20mm;
    object-fit: contain;
  }
  .company-name {
    margin: 0; font-size: 20px; line-height: 1.08; font-weight: 800;
  }
  .company-address {
    margin-top: 1.5mm; font-size: 10px; line-height: 1.2; font-weight: 700;
  }
  .reference-row {
    display: grid; grid-template-columns: 1fr 68mm;
    gap: 12mm; margin-top: 3mm; font-size: 11px;
  }
  .reference-date { display: flex; justify-content: space-between; gap: 5mm; }
  .recipient-area {
    display: grid; grid-template-columns: 1fr 47mm;
    gap: 12mm; margin-top: 6mm;
  }
  .recipient-title { margin-bottom: 2mm; font-size: 12px; font-weight: 800; }
  .employee-lines {
    display: grid; grid-template-columns: 39mm 5mm 1fr;
    font-size: 11.5px; font-weight: 700; line-height: 1.25;
  }
  .employee-lines .label { font-weight: 800; }
  .copy-title { padding-bottom: 1mm; border-bottom: 1px solid #222; font-size: 11px; }
  .copy-list { margin: 2mm 0 0; padding-left: 8mm; font-size: 10.5px; line-height: 1.45; }
  .letter-subject { margin: 8mm 0 5mm; font-size: 12px; font-weight: 800; }
  .letter-greeting, .letter-body, .allowance-lead, .blessing, .closing {
    margin: 0 0 4mm; font-size: 11.5px;
  }
  .letter-body { text-align: justify; }
  .salary-table {
    width: 100%; margin: 2mm 0 3mm; border-collapse: collapse;
    table-layout: fixed; font-size: 10px; line-height: 1.1;
    break-inside: avoid; page-break-inside: avoid;
  }
  .salary-table th, .salary-table td { border: 1px solid #111; padding: 1.2mm 1.5mm; }
  .salary-table thead th { background: #e9e9e9; text-align: center; font-size: 10.5px; }
  .salary-table .sl { width: 16mm; text-align: center; }
  .salary-table .amount { width: 37mm; text-align: right; white-space: nowrap; }
  .salary-table .gross-label, .salary-table .gross-amount { background: #e9e9e9; font-weight: 800; }
  .arrear-box {
    margin-top: 3mm; padding: 1.5mm 2mm 2mm; border: 1px solid #111;
    font-size: 9.5px; break-inside: avoid; page-break-inside: avoid;
  }
  .arrear-title { margin-bottom: 1mm; font-size: 11px; font-weight: 800; }
  .arrear-subtitle { width: 75mm; margin-left: 6mm; padding-bottom: .7mm; border-bottom: 1px solid #222; font-weight: 800; }
  .arrear-lines { display: grid; grid-template-columns: 31mm 5mm 1fr; margin: 1mm 0 0 14mm; }
  .letter-footer {
    position: absolute; left: 13mm; right: 13mm; bottom: 7mm;
    font-size: 8.8px;
  }
  .system-note { padding-top: 2mm; border-top: 1px solid #111; }
  .page-number { margin-top: 5mm; text-align: center; }
  .no-letters { max-width: 210mm; margin: 0 auto; padding: 20px; border: 1px solid #ddd; background: #fafafa; }

  @page { size: A4 portrait; margin: 0 !important; }
  @media print {
    html, body {
      margin: 0 !important; padding: 0 !important;
      background: #fff !important; overflow: visible !important;
    }
    body * { visibility: hidden !important; }
    #increment-letter-print-root,
    #increment-letter-print-root * { visibility: visible !important; }
    #increment-letter-print-root {
      position: absolute; left: 0; top: 0; width: 100%; margin: 0;
    }
    .t-Header, .t-Body-nav, .t-Body-title, .t-BreadcrumbRegion,
    .t-Footer, .t-Region-header, .t-Region-buttons, .inc-print-toolbar {
      display: none !important;
    }
    .increment-letter-page {
      width: 210mm; height: 297mm; min-height: 297mm;
      margin: 0; padding: 20px 10mm 22mm;
      border: 0; box-shadow: none;
      -webkit-print-color-adjust: exact; print-color-adjust: exact;
    }
    .salary-table, .arrear-box { break-inside: avoid; page-break-inside: avoid; }
  }
</style>
<div class="inc-print-toolbar">
~');

    IF :P503_INCREMENT_ID IS NULL THEN
        htp.p('<button type="button" class="inc-print-button" onclick="printIncrementLetters();">Print All Increment Letters</button>');
    ELSE
        htp.p('<button type="button" class="inc-print-button" onclick="printIncrementLetters();">Print Increment Letter</button>');
    END IF;

    htp.p('</div>');

    FOR r IN (
        SELECT i.increment_id,
               i.action_id,
               i.salary_month,
               i.current_list_date,
               i.due_date,
               NVL(i.revised_effective_date, i.effective_date) AS payable_effective_date,
               i.old_basic,
               i.proposed_basic AS new_basic,
               i.old_gross,
               i.proposed_gross AS new_gross,
               i.increment_amount,
               i.from_step_no,
               i.to_step_no,
               i.total_steps,
               i.posted_date,
               i.emp_id AS employee_pk,
               e.emp_id AS employee_id,
               NVL(e.empno, e.emp_id) AS employee_code,
               TRIM(e.f_name || ' ' || e.l_name) AS employee_name,
               d.designation,
               dp.dept_name,
               loc.name AS location_name,
               c.code AS company_code,
               c.name AS company_name,
               c.address AS company_address,
               c.phone AS company_phone,
               c.email AS company_email,
               ps.start_basic,
               ps.increment_1,
               ps.steps_before_eb,
               ps.eb_basic,
               ps.increment_2,
               ps.steps_after_eb,
               ps.max_basic,
               NVL(g.grade_code, g.grade_name) AS grade_name,
               g.grade_order,
               NVL(
                   l.letter_no,
                   'INC-' || TO_CHAR(i.salary_month) || '-' || TO_CHAR(i.increment_id)
               ) AS letter_no
          FROM hr_employee_increment i
               JOIN employees e ON e.id = i.emp_id
               JOIN company c ON c.id = i.com_id
               LEFT JOIN designations d ON d.id = e.desig_id
               LEFT JOIN departments dp ON dp.id = e.dept_id
               LEFT JOIN locations loc ON loc.id = e.loc_id
               LEFT JOIN pay_scale_master ps ON ps.scale_id = i.scale_id
               LEFT JOIN job_grades g ON g.id = ps.grade_id
               LEFT JOIN (
                   SELECT action_id,
                          MAX(letter_no) KEEP (DENSE_RANK LAST ORDER BY letter_id) AS letter_no
                     FROM hr_employee_letter
                    WHERE status <> 'CANCELLED'
                    GROUP BY action_id
               ) l ON l.action_id = i.action_id
         WHERE i.status = 'POSTED'
           AND i.com_id = TO_NUMBER(:P503_COM_ID)
           AND i.salary_month = TO_NUMBER(:P503_SALARY_MONTH)
           AND (
               :P503_INCREMENT_ID IS NULL
               OR i.increment_id = TO_NUMBER(:P503_INCREMENT_ID)
           )
         ORDER BY e.emp_id, i.increment_id
    ) LOOP
        l_letter_count := l_letter_count + 1;
        l_is_bengali := r.grade_order BETWEEN 15 AND 20;

        l_month_start := TRUNC(r.current_list_date, 'MM');
        l_arrear_months := 0;
        l_arrear_days := 0;
        l_arrear_amount := 0;

        IF TRUNC(r.payable_effective_date) < l_month_start THEN
            IF TRUNC(r.payable_effective_date) = TRUNC(r.payable_effective_date, 'MM') THEN
                l_arrear_months := GREATEST(
                    TRUNC(MONTHS_BETWEEN(l_month_start, TRUNC(r.payable_effective_date))),
                    0
                );
            ELSE
                l_next_month := ADD_MONTHS(TRUNC(r.payable_effective_date, 'MM'), 1);
                l_arrear_months := GREATEST(
                    TRUNC(MONTHS_BETWEEN(l_month_start, l_next_month)),
                    0
                );
                l_arrear_days := GREATEST(l_next_month - TRUNC(r.payable_effective_date), 0);
            END IF;

            l_arrear_amount := ROUND(
                GREATEST(NVL(r.new_gross, 0) - NVL(r.old_gross, 0), 0)
                * l_arrear_months
                + GREATEST(NVL(r.new_gross, 0) - NVL(r.old_gross, 0), 0)
                  * l_arrear_days
                  / TO_NUMBER(TO_CHAR(LAST_DAY(r.payable_effective_date), 'DD'))
            );
        END IF;

        htp.p('<section class="increment-letter-page '
              || CASE WHEN l_is_bengali THEN 'bn' ELSE 'en' END
              || '" lang="' || CASE WHEN l_is_bengali THEN 'bn' ELSE 'en' END
              || '">');
        htp.p('<header class="company-letterhead">');
        htp.p('<img class="letter-logo" src="'
              || apex_escape.html_attribute(c_logo_url)
              || '" alt="' || CASE WHEN l_is_bengali THEN 'কোম্পানির লোগো' ELSE 'Company logo' END || '">');
        htp.p('<div><h1 class="company-name">' || shown(r.company_name) || '</h1>');
        htp.p('<div class="company-address">' || shown(r.company_address) || '</div></div>');
        htp.p('</header>');

        htp.p('<div class="reference-row"><div>'
              || CASE WHEN l_is_bengali THEN 'সূত্র নং' ELSE 'Ref. No' END
              || '&nbsp;&nbsp;' || shown(CASE WHEN l_is_bengali
                                             THEN bn_digits(r.letter_no)
                                             ELSE r.letter_no END)
              || '</div><div class="reference-date"><span>'
              || CASE WHEN l_is_bengali THEN 'তারিখ' ELSE 'Date' END
              || '</span><span>' || display_date(r.payable_effective_date)
              || '</span></div></div>');

        htp.p('<div class="recipient-area"><div>');
        htp.p('<div class="recipient-title">'
              || CASE WHEN l_is_bengali THEN 'প্রতি :' ELSE 'To :' END
              || '</div><div class="employee-lines">');
        htp.p('<div class="label">' || CASE WHEN l_is_bengali THEN 'নাম' ELSE 'Name' END
              || '</div><div>:</div><div>'
              || shown(CASE WHEN l_is_bengali THEN r.employee_name ELSE UPPER(r.employee_name) END)
              || '</div>');
        htp.p('<div class="label">' || CASE WHEN l_is_bengali THEN 'পদবী' ELSE 'Designation' END
              || '</div><div>:</div><div>'
              || shown(CASE WHEN l_is_bengali THEN r.designation ELSE UPPER(r.designation) END)
              || '</div>');
        htp.p('<div class="label">' || CASE WHEN l_is_bengali THEN 'কর্মচারী আইডি' ELSE 'Employee ID' END
              || '</div><div>:</div><div>' || shown(CASE WHEN l_is_bengali
                                                        THEN bn_digits(r.employee_id)
                                                        ELSE r.employee_id END) || '</div>');
        htp.p('<div class="label">' || CASE WHEN l_is_bengali THEN 'কর্মচারী কোড' ELSE 'Employee Code' END
              || '</div><div>:</div><div>' || shown(CASE WHEN l_is_bengali
                                                        THEN bn_digits(r.employee_code)
                                                        ELSE r.employee_code END) || '</div>');
        htp.p('<div class="label">' || CASE WHEN l_is_bengali THEN 'বিভাগ' ELSE 'Department' END
              || '</div><div>:</div><div>' || shown(r.dept_name) || '</div>');
        htp.p('<div class="label">' || CASE WHEN l_is_bengali THEN 'কর্মস্থল' ELSE 'Location' END
              || '</div><div>:</div><div>' || shown(r.location_name) || '</div>');
        htp.p('</div></div><aside><div class="copy-title">'
              || CASE WHEN l_is_bengali THEN 'অনুলিপি:' ELSE 'Copy to:' END || '</div>');
        htp.p('<ol class="copy-list"><li>'
              || CASE WHEN l_is_bengali THEN 'ব্যক্তিগত নথি' ELSE 'Personal File' END
              || '</li><li>'
              || CASE WHEN l_is_bengali THEN 'বেতন বিভাগ' ELSE 'Payroll Section' END
              || '</li></ol></aside></div>');

        IF l_is_bengali THEN
            htp.p('<div class="letter-subject">বিষয় :&nbsp; বার্ষিক বেতন বৃদ্ধি পত্র</div>');
            htp.p('<p class="letter-greeting">জনাব,</p>');
            htp.p('<p class="letter-greeting">আসসালামু আলাইকুম ওয়া রাহমাতুল্লাহ।</p>');
            htp.p('<p class="letter-body">' || shown(r.company_name)
                  || '-এর ব্যবস্থাপনা কর্তৃপক্ষ আনন্দের সঙ্গে জানাচ্ছে যে, <strong>'
                  || display_date(r.payable_effective_date)
                  || '</strong> তারিখ থেকে আপনাকে ১ (এক)টি নিয়মিত বার্ষিক বেতন বৃদ্ধি মঞ্জুর করা হয়েছে। '
                  || 'এ বৃদ্ধির পরিমাণ <strong>' || display_money(r.increment_amount)
                  || ' টাকা</strong> এবং বেতন বৃদ্ধির পর আপনার মূল বেতন <strong>'
                  || display_money(r.new_basic) || ' টাকা</strong> নির্ধারণ করা হলো। '
                  || 'আপনার বেতন স্কেল <strong>'
                  || display_money(r.start_basic) || '-' || display_money(r.increment_1)
                  || 'x' || bn_digits(TO_CHAR(r.steps_before_eb)) || '-'
                  || display_money(r.eb_basic) || '-ইবি-' || display_money(r.increment_2)
                  || 'x' || bn_digits(TO_CHAR(r.steps_after_eb)) || '-'
                  || display_money(r.max_basic) || ' টাকা</strong> এবং গ্রেড <strong>'
                  || shown(bn_digits(r.grade_name)) || '</strong>।</p>');
            htp.p('<p class="allowance-lead">আপনার বেতন ও ভাতাদির বিবরণ নিম্নরূপ :</p>');
            htp.p('<table class="salary-table"><thead><tr><th class="sl">ক্রমিক<br>নং</th>'
                  || '<th>বিবরণ</th><th class="amount">পূর্ববর্তী<br>টাকা</th>'
                  || '<th class="amount">বেতন বৃদ্ধির পর<br>টাকা</th></tr></thead><tbody>');
        ELSE
            htp.p('<div class="letter-subject">Subject :&nbsp; Increment Letter</div>');
            htp.p('<p class="letter-greeting">Mohtaram,</p>');
            htp.p('<p class="letter-greeting">Assalamu Alaikum Wa-Rahmatullah.</p>');
            htp.p('<p class="letter-body">The Management of ' || shown(r.company_name)
                  || ' has been pleased to grant you 1 (One) Normal Increment with effect from <strong>'
                  || display_date(r.payable_effective_date)
                  || '</strong>. With an increment of Tk. <strong>' || display_money(r.increment_amount)
                  || '</strong>, your basic pay will be Tk. <strong>' || display_money(r.new_basic)
                  || '</strong> in the scale of pay <strong>'
                  || display_money(r.start_basic) || '-' || display_money(r.increment_1)
                  || 'x' || TO_CHAR(r.steps_before_eb) || '-' || display_money(r.eb_basic)
                  || '-EB-' || display_money(r.increment_2) || 'x'
                  || TO_CHAR(r.steps_after_eb) || '-' || display_money(r.max_basic)
                  || '</strong> of <strong>' || shown(r.grade_name) || '</strong>.</p>');
            htp.p('<p class="allowance-lead">Your Pay &amp; Allowances are as follows :</p>');
            htp.p('<table class="salary-table"><thead><tr><th class="sl">SL<br>No</th>'
                  || '<th>Particulars</th><th class="amount">Previous<br>Tk.</th>'
                  || '<th class="amount">On Increment<br>Tk.</th></tr></thead><tbody>');
        END IF;

        l_salary_rows := 0;
        FOR s IN (
            SELECT headcode,
                   head_name,
                   old_amount,
                   new_amount
              FROM (
                    SELECT h.headcode,
                           NVL(ah.head_name, h.headcode) AS head_name,
                           h.old_amount,
                           h.new_amount,
                           NVL(ah.print_order, h.slno) AS print_order,
                           h.slno
                      FROM emp_salary_structure_hist h
                           LEFT JOIN allowance_head ah
                             ON ah.head_id = h.slno
                     WHERE h.action_id = r.action_id
                       AND h.emp_id = r.employee_pk
                       AND NVL(ah.head_type, 'EARNING') = 'EARNING'

                    UNION ALL

                    /* Compatibility for increments posted before the full
                       earning snapshot was added to PR_APPLY_INCREMENT. */
                    SELECT s.headcode,
                           ah.head_name,
                           s.amount AS old_amount,
                           s.amount AS new_amount,
                           NVL(ah.print_order, s.slno) AS print_order,
                           s.slno
                      FROM emp_salary_structure s
                           JOIN allowance_head ah ON ah.head_id = s.slno
                     WHERE s.employee_id = r.employee_pk
                       AND NVL(s.is_active, 'Y') = 'Y'
                       AND ah.head_type = 'EARNING'
                       AND NOT EXISTS (
                             SELECT 1
                               FROM emp_salary_structure_hist h
                              WHERE h.action_id = r.action_id
                                AND h.emp_id = r.employee_pk
                                AND LPAD(TRIM(h.headcode), 3, '0') =
                                    LPAD(TRIM(s.headcode), 3, '0')
                           )
                   )
             WHERE NVL(old_amount, 0) <> 0 OR NVL(new_amount, 0) <> 0
             ORDER BY print_order, slno
        ) LOOP
            l_salary_rows := l_salary_rows + 1;
            htp.p('<tr><td class="sl">'
                  || CASE WHEN l_is_bengali
                          THEN bn_digits(TO_CHAR(l_salary_rows))
                          ELSE TO_CHAR(l_salary_rows) END
                  || '</td><td>'
                  || shown(CASE WHEN l_is_bengali
                                THEN bn_head_name(s.headcode, s.head_name)
                                ELSE s.head_name END)
                  || '</td><td class="amount">' || display_money(s.old_amount)
                  || '</td><td class="amount">' || display_money(s.new_amount)
                  || '</td></tr>');
        END LOOP;

        htp.p('<tr><td colspan="2" class="gross-label">'
              || CASE WHEN l_is_bengali THEN 'মোট বেতন :' ELSE 'Gross Salary :' END
              || '</td><td class="amount gross-amount">' || display_money(r.old_gross)
              || '</td><td class="amount gross-amount">' || display_money(r.new_gross)
              || '</td></tr>');
        htp.p('</tbody></table>');

        htp.p('<p class="blessing">'
              || CASE WHEN l_is_bengali
                      THEN 'মহান আল্লাহ আপনার আয়ে বরকত দান করুন এবং আপনাকে সঠিক পথে পরিচালিত করুন।'
                      ELSE 'May ALLAH give Barakat to your income and guide you in the true path.' END
              || '</p>');
        htp.p('<div class="arrear-box"><div class="arrear-title">'
              || CASE WHEN l_is_bengali THEN 'বকেয়ার বিবরণ :' ELSE 'Arrear Details :' END
              || '</div>');
        htp.p('<div class="arrear-subtitle">'
              || CASE WHEN l_is_bengali
                      THEN 'বর্তমান বেতন স্কেল অনুযায়ী :'
                      ELSE 'On Current Payscale :' END
              || '</div><div class="arrear-lines">');
        htp.p('<div>' || CASE WHEN l_is_bengali
                             THEN 'বেতন বৃদ্ধির হার'
                             ELSE 'Increment Rate' END
              || '</div><div>:</div><div>' || display_money(r.increment_1)
              || CASE WHEN l_is_bengali THEN ' , ইবি : ' ELSE ' , EB : ' END
              || display_money(r.increment_2) || '</div>');
        htp.p('<div>' || CASE WHEN l_is_bengali THEN 'সময়কাল' ELSE 'Duration' END
              || '</div><div>:</div><div>'
              || CASE WHEN l_is_bengali THEN bn_digits(TO_CHAR(l_arrear_months))
                      ELSE TO_CHAR(l_arrear_months) END
              || CASE WHEN l_is_bengali THEN ' মাস - ' ELSE ' Month - ' END
              || CASE WHEN l_is_bengali THEN bn_digits(TO_CHAR(l_arrear_days))
                      ELSE TO_CHAR(l_arrear_days) END
              || CASE WHEN l_is_bengali THEN ' দিন' ELSE ' Days' END || '</div>');
        htp.p('<div>' || CASE WHEN l_is_bengali
                             THEN 'বকেয়ার পরিমাণ'
                             ELSE 'Arrear Amount' END
              || '</div><div>:</div><div>' || display_money(l_arrear_amount) || '</div>');
        htp.p('</div></div>');
        htp.p('<p class="closing">'
              || CASE WHEN l_is_bengali THEN 'মা আসসালাম' ELSE 'Ma Assalam' END
              || '</p>');

        htp.p('<footer class="letter-footer"><div class="system-note">'
              || CASE WHEN l_is_bengali
                      THEN 'বি.দ্র.: এটি একটি কম্পিউটার-উৎপাদিত প্রতিবেদন; এতে কোনো স্বাক্ষরের প্রয়োজন নেই। কোনো জিজ্ঞাসা থাকলে ১৫ দিনের মধ্যে আমাদের লিখিতভাবে জানান।'
                      ELSE 'N.B. This is a system generated report &amp; does not require any signature. Please feel free to write us within 15 days if you have any query.' END
              || '</div><div class="page-number">'
              || CASE WHEN l_is_bengali
                      THEN 'পৃষ্ঠা ' || bn_digits(TO_CHAR(l_letter_count))
                           || ' / ' || bn_digits(TO_CHAR(l_total_letters))
                      ELSE 'Page ' || TO_CHAR(l_letter_count)
                           || ' of ' || TO_CHAR(l_total_letters) END
              || '</div></footer>');
        htp.p('</section>');
    END LOOP;

    IF l_letter_count = 0 THEN
        htp.p('<div class="no-letters">No Salary Done (POSTED) increment letters were found for the selected company and salary month.</div>');
    END IF;

    htp.p(q'~
</div>
<script>
function printIncrementLetters() {
  var source = document.getElementById('increment-letter-print-root');
  var printWindow;
  var copy;
  var toolbar;

  if (!source) {
    return;
  }

  printWindow = window.open('', '_blank', 'width=950,height=760');
  if (!printWindow) {
    window.alert('Please allow pop-ups to print the increment letter.');
    return;
  }

  copy = source.cloneNode(true);
  toolbar = copy.querySelector('.inc-print-toolbar');
  if (toolbar) {
    toolbar.remove();
  }

  printWindow.document.open();
  printWindow.document.write(
    '<!doctype html><html><head><meta charset="utf-8">' +
    '<title>Increment Letter</title></head><body>' +
    copy.outerHTML + '</body></html>'
  );
  printWindow.document.close();

  Promise.all(
    Array.prototype.map.call(printWindow.document.images, function (img) {
      if (img.complete) {
        return Promise.resolve();
      }
      return new Promise(function (resolve) {
        img.onload = resolve;
        img.onerror = resolve;
      });
    })
  ).then(function () {
    window.setTimeout(function () {
      printWindow.focus();
      printWindow.print();
    }, 150);
  });
}
</script>
~');
END;
