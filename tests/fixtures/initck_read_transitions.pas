{ Compile only: actual read snapshots, not runtime initialization checks.
  Include paths are relative to the repository root, as used by the test. }
{$INITCK-}
PROGRAM ReadTransitions;
VAR
  rs_debug_on, rs_override_off, rs_debug_recoupled,
  rs_debug_off, rs_override_on,
  rs_push_outer, rs_push_inner, rs_pop_inner, rs_pop_outer,
  rs_if_off, rs_if_on, rs_after_skipped,
  rs_include_on, rs_include_after, rs_include_off,
  rs_include_restored, rs_include_pop,
  rs_emitted, rs_next: INTEGER;
BEGIN
  {$DEBUG+}WRITELN(rs_debug_on);
  {$INITCK-}WRITELN(rs_override_off);
  {$DEBUG+}WRITELN(rs_debug_recoupled);
  {$DEBUG-}WRITELN(rs_debug_off);
  {$INITCK+}WRITELN(rs_override_on);

  { Nested PUSH/POP restores the overridden INITCK state, not just DEBUG. }
  {$DEBUG+,INITCK-,PUSH}
  {$INITCK+}WRITELN(rs_push_outer);
  {$PUSH,DEBUG-}WRITELN(rs_push_inner);
  {$POP}WRITELN(rs_pop_inner);
  {$POP}WRITELN(rs_pop_outer);

  {$IF INITCK $THEN}
    {$DEBUG+}WRITELN(rs_if_on);
  {$ELSE}
    WRITELN(rs_if_off);
  {$END}
  {$INITCK+}
  {$IF INITCK $THEN}
    WRITELN(rs_if_on);
  {$ELSE}
    {$DEBUG-}WRITELN(rs_if_off);
  {$END}
  { Neither nested skipped directives nor a skipped include may take effect. }
  {$IF 0 $THEN}
    {$INITCK-,DEBUG-,PUSH}
    {$IF 1 $THEN}WRITELN(rs_if_off);{$END}
    {$INCLUDE:'tests/fixtures/initck_read_missing.inc'}
  {$END}
  WRITELN(rs_after_skipped);

  { Active includes share the lexical state and PUSH stack with the caller. }
  {$INITCK-}
  {$INCLUDE:'tests/fixtures/initck_read_enable.inc'}
  WRITELN(rs_include_after);
  {$INCLUDE:'tests/fixtures/initck_read_restore.inc'}
  WRITELN(rs_include_pop);

  { DEBUG after an emitted identifier affects only subsequent consumers. }
  {$DEBUG-}WRITELN(rs_emitted {$DEBUG+} + rs_next)
END.
