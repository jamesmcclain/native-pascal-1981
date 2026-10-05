INTERFACE;
UNIT rtcall (Emit);
{ Emit is the ONLY caller of a runtime routine in this program: its WRITELN
  lowers to pas_* I/O helpers. The host PROGRAM below calls nothing from the
  runtime directly. This pins ExecClang's link order -- objects before the
  libpascalrt.a archive -- because a runtime member referenced only from this
  secondary compiland is dropped if the archive is scanned first. }
PROCEDURE Emit;
END;
