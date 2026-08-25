/*
  Oracle APEX Page 503
  Region Type : PL/SQL Dynamic Content
  Purpose     : Print one or all POSTED increment letters for a salary month.

  Required page items:
    P503_COM_ID          NUMBER, required
    P503_SALARY_MONTH    NUMBER(6), required, for example 202608
    P503_INCREMENT_ID    NUMBER, optional (one letter when supplied)

  Page 503 should use a Printer Friendly / Minimal page template.
*/

DECLARE
    l_letter_count NUMBER := 0;

    FUNCTION esc(p_text IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN apex_escape.html(NVL(p_text, ''));
    END esc;

    FUNCTION money(p_amount IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(
            NVL(p_amount, 0),
            'FM999G999G999G999G990D00',
            'NLS_NUMERIC_CHARACTERS=''.,'''
        );
    END money;
BEGIN
    IF :P503_COM_ID IS NULL OR :P503_SALARY_MONTH IS NULL THEN
        htp.p('<div class="t-Alert t-Alert--warning">Company and salary month are required.</div>');
        RETURN;
    END IF;

    htp.p(q'~
<style>
  .inc-print-toolbar { margin: 0 0 16px; text-align: right; }
  .inc-print-button {
    border: 0; border-radius: 4px; padding: 9px 18px;
    background: #1f5f99; color: #fff; font-weight: 600; cursor: pointer;
  }
  .increment-letter {
    box-sizing: border-box; max-width: 190mm; min-height: 267mm;
    margin: 0 auto 20px; padding: 14mm 15mm; background: #fff;
    color: #111; font-family: Arial, sans-serif; font-size: 12px;
    line-height: 1.45; border: 1px solid #d9d9d9;
    break-after: page; page-break-after: always;
  }
  .increment-letter:last-of-type { break-after: auto; page-break-after: auto; }
  .letter-head { text-align: center; border-bottom: 2px solid #222; padding-bottom: 10px; }
  .letter-company { margin: 0; font-size: 22px; font-weight: 700; }
  .letter-address { margin: 3px 0 0; font-size: 11px; }
  .letter-meta { width: 100%; margin: 16px 0 18px; border-collapse: collapse; }
  .letter-meta td { padding: 2px 0; vertical-align: top; }
  .letter-meta td:last-child { text-align: right; }
  .letter-subject { margin: 18px 0; text-align: center; font-weight: 700; text-decoration: underline; }
  .employee-table, .salary-table {
    width: 100%; margin: 12px 0 18px; border-collapse: collapse;
  }
  .employee-table th, .employee-table td,
  .salary-table th, .salary-table td {
    border: 1px solid #777; padding: 6px 8px; text-align: left;
  }
  .employee-table th { width: 22%; background: #f3f3f3; }
  .salary-table th { background: #e9eef4; }
  .amount { text-align: right !important; white-space: nowrap; }
  .letter-signature { margin-top: 45px; width: 100%; }
  .letter-signature td { width: 50%; vertical-align: bottom; }
  .signature-right { text-align: right; }
  .no-letters { padding: 20px; border: 1px solid #ddd; background: #fafafa; }
  @page { size: A4; margin: 10mm; }
  @media print {
    .t-Header, .t-Body-nav, .t-Footer, .t-Body-title, .inc-print-toolbar {
      display: none !important;
    }
    .t-Body-main, .t-Body-content, .t-Body-contentInner { margin: 0 !important; padding: 0 !important; }
    .increment-letter { border: 0; margin: 0; padding: 8mm 10mm; max-width: none; }
  }
</style>
<div class="inc-print-toolbar">
  <button type="button" class="inc-print-button" onclick="window.print();">Print All Letters</button>
</div>
~');

    FOR r IN (
        SELECT i.increment_id,
               i.action_id,
               i.salary_month,
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
               e.emp_id AS employee_code,
               TRIM(e.f_name || ' ' || e.l_name) AS employee_name,
               d.designation,
               dp.dept_name,
               c.name AS company_name,
               c.address AS company_address,
               c.phone AS company_phone,
               c.email AS company_email,
               NVL(
                   l.letter_no,
                   'INC-' || TO_CHAR(i.salary_month) || '-' || TO_CHAR(i.increment_id)
               ) AS letter_no,
               NVL(l.letter_date, TRUNC(i.posted_date)) AS letter_date
          FROM hr_employee_increment i
               JOIN employees e ON e.id = i.emp_id
               JOIN company c ON c.id = i.com_id
               LEFT JOIN designations d ON d.id = e.desig_id
               LEFT JOIN departments dp ON dp.id = e.dept_id
               LEFT JOIN (
                   SELECT action_id,
                          MAX(letter_no) KEEP (DENSE_RANK LAST ORDER BY letter_id) AS letter_no,
                          MAX(letter_date) KEEP (DENSE_RANK LAST ORDER BY letter_id) AS letter_date
                     FROM hr_employee_letter
                    WHERE status IN ('APPROVED', 'ISSUED')
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

        htp.p('<section class="increment-letter">');
        htp.p('<header class="letter-head">');
        htp.p('<h1 class="letter-company">' || esc(r.company_name) || '</h1>');
        htp.p('<p class="letter-address">' || esc(r.company_address));
        IF r.company_phone IS NOT NULL THEN
            htp.p(' | Phone: ' || esc(r.company_phone));
        END IF;
        IF r.company_email IS NOT NULL THEN
            htp.p(' | Email: ' || esc(r.company_email));
        END IF;
        htp.p('</p></header>');

        htp.p('<table class="letter-meta"><tr>');
        htp.p('<td><strong>Letter No:</strong> ' || esc(r.letter_no) || '</td>');
        htp.p('<td><strong>Date:</strong> ' || TO_CHAR(r.letter_date, 'DD-Mon-YYYY') || '</td>');
        htp.p('</tr></table>');

        htp.p('<p><strong>To</strong><br>' || esc(r.employee_name) || '<br>Employee ID: '
              || esc(r.employee_code) || '<br>' || esc(r.designation) || '<br>'
              || esc(r.dept_name) || '</p>');

        htp.p('<div class="letter-subject">Subject: Annual Increment of Pay</div>');
        htp.p('<p>Dear ' || esc(r.employee_name) || ',</p>');
        htp.p('<p>Your annual increment has been approved with effect from <strong>'
              || TO_CHAR(r.payable_effective_date, 'DD-Mon-YYYY')
              || '</strong>. Your consideration date remains '
              || TO_CHAR(r.due_date, 'DD-Mon-YYYY') || '.</p>');

        htp.p('<table class="employee-table">');
        htp.p('<tr><th>Salary Month</th><td>'
              || TO_CHAR(TO_DATE(TO_CHAR(r.salary_month) || '01', 'YYYYMMDD'), 'FMMonth YYYY')
              || '</td><th>Scale Step</th><td>'
              || NVL(TO_CHAR(r.from_step_no), 'Initial') || ' to '
              || TO_CHAR(r.to_step_no) || ' of ' || TO_CHAR(r.total_steps)
              || '</td></tr>');
        htp.p('</table>');

        htp.p('<table class="salary-table">');
        htp.p('<thead><tr><th>Salary Component</th><th class="amount">Old Amount</th>'
              || '<th class="amount">New Amount</th><th class="amount">Difference</th></tr></thead><tbody>');

        FOR s IN (
            SELECT LPAD(TRIM(h.headcode), 3, '0') AS normalized_headcode,
                   NVL(ah.head_name,
                       CASE LPAD(TRIM(h.headcode), 3, '0')
                           WHEN '001' THEN 'Basic'
                           WHEN '005' THEN 'HR'
                           WHEN '013' THEN 'PF'
                           WHEN '057' THEN 'CPF'
                       END
                   ) AS head_name,
                   h.old_amount,
                   h.new_amount
              FROM emp_salary_structure_hist h
                   LEFT JOIN allowance_head ah
                     ON LPAD(TRIM(ah.head_code), 3, '0') =
                        LPAD(TRIM(h.headcode), 3, '0')
             WHERE h.action_id = r.action_id
               AND h.emp_id = r.employee_pk
               AND LPAD(TRIM(h.headcode), 3, '0')
                   IN ('001', '005', '013', '057')
             ORDER BY CASE LPAD(TRIM(h.headcode), 3, '0')
                          WHEN '001' THEN 1
                          WHEN '005' THEN 2
                          WHEN '013' THEN 3
                          WHEN '057' THEN 4
                          ELSE 9
                      END
        ) LOOP
            htp.p('<tr><td>' || esc(s.normalized_headcode || ' - ' || s.head_name) || '</td>');
            htp.p('<td class="amount">' || money(s.old_amount) || '</td>');
            htp.p('<td class="amount">' || money(s.new_amount) || '</td>');
            htp.p('<td class="amount">' || money(NVL(s.new_amount, 0) - NVL(s.old_amount, 0)) || '</td></tr>');
        END LOOP;

        htp.p('<tr><th>Gross Salary</th><th class="amount">' || money(r.old_gross)
              || '</th><th class="amount">' || money(r.new_gross)
              || '</th><th class="amount">'
              || money(NVL(r.new_gross, 0) - NVL(r.old_gross, 0)) || '</th></tr>');
        htp.p('</tbody></table>');

        htp.p('<p><strong>Basic increment amount:</strong> ' || money(r.increment_amount) || '</p>');
        htp.p('<p>All other existing salary components remain unchanged. Please retain this letter for your records.</p>');

        htp.p('<table class="letter-signature"><tr><td>Employee Copy</td>');
        htp.p('<td class="signature-right">_____________________________<br>Authorized Signatory</td></tr></table>');
        htp.p('</section>');
    END LOOP;

    IF l_letter_count = 0 THEN
        htp.p('<div class="no-letters">No POSTED increment letters were found for the selected company and salary month.</div>');
    END IF;
END;
