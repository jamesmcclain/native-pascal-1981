{ DIALECT: extended }
PROGRAM DescriptorLayout(output);
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER;
     PCells = ^Cells;
     Holder = RECORD data: PCells END;
     Slots = ARRAY [0..1] OF PCells;
VAR p: PCells; h: Holder; a: Slots;
BEGIN
  WRITELN(SIZEOF(p), ' ', SIZEOF(h), ' ', SIZEOF(a))
END.
