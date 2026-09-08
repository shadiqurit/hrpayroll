/*
  Oracle APEX Page 483 - PL/SQL Dynamic Content
  Region name: Promotion Letter

  The only required/protected page item is P483_PROMOTION_ID.

  Language             : promoted JOB_GRADES.GRADE_ORDER
                         1-14 English; 15-20 Bengali
  Narrative            : latest non-cancelled HR_EMPLOYEE_LETTER
  Salary breakdown     : HR_PROMOTION_SALARY_DTL promoted earning amounts

  The letter deliberately uses the same visual salary style as the confirmation
  letter: salary head, colon, and promoted amount. It has no comparison grid.
  No salary head-code exclusion is applied, so earning heads 025 and 026 print.

  Signatory and optional TO/COPY lines come from HR_LETTER_SIGNATORY,
  HR_LETTER_RECIPIENT and the promotion-specific
  HR_PROMOTION_LETTER_RECIPIENT configuration.

  Printing is intended for the company's pre-designed letterhead. The generated
  output therefore omits the IBN/SINA brand, company-name banner and tagline,
  while reserving the top area occupied by the physical letterhead.

  printContent and divToPrint are retained for the page's custom print setup.
*/
DECLARE
    l_promotion_id     NUMBER;
    l_subject          hr_employee_letter.subject_text%TYPE;
    l_body             CLOB;
    l_letter_no        hr_employee_letter.letter_no%TYPE;
    l_letter_date      hr_employee_letter.letter_date%TYPE;
    l_promotion_no     hr_employee_promotion.promotion_no%TYPE;
    l_effective_date   hr_employee_promotion.effective_date%TYPE;
    l_emp_code         employees.emp_id%TYPE;
    l_emp_name         VARCHAR2(200);
    l_old_designation  designations.designation%TYPE;
    l_new_designation  designations.designation%TYPE;
    l_department       departments.dept_name%TYPE;
    l_location         locations.name%TYPE;
    l_grade_order      job_grades.grade_order%TYPE;
    l_company_name     company.name%TYPE;
    l_company_address  company.address%TYPE;
    l_company_phone    company.phone%TYPE;
    l_company_email    company.email%TYPE;
    l_sign_name_en     hr_letter_signatory.name_en%TYPE;
    l_sign_title_en    hr_letter_signatory.title_en%TYPE;
    l_sign_name_bn     hr_letter_signatory.name_bn%TYPE;
    l_sign_title_bn    hr_letter_signatory.title_bn%TYPE;
    l_token_position   PLS_INTEGER;
    l_after_token      PLS_INTEGER;
    l_legacy_sign_pos  PLS_INTEGER;
    l_row_count        PLS_INTEGER := 0;
    l_to_count         PLS_INTEGER := 0;
    l_copy_count       PLS_INTEGER := 0;
    l_new_gross        NUMBER := 0;
    l_is_bengali       BOOLEAN := FALSE;

    FUNCTION esc(p_value IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN apex_escape.html(NVL(p_value, '-'));
    END esc;

    FUNCTION esc_multiline(p_value IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN REPLACE(
                   REPLACE(esc(p_value), CHR(13) || CHR(10), '<br>'),
                   CHR(10),
                   '<br>'
               );
    END esc_multiline;

    FUNCTION money(p_amount IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(
            NVL(p_amount, 0),
            'FM999G999G999G990D00',
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

    FUNCTION bn_date_short(p_date IN DATE) RETURN VARCHAR2 IS
    BEGIN
        IF p_date IS NULL THEN
            RETURN '-';
        END IF;
        RETURN bn_digits(TO_CHAR(p_date, 'DD.MM.YYYY')) || ' খ্রি.';
    END bn_date_short;

    FUNCTION bn_company_name(p_name IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        IF INSTR(UPPER(NVL(p_name, '')), 'IBN SINA') > 0 THEN
            RETURN 'দি ইবনে সিনা ফার্মাসিউটিক্যাল ইন্ডাস্ট্রি পিএলসি';
        END IF;
        RETURN NVL(p_name, 'দি ইবনে সিনা ফার্মাসিউটিক্যাল ইন্ডাস্ট্রি পিএলসি');
    END bn_company_name;

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
            WHEN '026' THEN 'এলাউন্স ফর স্পেশ্যাল এ্যাচিভমেন্ট'
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

    PROCEDURE emit_body_segment(
        p_offset IN PLS_INTEGER,
        p_length IN PLS_INTEGER
    ) IS
        l_offset     PLS_INTEGER := p_offset;
        l_remaining  PLS_INTEGER := GREATEST(NVL(p_length, 0), 0);
        l_chunk      VARCHAR2(8000);
        l_take       PLS_INTEGER;
    BEGIN
        WHILE l_remaining > 0 LOOP
            l_take := LEAST(8000, l_remaining);
            l_chunk := DBMS_LOB.SUBSTR(l_body, l_take, l_offset);
            EXIT WHEN l_chunk IS NULL;
            htp.prn(l_chunk);
            l_offset := l_offset + LENGTH(l_chunk);
            l_remaining := l_remaining - LENGTH(l_chunk);
        END LOOP;
    END emit_body_segment;
BEGIN
    l_promotion_id := TO_NUMBER(:P483_PROMOTION_ID);

    SELECT subject_text,
           body_html,
           letter_no,
           letter_date,
           promotion_no,
           effective_date,
           emp_code,
           emp_name,
           old_designation,
           new_designation,
           department,
           location_name,
           grade_order,
           company_name,
           company_address,
           company_phone,
           company_email,
           sign_name_en,
           sign_title_en,
           sign_name_bn,
           sign_title_bn
      INTO l_subject,
           l_body,
           l_letter_no,
           l_letter_date,
           l_promotion_no,
           l_effective_date,
           l_emp_code,
           l_emp_name,
           l_old_designation,
           l_new_designation,
           l_department,
           l_location,
           l_grade_order,
           l_company_name,
           l_company_address,
           l_company_phone,
           l_company_email,
           l_sign_name_en,
           l_sign_title_en,
           l_sign_name_bn,
           l_sign_title_bn
      FROM (
            SELECT l.subject_text,
                   l.body_html,
                   l.letter_no,
                   l.letter_date,
                   p.promotion_no,
                   p.effective_date,
                   e.emp_id AS emp_code,
                   TRIM(e.f_name || ' ' || e.l_name) AS emp_name,
                   NVL(od.designation, nd.designation) AS old_designation,
                   nd.designation AS new_designation,
                   dp.dept_name AS department,
                   loc.name AS location_name,
                   g.grade_order,
                   c.name AS company_name,
                   c.address AS company_address,
                   c.phone AS company_phone,
                   c.email AS company_email,
                   sig.name_en AS sign_name_en,
                   sig.title_en AS sign_title_en,
                   sig.name_bn AS sign_name_bn,
                   sig.title_bn AS sign_title_bn
              FROM hr_employee_promotion p
                   JOIN employees e ON e.id = p.emp_id
                   LEFT JOIN designations od ON od.id = p.old_desig_id
                   LEFT JOIN designations nd ON nd.id = p.new_desig_id
                   LEFT JOIN departments dp ON dp.id = p.new_dept_id
                   LEFT JOIN locations loc ON loc.id = e.loc_id
                   LEFT JOIN company c ON c.id = e.com_id
                   LEFT JOIN hr_letter_signatory sig
                     ON sig.signatory_id = p.signatory_id
                   LEFT JOIN job_grades g
                     ON g.id = NVL(nd.grade, NVL(p.new_job_id, e.job_id))
                   JOIN hr_employee_letter l
                     ON l.promotion_id = p.promotion_id
                    AND l.status <> 'CANCELLED'
             WHERE p.promotion_id = l_promotion_id
               AND p.approval_status = 'POSTED'
             ORDER BY l.letter_id DESC
      )
     WHERE ROWNUM = 1;

    IF l_grade_order BETWEEN 15 AND 20 THEN
        l_is_bengali := TRUE;
    ELSIF l_grade_order BETWEEN 1 AND 14 THEN
        l_is_bengali := FALSE;
    ELSE
        RAISE_APPLICATION_ERROR(
            -20640,
            'Promotion letter language is configured only for grade order 1 through 20.'
        );
    END IF;

    /* Old promotion rows may predate SIGNATORY_ID. Use MD only as a legacy
       fallback; final submit requires an explicit active selection. */
    IF l_sign_name_en IS NULL OR l_sign_name_bn IS NULL THEN
        SELECT name_en,
               title_en,
               name_bn,
               title_bn
          INTO l_sign_name_en,
               l_sign_title_en,
               l_sign_name_bn,
               l_sign_title_bn
          FROM hr_letter_signatory
         WHERE signatory_code = 'MD';
    END IF;

    SELECT COUNT(*)
      INTO l_to_count
      FROM hr_promotion_letter_recipient pr
      LEFT JOIN hr_letter_recipient mr
        ON mr.letter_recipient_id = pr.letter_recipient_id
     WHERE pr.promotion_id = l_promotion_id
       AND pr.section_type = 'TO'
       AND pr.is_active = 'Y'
       AND NVL(
               CASE
                   WHEN l_grade_order BETWEEN 15 AND 20
                       THEN NVL(mr.recipient_name_bn, mr.recipient_name_en)
                   ELSE mr.recipient_name_en
               END,
               pr.line_text
           ) IS NOT NULL;

    SELECT COUNT(*)
      INTO l_copy_count
      FROM hr_promotion_letter_recipient pr
      LEFT JOIN hr_letter_recipient mr
        ON mr.letter_recipient_id = pr.letter_recipient_id
     WHERE pr.promotion_id = l_promotion_id
       AND pr.section_type = 'COPY'
       AND pr.is_active = 'Y'
       AND NVL(
               CASE
                   WHEN l_grade_order BETWEEN 15 AND 20
                       THEN NVL(mr.recipient_name_bn, mr.recipient_name_en)
                   ELSE mr.recipient_name_en
               END,
               pr.line_text
           ) IS NOT NULL;

    htp.p(q'~
<div id="divToPrint">
<style>
* { box-sizing: border-box; }
.promo-letter-shell { max-width: 900px; margin: 0 auto; color: #111; }
.promo-letter-shell.en { font-family: Georgia, "Times New Roman", serif; }
.promo-letter-shell.bn {
  font-family: "Noto Sans Bengali", "Hind Siliguri", "SolaimanLipi",
               "Kalpurush", "Arial Unicode MS", sans-serif;
}
.promo-letter-toolbar { display: flex; justify-content: flex-end; margin: 0 0 12px; }
.promo-letter-page {
  position: relative; width: 210mm; min-height: 297mm; margin: 0 auto;
  padding: 30mm 14mm 8mm; background: #fff; border: 1px solid #d7dce1;
  box-shadow: 0 3px 16px rgba(0,0,0,.12); font-size: 12.5px; line-height: 1.48;
}
.bn .promo-letter-page { font-size: 14px; line-height: 1.55; }
.department-line { font-weight: 700; margin: 0 0 5px; }
.letter-meta { display: flex; justify-content: space-between; gap: 20px; margin: 4px 0 10px; }
.employee-address { margin: 0 0 7px; line-height: 1.38; }
.employee-name { font-weight: 700; }
.custom-to .recipient-line:first-of-type { font-weight: 700; }
.letter-subject { margin: 8px 0 8px; font-weight: 700; text-decoration: underline; }
.letter-body p { margin: 6px 0; text-align: justify; }
.salary-breakdown {
  width: min(100%, 520px); min-width: 410px; margin: 8px 0 4px;
  font-size: 12px; line-height: 1.35;
  break-inside: avoid; page-break-inside: avoid;
}
.bn .salary-breakdown { font-size: 14px; }
.salary-line {
  display: grid; grid-template-columns: minmax(235px, 1fr) 18px 135px;
  align-items: baseline; column-gap: 5px; padding: 2px 5px;
}
.salary-label { font-weight: 600; }
.salary-colon { text-align: center; }
.salary-amount { text-align: right; white-space: nowrap; }
.salary-total { margin-top: 3px; border-top: 1px solid #111; font-weight: 700; }
.total-in-words { margin: 4px 0 8px !important; font-weight: 600; }
.signature-copy-row {
  display: flex; justify-content: space-between; align-items: flex-end; gap: 25px;
  width: 100%; margin-top: 12px; break-inside: avoid; page-break-inside: avoid;
}
.signature-block { flex: 0 0 47%; }
.signature-copy-row.no-copy .signature-block { flex-basis: 100%; }
.signature-space { height: 42px; }
.signature-name { font-weight: 700; }
.copy-section { flex: 0 0 48%; font-size: 10.5px; }
.bn .copy-section { font-size: 11.5px; }
.copy-section ol { margin: 2px 0 0; padding-left: 22px; }
.copy-section li { margin: 0; line-height: 1.25; }
.company-footer {
  margin-top: 8px; padding-top: 4px; border-top: 2px solid #164f8e;
  color: #24425f; text-align: center; font: 9px/1.25 Arial, sans-serif;
}
@page { size: A4 portrait; margin: 0; }
@media print {
  html, body { margin: 0 !important; padding: 0 !important; background: #fff !important; }
  body * { visibility: hidden !important; }
  .promo-letter-page, .promo-letter-page * { visibility: visible !important; }
  .promo-letter-page {
    position: absolute; inset: 0; width: 100%; min-height: auto; margin: 0;
    padding: 30mm 14mm 8mm; border: 0; box-shadow: none;
    -webkit-print-color-adjust: exact; print-color-adjust: exact;
  }
  .promo-letter-toolbar { display: none !important; }
  .salary-breakdown, .salary-line, .signature-copy-row { break-inside: avoid; page-break-inside: avoid; }
  .letter-body p { orphans: 3; widows: 3; }
}
</style>
~');

    htp.p('<div class="promo-letter-shell '
          || CASE WHEN l_is_bengali THEN 'bn' ELSE 'en' END
          || '" lang="' || CASE WHEN l_is_bengali THEN 'bn' ELSE 'en' END || '">');
    htp.p('<div class="promo-letter-toolbar"><button type="button" '
          || 'class="t-Button t-Button--hot" onclick="printContent();">'
          || CASE WHEN l_is_bengali
                  THEN '<span class="fa fa-print" aria-hidden="true"></span> পদোন্নতি পত্র প্রিন্ট করুন'
                  ELSE '<span class="fa fa-print" aria-hidden="true"></span> Print Promotion Letter'
             END
          || '</button></div>');
    htp.p('<article class="promo-letter-page">');

    htp.p('<div class="department-line">'
          || CASE WHEN l_is_bengali THEN 'মানবসম্পদ বিভাগ' ELSE 'Human Resources Department' END
          || '</div>');

    htp.p('<div class="letter-meta"><div><strong>'
          || CASE WHEN l_is_bengali THEN 'সূত্র নং :' ELSE 'Reference:' END
          || '</strong> ' || esc(NVL(l_letter_no, l_promotion_no)) || '</div><div><strong>'
          || CASE WHEN l_is_bengali THEN 'তারিখ:' ELSE 'Date:' END
          || '</strong> '
          || CASE WHEN l_is_bengali
                  THEN esc(bn_date_short(l_letter_date))
                  ELSE esc(TO_CHAR(l_letter_date, 'DD.MM.YYYY'))
             END
          || '</div></div>');

    IF l_to_count > 0 THEN
        htp.p('<div class="employee-address custom-to">'
              || CASE WHEN l_is_bengali THEN 'প্রতি' ELSE 'To' END);

        FOR r IN (
            SELECT NVL(
                       CASE
                           WHEN l_grade_order BETWEEN 15 AND 20
                               THEN NVL(mr.recipient_name_bn, mr.recipient_name_en)
                           ELSE mr.recipient_name_en
                       END,
                       pr.line_text
                   ) AS recipient_text
              FROM hr_promotion_letter_recipient pr
              LEFT JOIN hr_letter_recipient mr
                ON mr.letter_recipient_id = pr.letter_recipient_id
             WHERE pr.promotion_id = l_promotion_id
               AND pr.section_type = 'TO'
               AND pr.is_active = 'Y'
             ORDER BY NVL(mr.display_order, pr.display_order), pr.recipient_id
        ) LOOP
            htp.p('<div class="recipient-line">'
                  || esc_multiline(r.recipient_text) || '</div>');
        END LOOP;

        htp.p('</div>');
    ELSIF l_is_bengali THEN
        htp.p('<div class="employee-address">প্রতি<br><span class="employee-name">'
              || esc(l_emp_name) || '</span><br>Staff No. ' || esc(l_emp_code) || ',<br>'
              || esc(l_old_designation) || ', ' || esc(l_department) || ',<br>'
              || esc(bn_company_name(l_company_name)) || ',<br>'
              || 'কর্মস্থল: ' || esc(l_location) || '।</div>');
    ELSE
        htp.p('<div class="employee-address">To<br><span class="employee-name">'
              || esc(l_emp_name) || '</span><br>Staff No. ' || esc(l_emp_code) || ',<br>'
              || esc(l_old_designation) || ', ' || esc(l_department) || ',<br>'
              || esc(NVL(l_company_name, 'The IBN SINA Pharmaceutical Industry PLC')) || ',<br>'
              || 'Place of posting: ' || esc(l_location) || '.</div>');
    END IF;

    IF l_is_bengali THEN
        htp.p('<div class="letter-subject">বিষয় : ' || esc(l_subject) || '</div>');
    ELSE
        htp.p('<div class="letter-subject">Subject: ' || esc(l_subject) || '</div>');
    END IF;

    htp.p('<div class="letter-body">');
    l_token_position := DBMS_LOB.INSTR(l_body, '#SALARY_DETAILS#');

    IF l_token_position > 0 THEN
        emit_body_segment(1, l_token_position - 1);
    ELSE
        emit_body_segment(1, DBMS_LOB.GETLENGTH(l_body));
    END IF;

    htp.p('<div class="salary-breakdown">');

    FOR r IN (
        SELECT d.slno,
               d.headcode,
               NVL(d.head_name, NVL(ah.head_name, d.headcode)) AS head_name,
               NVL(d.amount, 0) AS new_amount
          FROM hr_promotion_salary_dtl d
               LEFT JOIN allowance_head ah ON ah.head_id = d.slno
         WHERE d.promotion_id = l_promotion_id
           AND NVL(ah.head_type, 'EARNING') = 'EARNING'
           AND NVL(d.amount, 0) <> 0
         /* Intentionally no NOT IN ('025','026'): both earning heads print. */
         ORDER BY NVL(ah.print_order, d.slno), d.slno
    ) LOOP
        l_row_count := l_row_count + 1;
        l_new_gross := l_new_gross + NVL(r.new_amount, 0);

        htp.p('<div class="salary-line"><div class="salary-label">'
              || esc(CASE WHEN l_is_bengali
                          THEN bn_head_name(r.headcode, r.head_name)
                          ELSE r.head_name END) || '</div>'
              || '<div class="salary-colon">:</div>'
              || '<div class="salary-amount">' || display_money(r.new_amount) || '</div></div>');
    END LOOP;

    IF l_row_count = 0 THEN
        htp.p('<div class="salary-empty">'
              || CASE WHEN l_is_bengali
                      THEN 'পদোন্নতির বেতনের বিবরণ পাওয়া যায়নি।'
                      ELSE 'No promoted salary details were found.' END
              || '</div>');
    ELSE
        htp.p('<div class="salary-line salary-total"><div class="salary-label">'
              || CASE WHEN l_is_bengali THEN 'মোট' ELSE 'Total' END
              || '</div><div class="salary-colon">:</div><div class="salary-amount">'
              || display_money(l_new_gross) || '</div></div>');
    END IF;

    htp.p('</div>');

    IF l_row_count > 0 THEN
        IF l_is_bengali THEN
            htp.p('<p class="total-in-words">মোট: '
                  || esc(f_inword_tk_bn(l_new_gross)) || '।</p>');
        ELSE
            htp.p('<p class="total-in-words">Total in words: '
                  || esc(f_inword_tk(l_new_gross)) || '</p>');
        END IF;
    END IF;

    IF l_token_position > 0 THEN
        l_after_token := l_token_position + LENGTH('#SALARY_DETAILS#');
        l_legacy_sign_pos := DBMS_LOB.INSTR(
                                 l_body,
                                 '<div class="signature-copy-row">',
                                 l_after_token
                             );

        IF l_legacy_sign_pos > 0 THEN
            emit_body_segment(
                l_after_token,
                l_legacy_sign_pos - l_after_token
            );
        ELSE
            emit_body_segment(
                l_after_token,
                DBMS_LOB.GETLENGTH(l_body) - l_after_token + 1
            );
        END IF;
    END IF;

    htp.p('</div>');

    htp.p('<div class="signature-copy-row'
          || CASE WHEN l_copy_count = 0 THEN ' no-copy' END || '">');
    htp.p('<div class="signature-block"><div class="signature-space"></div>'
          || '<div class="signature-name">('
          || esc(CASE WHEN l_is_bengali THEN l_sign_name_bn ELSE l_sign_name_en END)
          || ')</div><div>'
          || esc(CASE WHEN l_is_bengali THEN l_sign_title_bn ELSE l_sign_title_en END)
          || '</div></div>');

    IF l_copy_count > 0 THEN
        htp.p('<div class="copy-section"><strong>'
              || CASE WHEN l_is_bengali THEN 'অনুলিপিঃ' ELSE 'Copy to:' END
              || '</strong><ol>');

        FOR r IN (
            SELECT NVL(
                       CASE
                           WHEN l_grade_order BETWEEN 15 AND 20
                               THEN NVL(mr.recipient_name_bn, mr.recipient_name_en)
                           ELSE mr.recipient_name_en
                       END,
                       pr.line_text
                   ) AS recipient_text
              FROM hr_promotion_letter_recipient pr
              LEFT JOIN hr_letter_recipient mr
                ON mr.letter_recipient_id = pr.letter_recipient_id
             WHERE pr.promotion_id = l_promotion_id
               AND pr.section_type = 'COPY'
               AND pr.is_active = 'Y'
             ORDER BY NVL(mr.display_order, pr.display_order), pr.recipient_id
        ) LOOP
            htp.p('<li>' || esc_multiline(r.recipient_text) || '</li>');
        END LOOP;

        htp.p('</ol></div>');
    END IF;

    htp.p('</div>');
    htp.p('<footer class="company-footer">' || esc(l_company_address));

    IF l_company_phone IS NOT NULL OR l_company_email IS NOT NULL THEN
        htp.p('<br>' || esc(l_company_phone)
              || CASE WHEN l_company_phone IS NOT NULL AND l_company_email IS NOT NULL
                      THEN ' &nbsp; | &nbsp; ' END
              || esc(l_company_email));
    END IF;

    htp.p('<br>Promotion: ' || esc(l_promotion_no) || ' &nbsp; | &nbsp; '
          || CASE WHEN l_is_bengali THEN 'কার্যকর: ' ELSE 'Effective: ' END
          || CASE WHEN l_is_bengali
                  THEN esc(bn_date_short(l_effective_date))
                  ELSE esc(TO_CHAR(l_effective_date, 'DD-Mon-YYYY')) END
          || '</footer></article></div></div>');
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        htp.p('<div class="t-Alert t-Alert--warning t-Alert--defaultIcons">'
              || '<div class="t-Alert-wrap"><div class="t-Alert-content">'
              || '<div class="t-Alert-header"><h2 class="t-Alert-title">'
              || 'No posted promotion letter was found for this promotion.'
              || '</h2></div></div></div></div>');
    WHEN OTHERS THEN
        htp.p('<div class="t-Alert t-Alert--danger t-Alert--defaultIcons">'
              || '<div class="t-Alert-wrap"><div class="t-Alert-content">'
              || '<div class="t-Alert-header"><h2 class="t-Alert-title">'
              || apex_escape.html(SQLERRM)
              || '</h2></div></div></div></div> </div>');
END;
