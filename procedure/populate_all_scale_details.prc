DROP PROCEDURE HRMS.POPULATE_ALL_SCALE_DETAILS;

CREATE OR REPLACE PROCEDURE HRMS.populate_all_scale_details AS
BEGIN
    FOR rec IN (SELECT scale_id FROM pay_scale_master WHERE is_active = 'Y') LOOP
        populate_scale_detail(rec.scale_id);
    END LOOP;
END;
/
