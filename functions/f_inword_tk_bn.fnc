CREATE OR REPLACE FUNCTION HRMS.f_inword_tk_bn(p_amount IN NUMBER)
RETURN VARCHAR2
IS
    TYPE t_words IS TABLE OF VARCHAR2(30) INDEX BY PLS_INTEGER;
    l_words   t_words;
    l_number  NUMBER := TRUNC(ABS(NVL(p_amount, 0)));
    l_paisa   PLS_INTEGER := ROUND(MOD(ABS(NVL(p_amount, 0)), 1) * 100);

    FUNCTION integer_words(p_number IN NUMBER) RETURN VARCHAR2 IS
        l_n       NUMBER := TRUNC(p_number);
        l_result  VARCHAR2(4000);
        l_part    NUMBER;
    BEGIN
        IF l_n = 0 THEN
            RETURN l_words(0);
        END IF;

        IF l_n >= 10000000 THEN
            l_part := TRUNC(l_n / 10000000);
            l_result := integer_words(l_part) || ' কোটি ';
            l_n := MOD(l_n, 10000000);
        END IF;

        IF l_n >= 100000 THEN
            l_part := TRUNC(l_n / 100000);
            l_result := l_result || integer_words(l_part) || ' লক্ষ ';
            l_n := MOD(l_n, 100000);
        END IF;

        IF l_n >= 1000 THEN
            l_part := TRUNC(l_n / 1000);
            l_result := l_result || integer_words(l_part) || ' হাজার ';
            l_n := MOD(l_n, 1000);
        END IF;

        IF l_n >= 100 THEN
            l_part := TRUNC(l_n / 100);
            l_result := l_result || integer_words(l_part) || 'শত ';
            l_n := MOD(l_n, 100);
        END IF;

        IF l_n > 0 THEN
            l_result := l_result || l_words(l_n);
        END IF;

        RETURN TRIM(REGEXP_REPLACE(l_result, '[[:space:]]+', ' '));
    END integer_words;
BEGIN
    l_words(0)  := 'শূন্য';       l_words(1)  := 'এক';          l_words(2)  := 'দুই';
    l_words(3)  := 'তিন';        l_words(4)  := 'চার';         l_words(5)  := 'পাঁচ';
    l_words(6)  := 'ছয়';         l_words(7)  := 'সাত';         l_words(8)  := 'আট';
    l_words(9)  := 'নয়';         l_words(10) := 'দশ';          l_words(11) := 'এগারো';
    l_words(12) := 'বারো';       l_words(13) := 'তেরো';       l_words(14) := 'চৌদ্দ';
    l_words(15) := 'পনেরো';      l_words(16) := 'ষোলো';       l_words(17) := 'সতেরো';
    l_words(18) := 'আঠারো';      l_words(19) := 'উনিশ';       l_words(20) := 'বিশ';
    l_words(21) := 'একুশ';       l_words(22) := 'বাইশ';       l_words(23) := 'তেইশ';
    l_words(24) := 'চব্বিশ';      l_words(25) := 'পঁচিশ';      l_words(26) := 'ছাব্বিশ';
    l_words(27) := 'সাতাশ';      l_words(28) := 'আটাশ';      l_words(29) := 'ঊনত্রিশ';
    l_words(30) := 'ত্রিশ';       l_words(31) := 'একত্রিশ';    l_words(32) := 'বত্রিশ';
    l_words(33) := 'তেত্রিশ';    l_words(34) := 'চৌত্রিশ';    l_words(35) := 'পঁয়ত্রিশ';
    l_words(36) := 'ছত্রিশ';     l_words(37) := 'সাঁইত্রিশ';   l_words(38) := 'আটত্রিশ';
    l_words(39) := 'ঊনচল্লিশ';  l_words(40) := 'চল্লিশ';      l_words(41) := 'একচল্লিশ';
    l_words(42) := 'বিয়াল্লিশ';  l_words(43) := 'তেতাল্লিশ';   l_words(44) := 'চুয়াল্লিশ';
    l_words(45) := 'পঁয়তাল্লিশ'; l_words(46) := 'ছেচল্লিশ';    l_words(47) := 'সাতচল্লিশ';
    l_words(48) := 'আটচল্লিশ';   l_words(49) := 'ঊনপঞ্চাশ';   l_words(50) := 'পঞ্চাশ';
    l_words(51) := 'একান্ন';      l_words(52) := 'বাহান্ন';     l_words(53) := 'তিপ্পান্ন';
    l_words(54) := 'চুয়ান্ন';    l_words(55) := 'পঞ্চান্ন';     l_words(56) := 'ছাপ্পান্ন';
    l_words(57) := 'সাতান্ন';     l_words(58) := 'আটান্ন';     l_words(59) := 'ঊনষাট';
    l_words(60) := 'ষাট';        l_words(61) := 'একষট্টি';    l_words(62) := 'বাষট্টি';
    l_words(63) := 'তেষট্টি';     l_words(64) := 'চৌষট্টি';    l_words(65) := 'পঁয়ষট্টি';
    l_words(66) := 'ছেষট্টি';     l_words(67) := 'সাতষট্টি';   l_words(68) := 'আটষট্টি';
    l_words(69) := 'ঊনসত্তর';    l_words(70) := 'সত্তর';      l_words(71) := 'একাত্তর';
    l_words(72) := 'বাহাত্তর';    l_words(73) := 'তিয়াত্তর';   l_words(74) := 'চুয়াত্তর';
    l_words(75) := 'পঁচাত্তর';    l_words(76) := 'ছিয়াত্তর';   l_words(77) := 'সাতাত্তর';
    l_words(78) := 'আটাত্তর';    l_words(79) := 'ঊনআশি';     l_words(80) := 'আশি';
    l_words(81) := 'একাশি';      l_words(82) := 'বিরাশি';     l_words(83) := 'তিরাশি';
    l_words(84) := 'চুরাশি';     l_words(85) := 'পঁচাশি';     l_words(86) := 'ছিয়াশি';
    l_words(87) := 'সাতাশি';     l_words(88) := 'আটাশি';     l_words(89) := 'ঊননব্বই';
    l_words(90) := 'নব্বই';      l_words(91) := 'একানব্বই';  l_words(92) := 'বিরানব্বই';
    l_words(93) := 'তিরানব্বই';  l_words(94) := 'চুরানব্বই'; l_words(95) := 'পঁচানব্বই';
    l_words(96) := 'ছিয়ানব্বই'; l_words(97) := 'সাতানব্বই';  l_words(98) := 'আটানব্বই';
    l_words(99) := 'নিরানব্বই';

    IF l_paisa = 100 THEN
        l_number := l_number + 1;
        l_paisa := 0;
    END IF;

    IF p_amount < 0 THEN
        RETURN 'মাইনাস ' || integer_words(l_number) || ' টাকা'
               || CASE WHEN l_paisa > 0
                       THEN ' ' || integer_words(l_paisa) || ' পয়সা' END;
    END IF;

    RETURN integer_words(l_number) || ' টাকা'
           || CASE WHEN l_paisa > 0
                   THEN ' ' || integer_words(l_paisa) || ' পয়সা' END;
END f_inword_tk_bn;
/
