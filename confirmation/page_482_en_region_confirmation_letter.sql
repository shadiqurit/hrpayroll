DECLARE

    v_confirm_id           NUMBER;
    v_emp_id               NUMBER;
    v_confirm_date         DATE;
    v_status               VARCHAR2(20);
    v_grade_order          NUMBER;

    v_old_basic            NUMBER := 0;
    v_proposed_basic       NUMBER := 0;
    v_old_gross            NUMBER := 0;
    v_proposed_gross       NUMBER := 0;

    v_increment_eligible   VARCHAR2(1);
    v_increment_amount     NUMBER := 0;
    v_created_date         DATE;
    v_submitted_date       DATE;
    v_approved_date        DATE;
    v_remarks              VARCHAR2(1000);
   

    /* ============================================================
       EMPLOYEE
       ============================================================ */
    v_emp_code             VARCHAR2(100);
    v_emp_name             VARCHAR2(300);
    v_grade                VARCHAR2(100);
    v_designation          VARCHAR2(300);
    v_department           VARCHAR2(300);
    v_location             VARCHAR2(300);
    v_location_code        VARCHAR2(50);
    v_businessunit         VARCHAR2(300);
    v_join_date            DATE;

    /* ============================================================
       SALARY
       ============================================================ */
    v_scale_text           VARCHAR2(1000);
    v_total_earning        NUMBER := 0;

    /* ============================================================
       LETTER
       ============================================================ */
    v_letter_no            VARCHAR2(100);
    v_letter_date          DATE;

