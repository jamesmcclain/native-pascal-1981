(* Tier-2 ON/OFF runtime-check metacommands are stored in meta_flags.
   All names should parse without error. *)
{$BRAVE+, $DEBUG+}
{$DEBUG-}
{$ENTRY+}
{$GOTO+}
{$INDEXCK-}
{$INITCK+}
{$LINE+}
{$MATHCK-}
{$NILCK-}
{$RANGECK-}
{$RUNTIME+}
{$STACKCK-}
{$WARN-}
{$DEBUG+}
PROGRAM Tier2Meta;
VAR x: INTEGER;
BEGIN
  x := 42
END.
