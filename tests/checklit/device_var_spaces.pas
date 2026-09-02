{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ CHECK: .visible .shared .align 4 .b8 block_scratch[256]; }
{ CHECK: .visible .global .align 4 .b8 output_data[256]; }
{ CHECK: .visible .shared .align 4 .b8 touch.local_scratch[128]; }
{ CHECK: st.shared.u32 }
{ CHECK: st.global.u32 }
DEVICE MODULE DVarSpaces;
VAR
  [SPACE(SHARED)] block_scratch: ARRAY [0..63] OF INTEGER32;
  [SPACE(GLOBAL)] output_data: ARRAY [0..63] OF INTEGER32;
PROCEDURE touch;
VAR
  [SPACE(SHARED)] local_scratch: ARRAY [0..31] OF INTEGER32;
BEGIN
  block_scratch[THREADIDX_X] := THREADIDX_X;
  output_data[THREADIDX_X] := block_scratch[THREADIDX_X];
  local_scratch[THREADIDX_X] := output_data[THREADIDX_X]
END;
.
