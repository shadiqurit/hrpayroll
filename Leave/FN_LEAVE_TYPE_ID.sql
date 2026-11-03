-- Numeric LEAVE_REQUEST.LEAVE_TYPE values are exact LT_IDs.
-- Character short codes use the company-specific code before a global code.
CREATE OR REPLACE FUNCTION HRMS.fn_leave_type_id(
    p_leave_type VARCHAR2, p_company_id NUMBER, p_active_only NUMBER DEFAULT 1)
    RETURN NUMBER AUTHID DEFINER IS
    l_value VARCHAR2(100) := UPPER(TRIM(p_leave_type));
    l_id NUMBER;
BEGIN
    IF l_value IS NULL OR p_company_id IS NULL
       OR NVL(p_active_only, 1) NOT IN (0, 1) THEN
        RAISE_APPLICATION_ERROR(-20832, 'A leave type and applicant company are required.');
    END IF;
    IF REGEXP_LIKE(l_value, '^[0-9]+$') THEN
        SELECT lt_id INTO l_id FROM leave_types
         WHERE lt_id = TO_NUMBER(l_value)
           AND (com_id = p_company_id OR com_id IS NULL)
           AND (NVL(p_active_only, 1) = 0 OR active_flag = 'Y');
    ELSE
        SELECT lt.lt_id INTO l_id FROM leave_types lt
         WHERE UPPER(TRIM(lt.short_code)) = l_value
           AND (lt.com_id = p_company_id OR lt.com_id IS NULL)
           AND (NVL(p_active_only, 1) = 0 OR lt.active_flag = 'Y')
           AND (lt.com_id = p_company_id OR NOT EXISTS (
               SELECT 1 FROM leave_types company_type
                WHERE company_type.com_id = p_company_id
                  AND UPPER(TRIM(company_type.short_code)) = l_value
                  AND (NVL(p_active_only, 1) = 0 OR company_type.active_flag = 'Y')));
    END IF;
    RETURN l_id;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20832, 'Leave type is missing, inactive, or belongs to another company.');
    WHEN TOO_MANY_ROWS THEN
        RAISE_APPLICATION_ERROR(-20833, 'Ambiguous leave short code; correct the leave type setup.');
END fn_leave_type_id;
/
