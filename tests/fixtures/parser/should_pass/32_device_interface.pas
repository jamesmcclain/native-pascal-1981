DEVICE INTERFACE;
UNIT KERNEL (add, scale);
TYPE vec = ADS(GLOBAL) OF INTEGER;
PROCEDURE add (a, b: vec; n: INTEGER);
PROCEDURE scale (v: vec; k, n: INTEGER);
END;
