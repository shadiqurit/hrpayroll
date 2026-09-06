/*
  Oracle APEX Page 483 - PL/SQL Dynamic Content
  Region name: Promotion Letter

  Required protected hidden item: P483_PROMOTION_ID

  Letter narrative source : HR_EMPLOYEE_LETTER.BODY_HTML / SUBJECT_TEXT
  New salary source        : HR_PROMOTION_SALARY_DTL
  Old salary source        : EMP_SALARY_STRUCTURE_HIST rows whose remarks
                             start with [PROMOTION:<promotion_no>]
*/
DECLARE
    l_subject          hr_employee_letter.subject_text%TYPE;
    l_body             CLOB;
    l_letter_no        hr_employee_letter.letter_no%TYPE;
    l_letter_date      hr_employee_letter.letter_date%TYPE;
    l_letter_status    hr_employee_letter.status%TYPE;
    l_promotion_no     hr_employee_promotion.promotion_no%TYPE;
    l_effective_date   hr_employee_promotion.effective_date%TYPE;
    l_emp_id           hr_employee_promotion.emp_id%TYPE;
    l_company_name     company.name%TYPE;
    l_company_address  company.address%TYPE;
    l_company_phone    company.phone%TYPE;
    l_company_email    company.email%TYPE;
    l_token_position   PLS_INTEGER;
    l_after_token      PLS_INTEGER;
    l_row_count        PLS_INTEGER := 0;
    l_old_gross        NUMBER := 0;
    l_new_gross        NUMBER := 0;

    FUNCTION money (p_amount IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(
            NVL(p_amount, 0),
            'FM999G999G999G990D00',
            'NLS_NUMERIC_CHARACTERS=''.,'''
        );
    END money;

    PROCEDURE emit_body_segment (
        p_offset IN PLS_INTEGER,
        p_length IN PLS_INTEGER
    ) IS
        l_offset     PLS_INTEGER := p_offset;
        l_remaining  PLS_INTEGER := p_length;
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
    SELECT subject_text,
           body_html,
           letter_no,
           letter_date,
           letter_status,
           promotion_no,
           effective_date,
           emp_id,
           company_name,
           company_address,
           company_phone,
           company_email
      INTO l_subject,
           l_body,
           l_letter_no,
           l_letter_date,
           l_letter_status,
           l_promotion_no,
           l_effective_date,
           l_emp_id,
           l_company_name,
           l_company_address,
           l_company_phone,
           l_company_email
      FROM (
            SELECT l.subject_text,
                   l.body_html,
                   l.letter_no,
                   l.letter_date,
                   l.status AS letter_status,
                   p.promotion_no,
                   p.effective_date,
                   p.emp_id,
                   c.name AS company_name,
                   c.address AS company_address,
                   c.phone AS company_phone,
                   c.email AS company_email
              FROM hr_employee_promotion p
                   JOIN employees e ON e.id = p.emp_id
                   LEFT JOIN company c ON c.id = e.com_id
                   JOIN hr_employee_letter l
                     ON l.promotion_id = p.promotion_id
                    AND l.status <> 'CANCELLED'
             WHERE p.promotion_id = :P483_PROMOTION_ID
               AND p.approval_status = 'POSTED'
             ORDER BY l.letter_id DESC
      )
     WHERE ROWNUM = 1;

    htp.p(q'~
<style>
.promo-letter-shell { max-width: 900px; margin: 0 auto; color: #1f2933; font-family: Arial, Helvetica, sans-serif; }
.promo-letter-toolbar { display: flex; justify-content: flex-end; margin: 0 0 14px; }
.promo-letter-page { min-height: 277mm; box-sizing: border-box; padding: 16mm 18mm; background: #fff; border: 1px solid #d9dee3; box-shadow: 0 3px 16px rgba(0,0,0,.12); }
.promo-letter-company { text-align: center; padding-bottom: 12px; border-bottom: 2px solid #253858; }
.promo-letter-company h1 { margin: 0; color: #172b4d; font-size: 24px; }
.promo-letter-company p { margin: 4px 0 0; font-size: 12px; }
.promo-letter-meta { display: flex; justify-content: space-between; margin: 18px 0 22px; font-size: 13px; }
.promo-letter-subject { margin: 18px 0 24px; text-align: center; font-size: 18px; text-decoration: underline; }
.promo-letter-body { font-size: 14px; line-height: 1.65; }
.promo-letter-body p { margin: 10px 0; }
.promotion-salary { width: 100%; margin: 20px 0; border-collapse: collapse; font-size: 12px; }
.promotion-salary th, .promotion-salary td { padding: 7px 8px; border: 1px solid #9aa5b1; }
.promotion-salary thead th { color: #172b4d; background: #e9eef5; text-align: center; }
.promotion-salary td:first-child { text-align: left; }
.promotion-salary .amount { text-align: right; white-space: nowrap; }
.promotion-salary .negative { color: #b42318; }
.promotion-salary .total th { border-top: 2px solid #253858; background: #f4f6f8; }
.promo-letter-footer { margin-top: 28px; padding-top: 8px; border-top: 1px solid #d9dee3; color: #52606d; font-size: 10px; }
@page { size: A4 portrait; margin: 8mm; }
@media print {
  body * { visibility: hidden !important; }
  .promo-letter-page, .promo-letter-page * { visibility: visible !important; }
  .promo-letter-page { position: absolute; inset: 0; width: 100%; min-height: auto; padding: 10mm 12mm; border: 0; box-shadow: none; }
  .promo-letter-toolbar { display: none !important; }
  .promotion-salary thead { display: table-header-group; }
  .promotion-salary tr { break-inside: avoid; page-break-inside: avoid; }
}
</style>
<div class="promo-letter-shell">
  <div class="promo-letter-toolbar">
    <button type="button" class="t-Button t-Button--hot" onclick="window.print();">Print Promotion Letter</button>
  </div>
  <article class="promo-letter-page">
~');

    htp.p('<header class="promo-letter-company"><h1>'
          || apex_escape.html(NVL(l_company_name, 'Company')) || '</h1>');

    IF l_company_address IS NOT NULL THEN
        htp.p('<p>' || apex_escape.html(l_company_address) || '</p>');
    END IF;

    IF l_company_phone IS NOT NULL OR l_company_email IS NOT NULL THEN
        htp.p('<p>' || apex_escape.html(l_company_phone)
              || CASE WHEN l_company_phone IS NOT NULL AND l_company_email IS NOT NULL
                      THEN ' &nbsp; | &nbsp; ' END
              || apex_escape.html(l_company_email) || '</p>');
    END IF;

    htp.p('</header>');
    htp.p('<div class="promo-letter-meta"><span><strong>Reference:</strong> '
          || apex_escape.html(l_letter_no) || '</span><span><strong>Date:</strong> '
          || TO_CHAR(l_letter_date, 'DD-Mon-YYYY') || '</span></div>');
    htp.p('<h2 class="promo-letter-subject">' || apex_escape.html(l_subject) || '</h2>');
    htp.p('<div class="promo-letter-body">');

    /* BODY_HTML stores narrative only. Insert the live comparison where the
       #SALARY_DETAILS# marker occurs. */
    l_token_position := DBMS_LOB.INSTR(l_body, '#SALARY_DETAILS#');

    IF l_token_position > 0 THEN
        emit_body_segment(1, l_token_position - 1);
    ELSE
        emit_body_segment(1, DBMS_LOB.GETLENGTH(l_body));
    END IF;

    htp.p('<table class="promotion-salary"><thead><tr>'
          || '<th>Code</th><th>Salary Head</th><th>Before Promotion</th>'
          || '<th>Promotion Change</th><th>After Promotion</th>'
          || '</tr></thead><tbody>');

    FOR r IN (
        WITH ranked_history AS (
            SELECT h.slno,
                   h.headcode,
                   h.old_amount,
                   h.new_amount,
                   ROW_NUMBER() OVER (
                       PARTITION BY h.slno
                       ORDER BY h.hist_id DESC
                   ) AS rn
              FROM emp_salary_structure_hist h
             WHERE h.emp_id = l_emp_id
               AND h.revision_type = 'P'
               AND INSTR(h.remarks, '[PROMOTION:' || l_promotion_no || ']') = 1
        ),
        promotion_history AS (
            SELECT slno,
                   headcode,
                   old_amount,
                   new_amount
              FROM ranked_history
             WHERE rn = 1
        )
        SELECT salary_row.slno,
               salary_row.headcode,
               salary_row.head_name,
               salary_row.head_type,
               salary_row.old_amount,
               salary_row.new_amount
          FROM (
                SELECT d.slno,
                       d.headcode,
                       NVL(d.head_name, NVL(ah.head_name, d.headcode)) AS head_name,
                       ah.head_type,
                       NVL(h.old_amount, 0) AS old_amount,
                       NVL(d.amount, 0) AS new_amount
                  FROM hr_promotion_salary_dtl d
                       LEFT JOIN allowance_head ah ON ah.head_id = d.slno
                       LEFT JOIN promotion_history h ON h.slno = d.slno
                 WHERE d.promotion_id = :P483_PROMOTION_ID

                UNION ALL

                SELECT h.slno,
                       h.headcode,
                       NVL(ah.head_name, h.headcode) AS head_name,
                       ah.head_type,
                       NVL(h.old_amount, 0) AS old_amount,
                       0 AS new_amount
                  FROM promotion_history h
                       LEFT JOIN allowance_head ah ON ah.head_id = h.slno
                 WHERE NOT EXISTS (
                       SELECT 1
                         FROM hr_promotion_salary_dtl d
                        WHERE d.promotion_id = :P483_PROMOTION_ID
                          AND d.slno = h.slno
                 )
          ) salary_row
         ORDER BY salary_row.slno
    ) LOOP
        l_row_count := l_row_count + 1;

        IF r.head_type = 'EARNING' THEN
            l_old_gross := l_old_gross + NVL(r.old_amount, 0);
            l_new_gross := l_new_gross + NVL(r.new_amount, 0);
        END IF;

        htp.p('<tr><td>' || apex_escape.html(LPAD(TRIM(r.headcode), 3, '0')) || '</td>'
              || '<td>' || apex_escape.html(r.head_name) || '</td>'
              || '<td class="amount">' || money(r.old_amount) || '</td>'
              || '<td class="amount'
              || CASE WHEN NVL(r.new_amount, 0) - NVL(r.old_amount, 0) < 0
                      THEN ' negative' END || '">'
              || money(NVL(r.new_amount, 0) - NVL(r.old_amount, 0)) || '</td>'
              || '<td class="amount">' || money(r.new_amount) || '</td></tr>');
    END LOOP;

    IF l_row_count = 0 THEN
        htp.p('<tr><td colspan="5">No referenced promotion salary history was found.</td></tr>');
    ELSE
        htp.p('<tr class="total"><th colspan="2">Total Gross Salary</th>'
              || '<th class="amount">' || money(l_old_gross) || '</th>'
              || '<th class="amount">' || money(l_new_gross - l_old_gross) || '</th>'
              || '<th class="amount">' || money(l_new_gross) || '</th></tr>');
    END IF;

    htp.p('</tbody></table>');

    IF l_token_position > 0 THEN
        l_after_token := l_token_position + LENGTH('#SALARY_DETAILS#');
        emit_body_segment(
            l_after_token,
            DBMS_LOB.GETLENGTH(l_body) - l_after_token + 1
        );
    END IF;

    htp.p('</div>');
    htp.p('<footer class="promo-letter-footer">Promotion: '
          || apex_escape.html(l_promotion_no) || ' &nbsp; | &nbsp; Effective: '
          || TO_CHAR(l_effective_date, 'DD-Mon-YYYY') || ' &nbsp; | &nbsp; Letter status: '
          || apex_escape.html(l_letter_status) || '</footer>');
    htp.p('</article></div>');
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
              || '</h2></div></div></div></div>');
END;
