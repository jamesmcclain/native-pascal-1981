{ Every device index builtin is an INTEGER32 expression. Mixed spelling pins
  the same case-insensitive lookup rule used by code generation. }
{ CHECK: define void @read_indices }
{ CHECK: @__pas_tid_x }
{ CHECK: @__pas_tid_y }
{ CHECK: @__pas_tid_z }
{ CHECK: @__pas_ctaid_x }
{ CHECK: @__pas_ctaid_y }
{ CHECK: @__pas_ctaid_z }
{ CHECK: @__pas_ntid_x }
{ CHECK: @__pas_ntid_y }
{ CHECK: @__pas_ntid_z }
{ CHECK: @__pas_nctaid_x }
{ CHECK: @__pas_nctaid_y }
{ CHECK: @__pas_nctaid_z }
DEVICE INTERFACE;
UNIT DINDEX (read_indices);
PROCEDURE read_indices;
END;
DEVICE IMPLEMENTATION OF DINDEX;
PROCEDURE read_indices;
VAR
  total: INTEGER32;
BEGIN
  total := threadidx_x + ThreadIdx_Y + THREADIDX_Z +
           blockidx_x + BlockIdx_Y + BLOCKIDX_Z +
           blockdim_x + BlockDim_Y + BLOCKDIM_Z +
           griddim_x + GridDim_Y + GRIDDIM_Z
END;
.
