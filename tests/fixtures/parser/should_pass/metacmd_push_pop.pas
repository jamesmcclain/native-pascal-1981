(* $PUSH saves meta_flags; $POP restores them.
   After push/change/pop, original flags are back. *)
{$PUSH}
{$RANGECK-}
{$INDEXCK-}
{$POP}
PROGRAM PushPop;
VAR x: INTEGER;
BEGIN
  x := 1
END.
