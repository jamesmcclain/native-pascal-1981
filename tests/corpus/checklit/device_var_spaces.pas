{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ CHECK: .visible .shared .align 4 .b8 block_scratch[256]; }
{ CHECK: .visible .global .align 4 .b8 output_data[256]; }
{ CHECK: .visible .shared .align 4 .b8 touch.local_scratch[128]; }
{ Type-suffix spelling for a plain scalar store/load (u32 vs. b32) is an
  LLVM NVPTX AsmPrinter detail that changed across LLVM releases; only the
  memory space prefix reflects this test's SPACE(SHARED)/SPACE(GLOBAL)
  placement, so accept either spelling. }
{ CHECK-ANY: st.shared.u32 || st.shared.b32 }
{ CHECK-ANY: st.global.u32 || st.global.b32 }
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
