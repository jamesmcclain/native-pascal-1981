{ DIALECT: vintage extended }
{ An enabled out-of-domain CHR in a subrange or array index bound is a
  located compile-time error, as in a CONST value: it is never folded into
  a bound. }
PROGRAM chr_subrange_bound_domain(OUTPUT);
TYPE Tail = CHR(250)..CHR(300);
VAR a: ARRAY [CHR(-1)..CHR(255)] OF INTEGER;
BEGIN END.
