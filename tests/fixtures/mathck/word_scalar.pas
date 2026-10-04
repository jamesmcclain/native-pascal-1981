PROGRAM WordScalar;
VAR hi, lo, same, maximum: WORD;
    neg, two: INTEGER;
BEGIN
  hi := 40000; lo := 7; same := hi; maximum := 65535;
  WRITELN(hi DIV lo); WRITELN(hi MOD lo);
  WRITELN(lo DIV hi); WRITELN(lo MOD hi);
  WRITELN((hi > lo) AND (hi >= lo) AND NOT (hi < lo) AND NOT (hi <= lo));
  WRITELN((lo < hi) AND (lo <= hi) AND NOT (lo > hi) AND NOT (lo >= hi));
  WRITELN((hi = same) AND NOT (hi <> same) AND (hi <= same) AND (hi >= same));
  WRITELN((lo <> hi) AND NOT (lo = hi) AND (maximum > hi));
  WRITELN(hi DIV 2); WRITELN(hi > 1); WRITELN(1 < hi);
  WRITELN(WRD(-2) DIV 3);
  hi := 14;
  WRITELN(hi DIV lo); WRITELN(hi MOD lo); WRITELN(hi > lo);
  CASE maximum OF
    40000: WRITELN('wrong');
    65535: WRITELN('case max');
  END;
  CASE same OF
    40000: WRITELN('case high');
    65535: WRITELN('wrong');
  END;
  neg := -7; two := 2;
  WRITELN(neg DIV two); WRITELN(neg MOD two); WRITELN(neg < two);
  { Membership accepts INTEGER, not WORD. The same high-bit pattern must
    remain outside the set even when sign-extended by the membership path. }
  neg := -25536;
  WRITELN(neg IN [0, 7, 255]);
  neg := 7; WRITELN(neg IN [0, 7, 255]);
  (* WORD converts to REAL unsigned: FLOAT and a mixed REAL operand. *)
  WRITELN(FLOAT(maximum):8:1); WRITELN(FLOAT(same) + 0.5:8:1);
  WRITELN(1.0 + maximum:8:1); WRITELN(maximum * 1.0:8:1);
END.
