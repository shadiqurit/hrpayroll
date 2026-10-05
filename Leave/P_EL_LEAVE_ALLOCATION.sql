CREATE OR REPLACE PROCEDURE HRMS.p_el_leave_allocation (
    p_year       IN NUMBER,
    p_as_of_date IN DATE DEFAULT SYSDATE
)
AUTHID DEFINER
AS
BEGIN
    -- Update only EL. Store cumulative earned days in the existing yearly
    -- employee/type/year row; reruns replace the total instead of adding it.
    HRMS.p_leave_allocation(
        p_year => p_year,
        p_as_of_date => p_as_of_date,
        p_el_only => 1
    );
END p_el_leave_allocation;
/
