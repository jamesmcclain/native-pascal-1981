{ DIALECT: extended }
PROGRAM LAUNCHINVALIDKERNEL;
VAR not_kernel: INTEGER;
BEGIN
  LAUNCH(1, 1, 1);
  LAUNCH(missing_kernel, 1, 1);
  LAUNCH(not_kernel, 1, 1)
END.
