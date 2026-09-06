/*
  APEX PL/SQL Dynamic Content region for the promotion letter page.

  Replace PXXX_LETTER_ID with the real hidden page item. Protect that item with
  Session State Protection. The final-submit process branches to this page and
  passes the returned letter ID.
*/
DECLARE
    l_subject     hr_employee_letter.subject_text%TYPE;
    l_body        CLOB;
    l_letter_no   hr_employee_letter.letter_no%TYPE;
    l_letter_date hr_employee_letter.letter_date%TYPE;
    l_position    PLS_INTEGER := 1;
    l_chunk       VARCHAR2(8000);
BEGIN
    SELECT subject_text,
           body_html,
           letter_no,
           letter_date
      INTO l_subject,
           l_body,
           l_letter_no,
           l_letter_date
      FROM hr_employee_letter
     WHERE letter_id = :PXXX_LETTER_ID
       AND promotion_id IS NOT NULL
       AND status <> 'CANCELLED';

    htp.p(q'~
<style>
.promotion-letter-wrap { max-width: 850px; margin: 0 auto; color: #222; }
.promotion-letter-toolbar { margin-bottom: 16px; text-align: right; }
.promotion-letter-page { background: #fff; padding: 18mm; border: 1px solid #ddd; }
.promotion-letter-meta { display: flex; justify-content: space-between; margin-bottom: 22px; }
.promotion-letter-page h2 { text-align: center; }
.promotion-salary { width: 100%; border-collapse: collapse; margin: 18px 0; }
.promotion-salary th, .promotion-salary td { border: 1px solid #aaa; padding: 7px; }
.promotion-salary th { background: #f1f3f5; }
.promotion-salary .amount { text-align: right; white-space: nowrap; }
.promotion-salary .total th { border-top: 2px solid #333; }
@media print {
  body * { visibility: hidden !important; }
  .promotion-letter-page, .promotion-letter-page * { visibility: visible !important; }
  .promotion-letter-page { position: absolute; inset: 0; border: 0; padding: 12mm; }
  .promotion-letter-toolbar { display: none !important; }
}
</style>
<div class="promotion-letter-wrap">
  <div class="promotion-letter-toolbar">
    <button type="button" class="t-Button t-Button--hot" onclick="window.print();">Print Letter</button>
  </div>
  <article class="promotion-letter-page">
~');

    htp.p('<div class="promotion-letter-meta"><span><strong>Letter No:</strong> '
          || apex_escape.html(l_letter_no) || '</span><span><strong>Date:</strong> '
          || TO_CHAR(l_letter_date, 'DD-Mon-YYYY') || '</span></div>');
    htp.p('<h2>' || apex_escape.html(l_subject) || '</h2>');

    /* HTP.P is VARCHAR2-based; stream the CLOB in safe chunks. BODY_HTML is
       generated only from an HR-managed template plus escaped data. */
    WHILE l_position <= DBMS_LOB.GETLENGTH(l_body) LOOP
        l_chunk := DBMS_LOB.SUBSTR(l_body, 8000, l_position);
        htp.prn(l_chunk);
        l_position := l_position + LENGTH(l_chunk);
    END LOOP;

    htp.p('</article></div>');
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        htp.p('<div class="t-Alert t-Alert--warning">Promotion letter was not found.</div>');
END;
