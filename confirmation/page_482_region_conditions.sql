/*
  Oracle APEX Page 482 - confirmation-letter region conditions

  Set each region's Server-side Condition Type to "Rows returned" and paste
  the corresponding query below. These conditions are intentionally mutually
  exclusive, so the page renders only one confirmation letter.
*/

/* Region 1: existing English letter (grades 1-14) */
SELECT 1
  FROM hr_confirmation c
 WHERE c.confirm_id = TO_NUMBER(:P482_CONFIRM_ID)
   AND c.grade_order BETWEEN 1 AND 14;

/* Region 2: Bengali letter (grades 15-20) */
SELECT 1
  FROM hr_confirmation c
 WHERE c.confirm_id = TO_NUMBER(:P482_CONFIRM_ID)
   AND c.grade_order BETWEEN 15 AND 20;

