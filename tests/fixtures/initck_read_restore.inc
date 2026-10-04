{ An inner save/restore stays on; POP the save made in the other include. }
{$PUSH,INITCK-}
WRITELN(rs_include_off);
{$POP}
WRITELN(rs_include_restored);
{$POP}
