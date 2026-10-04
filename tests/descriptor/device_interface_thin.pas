{ DIALECT: extended }
DEVICE INTERFACE;
UNIT descriptordevice (PDeviceCells, touch);
TYPE DeviceCells = SUPER ARRAY [2..*] OF INTEGER32;
     PDeviceCells = ^DeviceCells;
PROCEDURE touch(p: PDeviceCells);
END;
PROGRAM DescriptorDeviceInterface;
USES descriptordevice;
VAR raw: PDeviceCells;
BEGIN raw := NIL; LAUNCH(touch, 1, 1, raw) END.
