INTERFACE;
UNIT uplevelapi (Cells, PCells, SumCells, Scale);
TYPE Cells = SUPER ARRAY [1..*] OF INTEGER; PCells = ^Cells;
FUNCTION SumCells(c: PCells; n: INTEGER): INTEGER;
PROCEDURE Scale(c: PCells; n, f: INTEGER);
END;
