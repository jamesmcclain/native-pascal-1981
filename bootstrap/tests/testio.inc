{ Output helpers for the pasboot fixtures. The bootstrap subset's WRITE takes
  only string literals and CHARs, so numbers and LSTRINGs are written a
  character at a time. The exported VAR checks interface linkage: a fixture
  assigns it and ReportCalls reads it from this separately compiled unit. }

INTERFACE;
UNIT testio;

TYPE
  Str255 = LSTRING(255);

VAR
  call_count: INTEGER32;

PROCEDURE WriteInt(n: INTEGER64);
PROCEDURE WriteStr(s: Str255);
PROCEDURE WriteBool(b: BOOLEAN);
PROCEDURE WriteLabel(s: Str255);
PROCEDURE ReportCalls;

END;
