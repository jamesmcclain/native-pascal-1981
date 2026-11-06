{ A codegen compile-time diagnostic (an INITCK unsupported boundary) inside
  an included routine names the included file. }
PROGRAM codegen_boundary(OUTPUT);
(*$INCLUDE:'codegen_boundary.inc'*)
BEGIN
  Probe
END.
