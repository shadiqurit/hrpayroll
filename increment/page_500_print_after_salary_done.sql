/*
  Oracle APEX Page 500
  Add a PRINT_INCREMENT_LETTERS button after FINAL_SUBMIT.

  Button configuration:
    Label        : Print Increment Letters
    Action       : Redirect to Page in this Application
    Target Page  : 503
    Clear Cache  : 503
    Set Items    :
      P503_COM_ID          = &P500_COM_ID.
      P503_SALARY_MONTH    = &P500_SALARY_MONTH.
      P503_INCREMENT_ID    = (leave empty)
    Target        : New Window
    Authorization : INC_VIEW

  Server-side Condition:
    Type: Rows returned
    Paste the query below without its trailing semicolon.

  The condition deliberately checks POSTED, not APPLIED. Salary application
  alone is reversible; the letter becomes printable only after Final Submit
  changes the increment to POSTED (the user-facing "Salary Done" state).
*/

SELECT 1
  FROM hr_employee_increment i
 WHERE i.com_id = TO_NUMBER(:P500_COM_ID)
   AND i.salary_month = TO_NUMBER(:P500_SALARY_MONTH)
   AND i.status = 'POSTED'
   AND ROWNUM = 1;
