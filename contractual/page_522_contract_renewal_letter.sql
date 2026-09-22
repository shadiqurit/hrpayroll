/* ============================================================================
   PAGE 522 - CONTRACT RENEWAL LETTER

   APEX page type: Normal Page
   Page template: Blank with Attributes (or Minimal)
   Required protected items: P522_RENEWAL_ID, P522_COM_ID
   Region type: PL/SQL Dynamic Content
   Escape Special Characters: No

   Add this page-level JavaScript function:

   function printContractLetter() {
     window.print();
   }
   ============================================================================ */

DECLARE
    L_RENEWAL_ID       NUMBER;
    L_BODY             CLOB;
    L_SUBJECT          VARCHAR2(500);
    L_LETTER_NO        VARCHAR2(30);
    L_LETTER_DATE      DATE;
    L_LETTER_STATUS    VARCHAR2(20);
    L_RENEWAL_NO       VARCHAR2(30);
    L_EMP_CODE         VARCHAR2(30);
    L_EMP_NAME         VARCHAR2(200);
    L_DESIGNATION      VARCHAR2(150);
    L_DEPARTMENT       VARCHAR2(150);
    L_LOCATION         VARCHAR2(150);
    L_ADDRESS          VARCHAR2(500);
    L_COMPANY          VARCHAR2(200);
    L_NEW_FROM         DATE;
    L_NEW_TO           DATE;
    L_SIGN_NAME        VARCHAR2(200);
    L_SIGN_TITLE       VARCHAR2(200);
    L_TOKEN_POS        PLS_INTEGER;
    L_AFTER_TOKEN      PLS_INTEGER;
    L_TOTAL            NUMBER := 0;
    L_ROW_COUNT        PLS_INTEGER := 0;
    L_COPY_COUNT       PLS_INTEGER := 0;
    L_TO_COUNT         PLS_INTEGER := 0;
    L_TOTAL_WORDS      VARCHAR2(4000);

    FUNCTION ESC (P_VALUE IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN APEX_ESCAPE.HTML(NVL(P_VALUE, ''));
    END ESC;

    FUNCTION ESC_MULTILINE (P_VALUE IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN REPLACE(ESC(P_VALUE), CHR(10), '<br>');
    END ESC_MULTILINE;

    FUNCTION BN_DIGITS (P_VALUE IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN TRANSLATE(P_VALUE, '0123456789', '০১২৩৪৫৬৭৮৯');
    END BN_DIGITS;

    FUNCTION BN_DATE (P_DATE IN DATE) RETURN VARCHAR2 IS
        L_MONTH VARCHAR2(30);
    BEGIN
        L_MONTH := CASE TO_CHAR(P_DATE, 'MM')
            WHEN '01' THEN 'জানুয়ারি'
            WHEN '02' THEN 'ফেব্রুয়ারি'
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
        RETURN BN_DIGITS(TO_CHAR(P_DATE, 'DD')) || ' ' || L_MONTH || ', '
               || BN_DIGITS(TO_CHAR(P_DATE, 'YYYY')) || ' খ্রি.';
    END BN_DATE;

    FUNCTION DISPLAY_MONEY (P_AMOUNT IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN BN_DIGITS(
            TO_CHAR(NVL(P_AMOUNT, 0),
                    'FM999G999G999G990D00',
                    'NLS_NUMERIC_CHARACTERS=''.,''')
        );
    END DISPLAY_MONEY;

    FUNCTION BN_HEAD_NAME (
        P_HEADCODE IN VARCHAR2,
        P_NAME     IN VARCHAR2
    ) RETURN VARCHAR2 IS
        L_NAME VARCHAR2(200) := UPPER(TRIM(P_NAME));
    BEGIN
        RETURN CASE
            WHEN LPAD(TRIM(P_HEADCODE), 3, '0') = '001' THEN 'মূল মঞ্জুরি'
            WHEN L_NAME IN ('BASIC', 'BASIC SALARY') THEN 'মূল মঞ্জুরি'
            WHEN L_NAME IN ('HOUSE RENT', 'HOUSE RENT ALLOWANCE') THEN 'বাড়ি ভাড়া ভাতা'
            WHEN L_NAME IN ('CONVEYANCE', 'CONVEYANCE ALLOWANCE') THEN 'যাতায়াত ভাতা'
            WHEN L_NAME IN ('MEDICAL', 'MEDICAL ALLOWANCE') THEN 'চিকিৎসা ভাতা'
            WHEN L_NAME = 'FOOD ALLOWANCE' THEN 'খাদ্য ভাতা'
            WHEN L_NAME = 'SPECIAL ALLOWANCE' THEN 'বিশেষ ভাতা'
            WHEN L_NAME = 'OTHER ALLOWANCE' THEN 'অন্যান্য ভাতা'
            ELSE NVL(P_NAME, P_HEADCODE)
        END;
    END BN_HEAD_NAME;

    PROCEDURE EMIT_SEGMENT (
        P_OFFSET IN PLS_INTEGER,
        P_LENGTH IN PLS_INTEGER
    ) IS
        L_OFFSET    PLS_INTEGER := P_OFFSET;
        L_REMAINING PLS_INTEGER := GREATEST(NVL(P_LENGTH, 0), 0);
        L_TAKE      PLS_INTEGER;
        L_CHUNK     VARCHAR2(8000);
    BEGIN
        WHILE L_REMAINING > 0 LOOP
            L_TAKE := LEAST(8000, L_REMAINING);
            L_CHUNK := DBMS_LOB.SUBSTR(L_BODY, L_TAKE, L_OFFSET);
            EXIT WHEN L_CHUNK IS NULL;
            HTP.PRN(L_CHUNK);
            L_OFFSET := L_OFFSET + LENGTH(L_CHUNK);
            L_REMAINING := L_REMAINING - LENGTH(L_CHUNK);
        END LOOP;
    END EMIT_SEGMENT;
BEGIN
    L_RENEWAL_ID := TO_NUMBER(:P522_RENEWAL_ID);

    SELECT L.BODY_HTML,
           L.SUBJECT_TEXT,
           L.LETTER_NO,
           L.LETTER_DATE,
           L.STATUS,
           R.RENEWAL_NO,
           R.EMP_CODE_SNAPSHOT,
           R.EMP_NAME_SNAPSHOT,
           R.DESIGNATION_SNAPSHOT,
           R.DEPARTMENT_SNAPSHOT,
           R.LOCATION_SNAPSHOT,
           R.ADDRESS_SNAPSHOT,
           R.COMPANY_SNAPSHOT,
           R.NEW_FROM_DATE,
           R.NEW_TO_DATE,
           S.NAME_BN,
           S.TITLE_BN
      INTO L_BODY,
           L_SUBJECT,
           L_LETTER_NO,
           L_LETTER_DATE,
           L_LETTER_STATUS,
           L_RENEWAL_NO,
           L_EMP_CODE,
           L_EMP_NAME,
           L_DESIGNATION,
           L_DEPARTMENT,
           L_LOCATION,
           L_ADDRESS,
           L_COMPANY,
           L_NEW_FROM,
           L_NEW_TO,
           L_SIGN_NAME,
           L_SIGN_TITLE
      FROM HR_CONTRACT_RENEWAL R
      JOIN EMPLOYEES E
        ON E.ID = R.EMP_ID
      JOIN HR_EMPLOYEE_LETTER L
        ON L.LETTER_ID = R.LETTER_ID
       AND L.CONTRACT_RENEWAL_ID = R.RENEWAL_ID
      JOIN HR_LETTER_SIGNATORY S
        ON S.SIGNATORY_ID = R.SIGNATORY_ID
     WHERE R.RENEWAL_ID = L_RENEWAL_ID
       AND E.COM_ID = :P522_COM_ID
       AND R.STATUS = 'POSTED'
       AND L.STATUS = 'ISSUED';

    SELECT COUNT(*)
      INTO L_TO_COUNT
      FROM HR_CONTRACT_RENEW_RECIPIENT X
      LEFT JOIN HR_LETTER_RECIPIENT M
        ON M.LETTER_RECIPIENT_ID = X.LETTER_RECIPIENT_ID
     WHERE X.RENEWAL_ID = L_RENEWAL_ID
       AND X.SECTION_TYPE = 'TO'
       AND X.IS_ACTIVE = 'Y'
       AND NVL(M.RECIPIENT_NAME_BN, X.LINE_TEXT) IS NOT NULL;

    SELECT COUNT(*)
      INTO L_COPY_COUNT
      FROM HR_CONTRACT_RENEW_RECIPIENT X
      LEFT JOIN HR_LETTER_RECIPIENT M
        ON M.LETTER_RECIPIENT_ID = X.LETTER_RECIPIENT_ID
     WHERE X.RENEWAL_ID = L_RENEWAL_ID
       AND X.SECTION_TYPE = 'COPY'
       AND X.IS_ACTIVE = 'Y'
       AND NVL(M.RECIPIENT_NAME_BN, X.LINE_TEXT) IS NOT NULL;

    HTP.P(q'~
<div id="contractLetterRoot">
<style>
* { box-sizing: border-box; }
.contract-shell {
  max-width: 920px; margin: 0 auto; color: #111;
  font-family: "Noto Sans Bengali", "Hind Siliguri", "SolaimanLipi",
               "Kalpurush", "Arial Unicode MS", sans-serif;
}
.contract-toolbar { display: flex; justify-content: flex-end; margin: 0 0 12px; }
.contract-page {
  position: relative; width: 210mm; min-height: 297mm; margin: 0 auto;
  padding: 26mm 15mm 12mm; background: #fff; border: 1px solid #d7dce1;
  box-shadow: 0 3px 16px rgba(0,0,0,.12); font-size: 13.4px; line-height: 1.55;
}
.department-line { font-weight: 700; font-size: 15px; margin-bottom: 3px; }
.letter-meta { display: flex; justify-content: space-between; gap: 20px; margin: 3px 0 13px; }
.employee-address { line-height: 1.38; margin-bottom: 10px; }
.employee-name { font-weight: 700; }
.letter-subject { font-size: 17px; font-weight: 700; text-decoration: underline; margin: 8px 0 12px; }
.letter-body p { margin: 7px 0; text-align: justify; }
.conditions { margin: 6px 0; padding-left: 31px; }
.conditions li { margin: 5px 0; padding-left: 6px; text-align: justify; }
.salary-block {
  width: min(100%, 520px); margin: 8px auto 9px;
  break-inside: avoid; page-break-inside: avoid;
}
.salary-line {
  display: grid; grid-template-columns: minmax(230px, 1fr) 18px 145px;
  gap: 5px; padding: 2px 7px; align-items: baseline;
}
.salary-label { font-weight: 600; }
.salary-colon { text-align: center; }
.salary-amount { text-align: right; white-space: nowrap; }
.salary-total { border-top: 1px solid #111; margin-top: 3px; font-weight: 700; }
.total-words { text-align: center !important; font-weight: 600; }
.signature-copy-row {
  display: flex; justify-content: space-between; align-items: flex-end;
  gap: 30px; margin-top: 18px; break-inside: avoid; page-break-inside: avoid;
}
.signature-block { flex: 0 0 44%; }
.signature-space { height: 46px; }
.signature-name { font-weight: 700; }
.copy-section { flex: 0 0 50%; font-size: 11.5px; }
.copy-section ol { margin: 3px 0 0; padding-left: 25px; }
.copy-section li { margin: 0; line-height: 1.34; }
.contract-footer {
  margin-top: 12px; border-top: 1px solid #777; padding-top: 4px;
  text-align: center; font-size: 9.5px; color: #444;
}
@page { size: A4 portrait; margin: 0; }
@media print {
  html, body { margin: 0 !important; padding: 0 !important; background: #fff !important; }
  body * { visibility: hidden !important; }
  .contract-page, .contract-page * { visibility: visible !important; }
  .contract-page {
    position: absolute; inset: 0; width: 100%; min-height: auto; margin: 0;
    padding: 26mm 15mm 12mm; border: 0; box-shadow: none;
    -webkit-print-color-adjust: exact; print-color-adjust: exact;
  }
  .contract-toolbar { display: none !important; }
  .salary-block, .signature-copy-row { break-inside: avoid; page-break-inside: avoid; }
  .letter-body p, .conditions li { orphans: 3; widows: 3; }
}
</style>
~');

    HTP.P('<div class="contract-shell" lang="bn">');
    HTP.P('<div class="contract-toolbar"><button type="button" '
          || 'class="t-Button t-Button--hot" onclick="printContractLetter();">'
          || '<span class="fa fa-print" aria-hidden="true"></span> '
          || 'চুক্তি নবায়ন পত্র প্রিন্ট করুন</button></div>');
    HTP.P('<article class="contract-page">');

    HTP.P('<div class="department-line">হিউম্যান রিসোর্স ডিপার্টমেন্ট</div>');
    HTP.P('<div class="letter-meta"><div><strong>সূত্র নং :</strong> '
          || ESC(NVL(L_LETTER_NO, L_RENEWAL_NO))
          || '</div><div><strong>তারিখ :</strong> '
          || ESC(BN_DATE(L_LETTER_DATE)) || '</div></div>');

    IF L_TO_COUNT > 0 THEN
        HTP.P('<div class="employee-address">প্রতি');
        FOR R IN (
            SELECT NVL(M.RECIPIENT_NAME_BN, X.LINE_TEXT) RECIPIENT_TEXT
              FROM HR_CONTRACT_RENEW_RECIPIENT X
              LEFT JOIN HR_LETTER_RECIPIENT M
                ON M.LETTER_RECIPIENT_ID = X.LETTER_RECIPIENT_ID
             WHERE X.RENEWAL_ID = L_RENEWAL_ID
               AND X.SECTION_TYPE = 'TO'
               AND X.IS_ACTIVE = 'Y'
             ORDER BY X.DISPLAY_ORDER, X.RECIPIENT_ID
        ) LOOP
            HTP.P('<br>' || ESC_MULTILINE(R.RECIPIENT_TEXT));
        END LOOP;
        HTP.P('</div>');
    ELSE
        HTP.P('<div class="employee-address"><span class="employee-name">জনাব '
              || ESC(L_EMP_NAME) || '</span><br>Staff No. # '
              || ESC(L_EMP_CODE) || ',<br>'
              || ESC(L_DESIGNATION)
              || CASE WHEN L_DEPARTMENT IS NOT NULL THEN ', ' || ESC(L_DEPARTMENT) END
              || ',<br>' || ESC(L_COMPANY)
              || CASE WHEN L_LOCATION IS NOT NULL THEN ',<br>' || ESC(L_LOCATION) END
              || CASE WHEN L_ADDRESS IS NOT NULL THEN ', ' || ESC_MULTILINE(L_ADDRESS) END
              || '।</div>');
    END IF;

    HTP.P('<div class="letter-subject">বিষয় : ' || ESC(L_SUBJECT) || '।</div>');
    HTP.P('<div class="letter-body">');

    L_TOKEN_POS := DBMS_LOB.INSTR(L_BODY, '#SALARY_DETAILS#');
    IF L_TOKEN_POS > 0 THEN
        EMIT_SEGMENT(1, L_TOKEN_POS - 1);
    ELSE
        EMIT_SEGMENT(1, DBMS_LOB.GETLENGTH(L_BODY));
    END IF;

    HTP.P('<div class="salary-block">');
    FOR R IN (
        SELECT D.HEADCODE,
               NVL(D.HEAD_NAME, NVL(AH.HEAD_NAME, D.HEADCODE)) HEAD_NAME,
               D.NEW_AMOUNT
          FROM HR_CONTRACT_RENEWAL_SALARY D
          LEFT JOIN ALLOWANCE_HEAD AH ON AH.HEAD_ID = D.SLNO
         WHERE D.RENEWAL_ID = L_RENEWAL_ID
           AND D.INCLUDE_IN_LETTER = 'Y'
           AND NVL(D.HEAD_TYPE, NVL(AH.HEAD_TYPE, 'EARNING')) = 'EARNING'
           AND NVL(D.NEW_AMOUNT, 0) <> 0
         ORDER BY NVL(D.PRINT_ORDER, NVL(AH.PRINT_ORDER, D.SLNO)), D.SLNO
    ) LOOP
        L_ROW_COUNT := L_ROW_COUNT + 1;
        L_TOTAL := L_TOTAL + NVL(R.NEW_AMOUNT, 0);
        HTP.P('<div class="salary-line"><div class="salary-label">'
              || ESC(BN_HEAD_NAME(R.HEADCODE, R.HEAD_NAME))
              || '</div><div class="salary-colon">:</div><div class="salary-amount">'
              || DISPLAY_MONEY(R.NEW_AMOUNT) || '</div></div>');
    END LOOP;

    IF L_ROW_COUNT = 0 THEN
        HTP.P('<div>বেতন-ভাতার বিবরণ পাওয়া যায়নি।</div>');
    ELSE
        HTP.P('<div class="salary-line salary-total"><div class="salary-label">মোট</div>'
              || '<div class="salary-colon">=</div><div class="salary-amount">'
              || DISPLAY_MONEY(L_TOTAL) || '</div></div>');
    END IF;
    HTP.P('</div>');

    IF L_ROW_COUNT > 0 THEN
        BEGIN
            L_TOTAL_WORDS := F_INWORD_TK_BN(L_TOTAL);
        EXCEPTION
            WHEN OTHERS THEN
                L_TOTAL_WORDS := DISPLAY_MONEY(L_TOTAL) || ' টাকা মাত্র';
        END;
        HTP.P('<p class="total-words">(' || ESC(L_TOTAL_WORDS) || ');</p>');
    END IF;

    IF L_TOKEN_POS > 0 THEN
        L_AFTER_TOKEN := L_TOKEN_POS + LENGTH('#SALARY_DETAILS#');
        EMIT_SEGMENT(
            L_AFTER_TOKEN,
            DBMS_LOB.GETLENGTH(L_BODY) - L_AFTER_TOKEN + 1
        );
    END IF;

    HTP.P('</div>');
    HTP.P('<div class="signature-copy-row">');
    HTP.P('<div class="signature-block"><div class="signature-space"></div>'
          || '<div class="signature-name">' || ESC(L_SIGN_NAME) || '</div>'
          || '<div>' || ESC(L_SIGN_TITLE) || '</div></div>');

    IF L_COPY_COUNT > 0 THEN
        HTP.P('<div class="copy-section"><strong>অনুলিপিঃ</strong><ol>');
        FOR R IN (
            SELECT NVL(M.RECIPIENT_NAME_BN, X.LINE_TEXT) RECIPIENT_TEXT
              FROM HR_CONTRACT_RENEW_RECIPIENT X
              LEFT JOIN HR_LETTER_RECIPIENT M
                ON M.LETTER_RECIPIENT_ID = X.LETTER_RECIPIENT_ID
             WHERE X.RENEWAL_ID = L_RENEWAL_ID
               AND X.SECTION_TYPE = 'COPY'
               AND X.IS_ACTIVE = 'Y'
             ORDER BY X.DISPLAY_ORDER, X.RECIPIENT_ID
        ) LOOP
            HTP.P('<li>' || ESC_MULTILINE(R.RECIPIENT_TEXT) || '</li>');
        END LOOP;
        HTP.P('</ol></div>');
    END IF;

    HTP.P('</div>');
    HTP.P('<footer class="contract-footer">'
          || ESC(L_COMPANY) || ' | ' || ESC(L_RENEWAL_NO)
          || ' | মেয়াদ: ' || ESC(BN_DATE(L_NEW_FROM))
          || ' - ' || ESC(BN_DATE(L_NEW_TO))
          || CASE WHEN L_LETTER_STATUS = 'ISSUED' THEN ' | চূড়ান্ত' ELSE '' END
          || '</footer>');
    HTP.P('</article></div></div>');

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        HTP.P('<div class="t-Alert t-Alert--warning t-Alert--defaultIcons">'
              || '<div class="t-Alert-wrap"><div class="t-Alert-content">'
              || '<div class="t-Alert-header"><h2 class="t-Alert-title">'
              || 'No final contract renewal letter was found.'
              || '</h2></div></div></div></div>');
    WHEN VALUE_ERROR THEN
        HTP.P('<div class="t-Alert t-Alert--danger t-Alert--defaultIcons">Invalid renewal ID.</div>');
    WHEN OTHERS THEN
        HTP.P('<div class="t-Alert t-Alert--danger t-Alert--defaultIcons">'
              || APEX_ESCAPE.HTML(SQLERRM) || '</div>');
END;
