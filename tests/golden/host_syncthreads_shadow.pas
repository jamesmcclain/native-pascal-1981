PROGRAM HostSyncthreadsShadow(output);
{ A user-declared SYNCTHREADS must shadow the DEVICE synchronization
  builtin and run as an ordinary procedure -- regression coverage for the
  builtin-dispatch-before-symbol-lookup bug the Gap 1 fix introduced (the
  intrinsic check used to run before LookupSymbol, so this call was
  rejected with "Device synchronization builtin requires DEVICE code"
  instead of reaching this body). }
PROCEDURE SYNCTHREADS;
BEGIN
  WRITELN('user procedure')
END;
BEGIN
  SYNCTHREADS
END.
