{ Interface of a unit in a USES cycle; see err_uses_cycle.pas. }

INTERFACE;
UNIT cycle_a;
USES cycle_b;
PROCEDURE PA;
END;
