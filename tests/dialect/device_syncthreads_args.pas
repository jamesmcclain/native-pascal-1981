{ DIALECT: extended }
DEVICE MODULE DeviceSyncthreadsArgs;
PROCEDURE go;
BEGIN
  SYNCTHREADS(1)
END;
.
