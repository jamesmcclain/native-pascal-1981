INTERFACE;
UNIT descriptorapi (PCells, shared, Relay, Replace);
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
VAR shared: PCells;
FUNCTION Relay(src: PCells): PCells;
PROCEDURE Replace(VAR dest: PCells; src: PCells);
END;
