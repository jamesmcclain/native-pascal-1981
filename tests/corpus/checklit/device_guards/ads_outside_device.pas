{ DIALECT: extended }
{ ADS pointers belong to DEVICE compilands; a host module declaring one is
  rejected. }
{ CHECK-FAIL: codegen: ADS pointers require a DEVICE compiland }
MODULE AdsHost;
PROCEDURE go(p: ADS(GLOBAL) OF INTEGER32);
BEGIN END;
.
