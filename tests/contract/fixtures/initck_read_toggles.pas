{ Compile only: declaration state must not determine later read state. }
{$INITCK+}
PROGRAM ReadToggles;
VAR rs_global_on: INTEGER;
{$INITCK-}
    rs_global_off: INTEGER;
PROCEDURE Probe;
{$INITCK+}
VAR rs_local_on: INTEGER;
{$INITCK-}
    rs_local_off: INTEGER;
BEGIN
  { The same storage has both enabled and disabled uses in one statement. }
  WRITELN({$INITCK+}rs_global_off + {$INITCK-}rs_global_off,
          {$INITCK-}rs_global_on + {$INITCK+}rs_global_on);
  WRITELN({$INITCK+}rs_local_off + {$INITCK-}rs_local_off,
          {$INITCK-}rs_local_on + {$INITCK+}rs_local_on);
  { A directive after an emitted identifier must not change that snapshot. }
  {$INITCK-}rs_local_off {$INITCK+}:= rs_local_on + {$INITCK-}rs_global_on;
  { Statement entry is off, but the actually consumed operands toggle. }
  IF ({$INITCK+}rs_local_off > {$INITCK-}rs_local_on) THEN
    WRITELN({$INITCK+}rs_global_off);
  { A later argument does not overwrite the call or earlier operand flags. }
  WRITELN({$INITCK-}ORD({$INITCK+}rs_local_off) + {$INITCK-}rs_local_on)
END;
BEGIN
  Probe
END.
