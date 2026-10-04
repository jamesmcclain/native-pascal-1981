PROGRAM MathckMetadataTransitions(output);
{ Conditional compilation and includes for per-operation MATHCK snapshots.
  Include paths are relative to the repository root, as used by the test. }
PROCEDURE Run;
VAR
  a, x: INTEGER;
BEGIN
  a := 1;
  {$MATHCK-}
  {$IF MATHCK $THEN}
    x := a + a;
  {$ELSE}
    x := a - a;
  {$END}
  {$MATHCK+}
  {$IF MATHCK $THEN}
    x := a * a;
  {$ELSE}
    {$MATHCK-} x := a DIV a;
  {$END}
  { Neither nested skipped directives nor a skipped include may take effect. }
  {$IF 0 $THEN}
    {$MATHCK-,DEBUG-,PUSH}
    {$IF 1 $THEN} x := a MOD a; {$END}
    {$INCLUDE:'tests/contract/fixtures/mathck/metadata_missing.inc'}
  {$END}
  x := a MOD a;
  { Active includes share the lexical state and PUSH stack with the caller. }
  {$MATHCK-}
  {$INCLUDE:'tests/contract/fixtures/mathck/metadata_enable.inc'}
  x := -a;
  {$INCLUDE:'tests/contract/fixtures/mathck/metadata_restore.inc'}
  x := SQR(a);
  { An include inside an expression: operations after it see its state. }
  {$MATHCK+}
  x := a + {$INCLUDE:'tests/contract/fixtures/mathck/metadata_disable.inc'} a - a
END;
BEGIN
  Run
END.
