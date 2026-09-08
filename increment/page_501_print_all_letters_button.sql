/*
  Oracle APEX Page 501 - Print All Increment Letters
  Region Type : PL/SQL Dynamic Content
  Region Name : Print All Letters
  Static ID   : PRINT_ALL_LETTERS_REGION

  Place this region above the Increment Register report.

  Region property:
    Page Items to Submit = P501_COM_ID,P501_SALARY_MONTH

  Dynamic Action:
    Event              = Change
    Selection Type     = Item(s)
    Item(s)            = P501_COM_ID,P501_SALARY_MONTH
    True Action        = Refresh
    Affected Elements  = Region / PRINT_ALL_LETTERS_REGION

  P501_SALARY_MONTH must contain one YYYYMM value. The generated URL is
  checksum-safe and opens Page 503 in a new tab. P503_INCREMENT_ID is cleared,
  so Page 503 prints every POSTED letter for that company and salary month.

  Page authorization: INC_VIEW
  APEX source paste  : paste the PL/SQL block below as-is.
*/

DECLARE
    l_print_url    VARCHAR2(32767);
    l_letter_count PLS_INTEGER := 0;
BEGIN
    IF :P501_COM_ID IS NOT NULL AND :P501_SALARY_MONTH IS NOT NULL THEN
        SELECT COUNT(*)
          INTO l_letter_count
          FROM hr_employee_increment i
         WHERE i.com_id = TO_NUMBER(:P501_COM_ID)
           AND i.salary_month = TO_NUMBER(:P501_SALARY_MONTH)
           AND i.status = 'POSTED';

        l_print_url := apex_page.get_url(
            p_page        => 503,
            p_clear_cache => '503',
            p_items       => 'P503_COM_ID,P503_SALARY_MONTH,P503_INCREMENT_ID',
            p_values      => TO_CHAR(:P501_COM_ID)
                             || ',' || TO_CHAR(:P501_SALARY_MONTH) || ','
        );

        IF l_letter_count > 0 THEN
            htp.p(
                '<a class="t-Button t-Button--hot t-Button--iconLeft"' ||
                ' href="' || apex_escape.html_attribute(l_print_url) || '"' ||
                ' target="_blank" rel="noopener">' ||
                '<span class="t-Icon fa fa-print" aria-hidden="true"></span>' ||
                '<span class="t-Button-label">Print All Letters (' ||
                TO_CHAR(l_letter_count) || ')</span></a>'
            );
        ELSE
            htp.p(
                '<button type="button" class="t-Button" disabled>' ||
                'No Salary Done Letters</button>'
            );
        END IF;
    ELSE
        htp.p(
            '<button type="button" class="t-Button" disabled>' ||
            'Select Company and Salary Month to Print All</button>'
        );
    END IF;
END;

