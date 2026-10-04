{ String initialization tracking is not implemented: an enabled INITCK read
  of a string is rejected rather than reading an uninitialized length byte
  or character. }
{ CHECK-FAIL: INITCK unsupported boundary: call consumer }
PROGRAM checked; VAR s: LSTRING(4);
BEGIN {$INITCK+} WRITELN(SCANEQ(4, 'b', s, 1)) END.
