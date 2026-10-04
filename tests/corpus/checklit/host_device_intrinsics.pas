{ DIALECT: extended }
{ Host orchestration accepts both supported launch geometries. }
{ CHECK: @pas_dev_alloc }
{ CHECK: @pas_dev_copy_to }
{ CHECK: @pas_dev_copy_from }
{ CHECK: @pas_dev_free }
{ CHECK: @pas_dev_launch }
PROGRAM HOSTDEVICEINTRINSICS;
TYPE
  PINT = ^INTEGER32;
VAR
  device_data: PINT;
  host_data: INTEGER32;
PROCEDURE kernel(data: PINT; item: INTEGER32);
BEGIN
  data^ := item
END;
BEGIN
  device_data := DEVALLOC(SIZEOF(host_data));
  DEVCOPYTO(device_data, ADR host_data, SIZEOF(host_data));
  LAUNCH(kernel, 1, 1, device_data, host_data);
  LAUNCH(kernel, 1, 1, 1, 1, 1, 1, device_data, host_data);
  DEVCOPYFROM(ADR host_data, device_data, SIZEOF(host_data));
  DEVFREE(device_data)
END.
