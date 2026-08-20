DROP FUNCTION HRMS.F_INWORD_TK;

CREATE OR REPLACE FUNCTION HRMS.f_inword_tk(p_amount IN NUMBER)
RETURN VARCHAR2
IS
  TYPE t_words IS TABLE OF VARCHAR2(20) INDEX BY PLS_INTEGER;
  v_ones   t_words;
  v_tens   t_words;
  v_result VARCHAR2(4000) := '';
  v_num    NUMBER := TRUNC(ABS(NVL(p_amount, 0)));
  v_paisa  NUMBER := ROUND(MOD(ABS(NVL(p_amount, 0)), 1) * 100);

  FUNCTION two_digits(p_n IN NUMBER) RETURN VARCHAR2 IS
  BEGIN
    IF p_n < 20 THEN
      RETURN v_ones(p_n);
    ELSE
      RETURN v_tens(TRUNC(p_n / 10)) || CASE WHEN MOD(p_n, 10) > 0 THEN '-' || v_ones(MOD(p_n, 10)) END;
    END IF;
  END;

  FUNCTION three_digits(p_n IN NUMBER) RETURN VARCHAR2 IS
  BEGIN
    IF p_n >= 100 THEN
      RETURN v_ones(TRUNC(p_n / 100)) || ' Hundred' || CASE WHEN MOD(p_n, 100) > 0 THEN ' ' || two_digits(MOD(p_n, 100)) END;
    ELSE
      RETURN two_digits(p_n);
    END IF;
  END;

BEGIN
  -- Initialize ones
  v_ones(0) := ''; v_ones(1) := 'One'; v_ones(2) := 'Two'; v_ones(3) := 'Three';
  v_ones(4) := 'Four'; v_ones(5) := 'Five'; v_ones(6) := 'Six'; v_ones(7) := 'Seven';
  v_ones(8) := 'Eight'; v_ones(9) := 'Nine'; v_ones(10) := 'Ten'; v_ones(11) := 'Eleven';
  v_ones(12) := 'Twelve'; v_ones(13) := 'Thirteen'; v_ones(14) := 'Fourteen';
  v_ones(15) := 'Fifteen'; v_ones(16) := 'Sixteen'; v_ones(17) := 'Seventeen';
  v_ones(18) := 'Eighteen'; v_ones(19) := 'Nineteen';

  -- Initialize tens
  v_tens(2) := 'Twenty'; v_tens(3) := 'Thirty'; v_tens(4) := 'Forty';
  v_tens(5) := 'Fifty'; v_tens(6) := 'Sixty'; v_tens(7) := 'Seventy';
  v_tens(8) := 'Eighty'; v_tens(9) := 'Ninety';

  IF p_amount = 0 OR p_amount IS NULL THEN
    RETURN 'Zero Taka Only.';
  END IF;

  -- Crore (1,00,00,000)
  IF v_num >= 10000000 THEN
    v_result := v_result || three_digits(TRUNC(v_num / 10000000)) || ' Crore ';
    v_num := MOD(v_num, 10000000);
  END IF;

  -- Lakh (1,00,000)
  IF v_num >= 100000 THEN
    v_result := v_result || two_digits(TRUNC(v_num / 100000)) || ' Lakh ';
    v_num := MOD(v_num, 100000);
  END IF;

  -- Thousand (1,000)
  IF v_num >= 1000 THEN
    v_result := v_result || two_digits(TRUNC(v_num / 1000)) || ' Thousand ';
    v_num := MOD(v_num, 1000);
  END IF;

  -- Hundred and remainder
  IF v_num > 0 THEN
    v_result := v_result || three_digits(v_num);
  END IF;

  -- Append Taka and Paisa
  v_result := TRIM(v_result);
  IF v_paisa > 0 THEN
    v_result := v_result || ' Taka and ' || two_digits(v_paisa) || ' Paisa Only.';
  ELSE
    v_result := v_result || ' Taka Only.';
  END IF;

  RETURN v_result;
END f_inword_tk;
/