BEGIN

    /* ============================================================
       1. CONFIRMATION ID
       ============================================================ */
    v_confirm_id := TO_NUMBER(:P482_CONFIRM_ID);


    /* ============================================================
       2. CONFIRMATION INFORMATION
       ============================================================ */
    SELECT c.emp_id,
           c.confirm_date,
           c.status,
           c.grade_order,
           NVL(c.old_basic, 0),
           NVL(c.proposed_basic, 0),
           NVL(c.old_gross, 0),
           NVL(c.proposed_gross, 0),
           NVL(c.increment_eligible, 'N'),
           NVL(c.increment_amount, 0),
           c.created_date,
           c.submitted_date,
           c.approved_date,
           c.remarks

      INTO v_emp_id,
           v_confirm_date,
           v_status,
           v_grade_order,
           v_old_basic,
           v_proposed_basic,
           v_old_gross,
           v_proposed_gross,
           v_increment_eligible,
           v_increment_amount,
           v_created_date,
           v_submitted_date,
           v_approved_date,
           v_remarks

      FROM hr_confirmation c
     WHERE c.confirm_id = v_confirm_id;


    /* ============================================================
       3. EMPLOYEE INFORMATION
       ============================================================ */
    -- SELECT NVL(v.empcode, '-'),
    --        NVL(v.fullname, '-'),
    --        v.join_date,
    --        NVL(v.grade, '-'),
    --        NVL(v.designation, '-'),
    --        NVL(v.department, '-'),
    --        NVL(v.locationname, '-')

    --   INTO v_emp_code,
    --        v_emp_name,
    --        v_join_date,
    --        v_grade,
    --        v_designation,
    --        v_department,
    --        v_location

    --   FROM v_emp v
    --  WHERE v.emp_id = v_emp_id;

    SELECT NVL(v.empcode, '-'),
           NVL(v.fullname, '-'),
           v.join_date,
           NVL(v.grade, '-'),
           NVL(v.designation, '-'),
           NVL(v.department, '-'),
           NVL(v.locationname, '-'),
           NVL(v.loccode, '-'),
           NVL(v.locationname, '-')
      INTO v_emp_code,
           v_emp_name,
           v_join_date,
           v_grade,
           v_designation,
           v_department,
           v_location,
           v_location_code,
           v_businessunit
      FROM v_emp v
     WHERE v.emp_id = v_emp_id;


    /* ============================================================
       4. PAY SCALE
       ============================================================ */
    BEGIN

        SELECT 'Tk. '
               || TO_CHAR(
                      m.start_basic,
                      'FM999G999G999G990'
                  )
               || ' - '
               || TO_CHAR(
                      m.increment_1,
                      'FM999G999G990'
                  )
               || ' x '
               || TO_CHAR(m.steps_before_eb)
               || ' - '
               || TO_CHAR(
                      m.eb_basic,
                      'FM999G999G999G990'
                  )
               || ' - '
               || TO_CHAR(
                      m.increment_2,
                      'FM999G999G990'
                  )
               || ' x '
               || TO_CHAR(m.steps_after_eb)
               || ' - '
               || TO_CHAR(
                      m.max_basic,
                      'FM999G999G999G990'
                  )

          INTO v_scale_text

          FROM (
                SELECT p.*
                  FROM pay_scale_master p
                 WHERE p.grade_id =
                       (
                           SELECT hc.job_id
                             FROM hr_confirmation hc
                            WHERE hc.confirm_id = v_confirm_id
                       )

                   AND NVL(p.is_active, 'Y') = 'Y'

                   AND TRUNC(v_confirm_date) >=
                       NVL(
                           TRUNC(p.effective_from),
                           DATE '1900-01-01'
                       )

                   AND TRUNC(v_confirm_date) <=
                       NVL(
                           TRUNC(p.effective_to),
                           DATE '2999-12-31'
                       )

                 ORDER BY
                       NVL(
                           p.effective_from,
                           DATE '1900-01-01'
                       ) DESC,
                       p.revision_no DESC
               ) m

         WHERE ROWNUM = 1;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_scale_text := NULL;
    END;


    /* ============================================================
       5. TOTAL EARNING
       ============================================================ */
    SELECT NVL(
               SUM(NVL(d.proposed_amount, 0)),
               0
           )
      INTO v_total_earning

      FROM hr_confirmation_salary_dtl d
     WHERE d.confirm_id = v_confirm_id
       AND NVL(d.is_active, 'Y') = 'Y'
       AND NVL(d.show_in_letter, 'Y') = 'Y'
       AND d.head_type = 'EARNING';


    /* ============================================================
       6. LETTER DATE
       ============================================================ */
    v_letter_date :=
        NVL(
            v_approved_date,
            NVL(
                v_submitted_date,
                v_created_date
            )
        );


    /* ============================================================
       7. LETTER NUMBER
       ============================================================ */
    v_letter_no :=
           'HR/CONF/'
        || TO_CHAR(
               NVL(v_letter_date, SYSDATE),
               'YYYY'
           )
        || '/'
        || LPAD(
               v_confirm_id,
               6,
               '0'
           );


    /* ============================================================
       8. PRINT BUTTON
       OUTSIDE PRINTABLE DIV
       ============================================================ */
    htp.p(q'~
<div class="print-toolbar no-print">

    <button type="button"
            class="t-Button t-Button--hot"
            onclick="printContent();">

        <span class="fa fa-print"></span>

        Print Confirmation Letter

    </button>

</div>
~');


    /* ============================================================
       9. PRINT DIV START
       ============================================================ */
    htp.p(
        '<div id="divToPrint" class="confirmation-letter">'
    );


    /* ============================================================
       10. STYLE
       ============================================================ */
    htp.p(q'~
<style>

* {
    box-sizing: border-box;
}


/* ============================================================
   MAIN PRINT AREA
   ============================================================ */

.confirmation-letter {

    width: 210mm;

    margin: 0 auto;

    padding: 0;

    background: #ffffff;

    color: #111111;

    font-family:
        Arial,
        Helvetica,
        sans-serif;

    font-size: 18px;

    line-height: 2;
}


/* ============================================================
   A4 CONTENT
   ============================================================ */

.letter-page {

    position: relative;

    width: 210mm;

    min-height: 297mm;

    margin: 10px auto;

    /* Keep the pre-printed company-pad header and page edges clear. */
    padding:
        30mm
        14mm
        8mm
        14mm;

    background: #ffffff;

    box-sizing: border-box;
}


/* ============================================================
   CONTENT LAYER
   ============================================================ */

.letter-content {

    position: relative;

    z-index: 2;
}


/* ============================================================
   PRINT TOOLBAR
   ============================================================ */

.print-toolbar {

    width: 210mm;

    margin:
        10px
        auto;

    text-align: right;
}


/* ============================================================
   DRAFT WATERMARK - NORMAL SCREEN
   ============================================================ */

.draft-watermark {

    position: absolute;

    top: 40%;

    left: 0;

    width: 100%;

    text-align: center;

    transform:
        rotate(-35deg);

    transform-origin: center;

    font-size: 55px;

    font-weight: 700;

    letter-spacing: 5px;

    color:
        rgba(
            180,
            0,
            0,
            0.09
        );

    z-index: 10;

    pointer-events: none;

    user-select: none;
}


/* ============================================================
   HEADER
   ============================================================ */

.hr-department {

    margin-bottom: 8px;

    font-size: 16px;

    font-weight: 700;
}


.ref-row {

    display: flex;

    justify-content:
        space-between;

    align-items:
        center;

    margin-top: 4px;

    margin-bottom: 20px;

    gap: 20px;
}


/* ============================================================
   EMPLOYEE BLOCK
   ============================================================ */

.employee-block {

    margin-bottom: 18px;
}


.employee-name {

    font-weight: 700;
}


/* ============================================================
   LETTER TITLE
   ============================================================ */

.letter-title {

    margin:
        18px
        0
        22px
        0;

    text-align: left;

    font-size: 18px;

    font-weight: 700;

   
}


/* ============================================================
   PARAGRAPH
   ============================================================ */

.letter-paragraph {

    margin:
        10px
        0;

    text-align:
        justify;
}


/* ============================================================
   TERMS
   ============================================================ */

.terms-title {

    margin: 18px;

    font-size: 18px;

    font-weight: 700;
}


.terms {

    margin:
        0;

    padding-left:
        28px;
}


.terms > li {
    
    font-size: 17px;
    line-height: 2;
    margin-bottom:
        15px;

    padding-left:
        5px;

    text-align:
        justify;

    break-inside:
        avoid;

    page-break-inside:
        avoid;
}


/* ============================================================
   SALARY BREAKDOWN
   ============================================================ */

.salary-breakdown {

    width: auto;

    min-width:
        400px;

    border-collapse:
        collapse;

    margin:
        12px
        0
        12px
        0;

    break-inside:
        avoid;

    page-break-inside:
        avoid;
}


.salary-breakdown td {

    padding:
        3px
        7px;

    vertical-align:
        top;
}


.salary-label {

    width:
        210px;

    font-weight:
        600;
}


.salary-colon {

    width:
        15px;

    text-align:
        center;
}


.salary-amount {

    width:
        135px;

    text-align:
        right;

    white-space:
        nowrap;
}


.salary-total td {

    border-top:
        1px
        solid
        #333333;

    padding-top:
        6px;

    font-weight:
        700;
}


/* ============================================================
   SIGNATURE
   ============================================================ */

.signature-block {

    margin-top:
        45px;

    break-inside:
        avoid;

    page-break-inside:
        avoid;
}


.signature-space {

    height:
        65px;
}


.signature-name {

    font-weight:
        700;
}


/* ============================================================
   COPY
   ============================================================ */

.copy-section {

    margin-top:
        35px;

    font-size:
        16px;

    break-inside:
        avoid;

    page-break-inside:
        avoid;
}


.copy-section ol {

    margin-top:
        5px;

    padding-left:
        22px;
}


.copy-section li {

    margin-bottom:
        2px;

    text-align:
        left;
}


.signature-copy-row {
    display: flex;
    flex-direction: row;
    justify-content: space-between;
    align-items: flex-end;

    width: 100%;

    margin-top: 45px;

    gap: 30px;

    break-inside: avoid;
    page-break-inside: avoid;
}


/* LEFT SIDE */
.signature-block {
    flex: 0 0 45%;

    margin: 0;

    padding: 0;

    text-align: left;
}


.signature-space {
    height: 65px;
}


.signature-name {
    font-size: 17px;
    font-weight: 700;
    line-height: 1.5;
}


/* RIGHT SIDE */
.copy-section {
    flex: 0 0 48%;

    margin: 0;

    padding: 0;

    font-size: 15px;

    text-align: left;
}


.copy-section ol {
    margin: 4px 0 0 0;
    padding-left: 22px;
}


.copy-section li {
    margin: 0;
    padding: 0;

    line-height: 1.6;

    text-align: left;
}


/* ============================================================
   SCREEN PREVIEW
   ============================================================ */

@media screen {

    .letter-page {

        box-shadow:
            0
            2px
            12px
            rgba(
                0,
                0,
                0,
                0.15
            );
    }

}


/* ============================================================
   PRINT
   ============================================================ */
@media print {

    @page {
        size: A4 portrait;
        /* Repeated on every physical company-pad page. */
        margin: 30mm 14mm 8mm;
    }

    html,
    body {
        width: 100% !important;        
        margin: 0 !important;
        padding: 0 !important;
        background: #ffffff !important;
        /* Force a larger font size and pure black text for print clarity */
        font-size: 17px !important; 
        color: #000000 !important;
        -webkit-print-color-adjust: exact !important;
        print-color-adjust: exact !important;
    }

    #divToPrint,
    .confirmation-letter {
        width: 100% !important;        
        margin: 0 !important;
        padding: 0 !important;
        background: #ffffff !important;
        /* Ensure the larger size inherits down into your specific container */
        font-size: 17px !important;
        color: #000000 !important;
    }

    .letter-page {
        width: 100% !important;
        min-height: auto !important;
        margin: 0 !important;
        /* @page supplies the repeating print clearance; avoid doubling it. */
        padding: 0 !important;
        box-shadow: none !important;
    }

    .draft-watermark {
        position: fixed !important;
        top: 42% !important;
        left: 0 !important;
        width: 100% !important;
        text-align: center !important;
        transform: rotate(-35deg) !important;
        transform-origin: center !important;
        font-size: 55px !important;
        font-weight: 700 !important;
        letter-spacing: 5px !important;
        color: rgba(180, 0, 0, 0.09) !important;
        z-index: 9999 !important;
        pointer-events: none !important;
    }

    .letter-content {
        position: relative !important;
        z-index: 2 !important;
    }

    .no-print,
    .print-toolbar {
        display: none !important;
    }

    .salary-breakdown,
    .salary-breakdown tr {
        break-inside: avoid !important;
        page-break-inside: avoid !important;
    }

    .signature-block,
    .copy-section {
        break-inside: avoid !important;
        page-break-inside: avoid !important;
    }

    .signature-copy-row {
        display: flex !important;
        flex-direction: row !important;
        justify-content: space-between !important;
        align-items: flex-end !important;

        width: 100% !important;

        gap: 30px !important;

        break-inside: avoid !important;
        page-break-inside: avoid !important;
    }

    .signature-block {
        flex: 0 0 45% !important;
        width: 45% !important;

        margin: 0 !important;
    }

    .copy-section {
        flex: 0 0 48% !important;
        width: 48% !important;

        margin: 0 !important;
    }

    p {
        orphans: 3;
        widows: 3;
    }
}

</style>
~');


    /* ============================================================
       11. LETTER PAGE
       ============================================================ */
    htp.p(
        '<div class="letter-page">'
    );


    /* ============================================================
       12. DRAFT WATERMARK
       ONLY ONE WATERMARK REQUIRED
       ============================================================ */
    IF UPPER(NVL(v_status, '-')) = 'DRAFT' THEN

        htp.p(
            '<div class="draft-watermark">'
            || 'DRAFT PREVIEW'
            || '</div>'
        );

    END IF;


    /* ============================================================
       13. LETTER CONTENT
       ============================================================ */
    htp.p(
        '<div class="letter-content">'
    );


    /* ============================================================
       HR DEPARTMENT
       ============================================================ */
    htp.p(
        '<div class="hr-department">'
        || 'Human Resources Department'
        || '</div>'
    );


    /* ============================================================
       REFERENCE + DATE
       ============================================================ */
    htp.p(
           '<div class="ref-row">'

        || '<div>'

        || '<strong>Ref:</strong> '

        || apex_escape.html(
               v_letter_no
           )

        || '</div>'


        || '<div>'

        || '<strong>Date:</strong> '

        || apex_escape.html(
               TO_CHAR(
                   NVL(
                       v_letter_date,
                       SYSDATE
                   ),
                   'DD Month YYYY'
               )
           )

        || '</div>'

        || '</div>'
    );


    /* ============================================================
       EMPLOYEE ADDRESS
       ============================================================ */
    htp.p(
        '<div class="employee-block">'
    );


    htp.p(
           '<div class="employee-name">'
        || apex_escape.html(v_emp_name)
        || '</div>'
    );


    htp.p(
           '<div>'
        || 'Employee ID: '
        || apex_escape.html(v_emp_code)
        || '</div>'
    );


    htp.p(
           '<div>'
        || apex_escape.html(v_designation)
        || '</div>'
    );


    htp.p(
           '<div>'
        || apex_escape.html(v_department)
        || '</div>'
    );


    htp.p(
           '<div>'
        || apex_escape.html(v_location)
        || '</div>'
    );


    htp.p(
        '</div>'
    );


    /* ============================================================
       LETTER TITLE
       ============================================================ */
    htp.p(
           '<div class="letter-title">'
        || 'Subject : Job Confirmation'
        || '</div>'
    );


    /* ============================================================
       SALUTATION
       ============================================================ */
    htp.p(q'~
<p class="letter-paragraph">
    Janab
    <br>
    Assalamu Alaikum Wa Rahmatullah.
</p>
~');


    /* ============================================================
       CONFIRMATION TEXT
       ============================================================ */
    htp.p(
           '<p class="letter-paragraph">'

        || 'The Management of The IBN SINA Pharmaceutical Industry PLC (IPI) '
        || 'is pleased to confirm your job as '

        || '<strong>'
        || apex_escape.html(v_designation)
        || '</strong>'

        || ' effective from '

        || '<strong>'
        || apex_escape.html(
               TO_CHAR(
                   v_confirm_date,
                   'DD Month YYYY'
               )
           )
        || '</strong>'

        || ' with the following terms and conditions.'

        || '</p>'
    );


    /* ============================================================
       TERMS HEADING
       ============================================================ */
    htp.p(
        '<div class="terms-title">'
        || 'Terms and Conditions'
        || '</div>'
    );


    /* ============================================================
       TERMS START
       ============================================================ */
    htp.p(
        '<ol class="terms">'
    );


    /* ============================================================
       TERM 1 - SALARY
       ============================================================ */
    htp.p(
        '<li>'
    );


    htp.p(
           'You will be paid monthly salary as per IPI Pay Scale '

        || '<strong>'
        || apex_escape.html(v_grade)
        || '</strong>'

        || ' ('
    );


    IF v_scale_text IS NOT NULL THEN

        htp.p(
            apex_escape.html(
                v_scale_text
            )
        );

    ELSE

        htp.p(
            'Applicable Pay Scale'
        );

    END IF;


    htp.p(
        '). Your salary breakdown is as follows:'
    );


    /* ============================================================
       SALARY TABLE
       ============================================================ */
    htp.p(
        '<table class="salary-breakdown">'
    );


    /* ============================================================
       EARNING HEADS
       ============================================================ */
    FOR r IN
    (
        SELECT d.head_name,
               d.proposed_amount,
               d.display_order,
               d.slno

          FROM hr_confirmation_salary_dtl d

         WHERE d.confirm_id = v_confirm_id

           AND NVL(
                   d.is_active,
                   'Y'
               ) = 'Y'

           AND NVL(
                   d.show_in_letter,
                   'Y'
               ) = 'Y'

           AND d.head_type = 'EARNING'

           AND NVL(
                   d.proposed_amount,
                   0
               ) <> 0

         ORDER BY
               NVL(
                   d.display_order,
                   d.slno
               ),
               d.slno
    )
    LOOP

        htp.p(
               '<tr>'

            || '<td class="salary-label">'
            || apex_escape.html(
                   r.head_name
               )
            || '</td>'

            || '<td class="salary-colon">'
            || ':'
            || '</td>'

            || '<td class="salary-amount">'
            || TO_CHAR(
                   r.proposed_amount,
                   'FM999G999G999G990D00'
               )
            || '</td>'

            || '</tr>'
        );

    END LOOP;


    /* ============================================================
       TOTAL
       ============================================================ */
    htp.p(
           '<tr class="salary-total">'

        || '<td>'
        || 'Total'
        || '</td>'

        || '<td class="salary-colon">'
        || ':'
        || '</td>'

        || '<td class="salary-amount">'
        || TO_CHAR(
               v_total_earning,
               'FM999G999G999G990D00'
           )
        || '</td>'

        || '</tr>'
    );


    htp.p(
        '</table>'
    );


    htp.p(
        '</li>'
    );


    /* ============================================================
       REMAINING TERMS
       ============================================================ */
    htp.p(q'~

<li>
    You will be entitled to statutory leave benefits as per company policy;
</li>

<li>
    You may be assigned to work at any place within the company's
    operational scope and at any time as required by the management;
</li>

<li>
    You will be entitled to 02 (Two) festival bonuses annually,
    equivalent to basic salary;
</li>

<li>
    You will be enrolled as a member of the company's Employees
    Provident Fund and will be entitled to Provident Fund benefits
    as per prevailing rules;
</li>

<li>
    You will be entitled to the company's Employees Gratuity Fund
    as per prevailing rules;
</li>

<li>
    You will be enrolled as a member of the company's Superannuation
    Fund and will be entitled to its benefits according to the
    prevailing regulations;
</li>

<li>
    You will be entitled to a proportionate dividend from the
    company's Profit Sharing Fund (WPPF) every year;
</li>

<li>
    In the event of resignation by an individual or termination of
    employment by the company, the respective party must provide
    notice or notice pay, based on basic salary, in accordance with
    service rules;
</li>

<li>
    You will be governed by the rules and regulations of the company
    in vogue or as amended from time to time by the Board of Directors.
</li>

~');


    htp.p(
        '</ol>'
    );


    /* ============================================================
       FINAL MESSAGE
       ============================================================ */
    htp.p(q'~

<p class="letter-paragraph"
   style="margin-top:30px;">

    May Almighty Allah grant us all the ability to perform our duties
    and responsibilities with excellence.

</p>


<p class="letter-paragraph"
   style="margin-top:25px;">

    Ma'Assalam.

</p>

~');


    /* ============================================================
       SIGNATURE + COPY
       SAME HORIZONTAL SECTION
       SIGNATORY LEFT / COPY RIGHT
       ============================================================ */

    htp.p(q'~

<div class="signature-copy-row">


    <!-- ======================================================
         LEFT SIDE - SIGNATORY
         ====================================================== -->

    <div class="signature-block">

        <div class="signature-space"></div>

~');


    /* ============================================================
       SIGNATORY
       ============================================================ */

    IF UPPER(TRIM(v_location_code)) = 'HO' THEN

        htp.p(q'~

        <div class="signature-name">
            Prof. Dr. A.K.M Sadrul Islam
        </div>

        <div>
            Managing Director
        </div>

~');


    ELSIF UPPER(TRIM(v_location_code)) = 'FAC' THEN

        htp.p(q'~

        <div class="signature-name">
            Md. Kabir Hossain
        </div>

        <div>
            Executive Director (Plants)
        </div>

~');


    ELSE

        htp.p(q'~

        <div class="signature-name">
            Md. Yeanur Rahman
        </div>

        <div>
            Executive Director (Admin)
        </div>

~');

    END IF;

    htp.p(q'~

    </div>

   <div class="copy-section">

        <strong>
            Copy to:
        </strong>

        <ol>

~');

    IF UPPER(TRIM(v_location_code)) = 'FAC' THEN

        htp.p(q'~

        <li>
            ED and Head of Plants
        </li>

        <li>
            Concerned Department Head
        </li>

        <li>
            HRD (Plants)
        </li>

        <li>
            Accounts Department
        </li>

        <li>
            Personal File
        </li>

        <li>
            Office Copy
        </li>

~');


    ELSIF UPPER(TRIM(v_location_code)) = 'HO' THEN

        htp.p(q'~

        <li>
            Head of Department
        </li>

        <li>
            Accounts Department
        </li>

        <li>
            Personal File
        </li>

        <li>
            Office Copy
        </li>

~');

   ELSIF UPPER(TRIM(v_department)) = 'SALES' THEN

        htp.p(q'~

        <li>
            Head of Sales
        </li>

        <li>
            Group Leader
        </li>

        <li>
            Accounts Department
        </li>

        <li>
            Personal File
        </li>

        <li>
            Office Copy
        </li>

~');


    /* ============================================================
       ALL OTHER EMPLOYEES
       ============================================================ */

    ELSE

        htp.p(q'~

        <li>
            Concerned Department Head
        </li>

        <li>
            Accounts Department
        </li>

        <li>
            Personal File
        </li>

        <li>
            Office Copy
        </li>

~');

    END IF;


    /* ============================================================
       CLOSE COPY + HORIZONTAL ROW
       ============================================================ */

    htp.p(q'~

        </ol>

    </div>

</div>

~');


    /* ============================================================
       CLOSE letter-content
       ============================================================ */
    htp.p(
        '</div>'
    );


    /* ============================================================
       CLOSE letter-page
       ============================================================ */
    htp.p(
        '</div>'
    );


    /* ============================================================
       CLOSE divToPrint
       ============================================================ */
    htp.p(
        '</div>'
    );


EXCEPTION

    WHEN NO_DATA_FOUND THEN

        htp.p(q'~
<div class="t-Alert t-Alert--danger t-Alert--defaultIcons">
    <div class="t-Alert-wrap">
        <div class="t-Alert-content">
            <div class="t-Alert-header">
                <h2 class="t-Alert-title">
                    Confirmation information not found.
                </h2>
            </div>
        </div>
    </div>
</div>
~');


    WHEN VALUE_ERROR THEN

        htp.p(q'~
<div class="t-Alert t-Alert--danger t-Alert--defaultIcons">
    <div class="t-Alert-wrap">
        <div class="t-Alert-content">
            <div class="t-Alert-header">
                <h2 class="t-Alert-title">
                    Invalid Confirmation ID.
                </h2>
            </div>
        </div>
    </div>
</div>
~');
    WHEN OTHERS THEN
        htp.p(
               '<div class="t-Alert '
            || 't-Alert--danger '
            || 't-Alert--defaultIcons">'

            || '<div class="t-Alert-wrap">'

            || '<div class="t-Alert-content">'

            || '<div class="t-Alert-header">'

            || '<h2 class="t-Alert-title">'

            || apex_escape.html(
                   SQLERRM
               )
            || '</h2>'
            || '</div>'
            || '</div>'
            || '</div>'
            || '</div>'
        );

END;
