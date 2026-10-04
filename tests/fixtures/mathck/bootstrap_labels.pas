{ Numeric labels above 32767 for tests/mathck_bootstrap_audit.sh. Their
  parser keys wrap to INTEGER on purpose (32768 -> -32768, 40000 ->
  -25536, 65535 -> -1) and stay distinct, so every GOTO reaches its own
  label under either setting. }
PROGRAM LabelKeys(OUTPUT);
LABEL 32767, 32768, 40000, 65535;
BEGIN
  GOTO 32767;
32767: WRITELN('32767'); GOTO 32768;
32768: WRITELN('32768'); GOTO 40000;
40000: WRITELN('40000'); GOTO 65535;
65535: WRITELN('65535')
END.
