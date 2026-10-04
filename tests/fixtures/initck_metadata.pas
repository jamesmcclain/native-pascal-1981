PROGRAM InitMetadata;
VAR
  ck_default: INTEGER;
  {$INITCK+}
  ck_on: INTEGER;
  {$INITCK-}
  ck_off: INTEGER;
  {$DEBUG+}
  ck_debug: INTEGER;
  {$INITCK-}
  ck_override: INTEGER;
  {$PUSH}
  {$INITCK+}
  ck_pushed: INTEGER;
  {$POP}
  ck_restored: INTEGER;
  {$IF INITCK $THEN}
  ck_wrong_off_branch: INTEGER;
  {$ELSE}
  ck_if_off: INTEGER;
  {$END}
  {$INITCK+}
  {$IF INITCK $THEN}
  ck_if_on: INTEGER;
  {$ELSE}
  ck_wrong_on_branch: INTEGER;
  {$END}
  {$DEBUG-}
  ck_debug_off: INTEGER;
  {$INITCK+}
  ck_after_debug_off: INTEGER;
  ck_mid {$INITCK-}: INTEGER;
  ck_after_mid: INTEGER;
  {$INITCK+}
  ck_last: INTEGER;
{$INITCK-}
BEGIN END.
