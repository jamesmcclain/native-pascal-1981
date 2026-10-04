(*$INCLUDE:'runtime_secondary_link.inc'*)
PROGRAM RuntimeSecondaryLink(output);
{ The host body calls no runtime routine itself; only rtcall.Emit does. If
  ExecClang ever regresses to naming libpascalrt.a before the object files,
  this fails to link with "undefined reference to pas_...". }
USES rtcall;
BEGIN
  Emit;
END.
