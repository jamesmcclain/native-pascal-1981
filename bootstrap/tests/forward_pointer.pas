{ A pointer type may name a type declared later in the same TYPE section:
  a list through ADR, mutually recursive records, and a record pointing at
  itself. In a routine's TYPE section the later local declaration wins
  over an outer type of the same name. The native compiler's
  tests/golden/forward_pointer_types.pas checks the same rules. }
(*$INCLUDE:'testio.inc'*)
PROGRAM fwd2(input, output);
USES testio;
TYPE
  Node = RECORD v: INTEGER END;
  PA = ^RA;
  PB = ^RB;
  RA = RECORD n: INTEGER; b: PB END;
  RB = RECORD m: INTEGER; a: PA END;
  Self = RECORD k: INTEGER; me: ^Self END;
VAR
  xa: RA; xb: RB; s: Self; g: Node;

PROCEDURE Local;
TYPE
  PNode = ^Node;
  Node = RECORD v, w: INTEGER; next: PNode END;
VAR
  q, r: Node;
BEGIN
  r.w := 9;
  q.next := ADR r;
  WriteInt(q.next^.w); WriteInt(SIZEOF(q)); WRITELN;
END;

BEGIN
  xa.n := 6; xb.m := 5; xa.b := ADR xb; xb.a := ADR xa;
  WriteInt(xa.b^.m); WriteInt(xa.b^.a^.n); WRITELN;
  s.k := 3; s.me := ADR s;
  WriteInt(s.me^.me^.k); WRITELN;
  Local;
  WriteInt(SIZEOF(g)); WRITELN;
END.
