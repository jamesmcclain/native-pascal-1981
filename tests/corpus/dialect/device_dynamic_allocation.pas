{ DIALECT: extended }
DEVICE MODULE DeviceDynamicAllocation;
TYPE PINT = ^INTEGER32;
VAR p: PINT;
PROCEDURE go;
BEGIN
  NEW(p);
  DISPOSE(p)
END;
.
