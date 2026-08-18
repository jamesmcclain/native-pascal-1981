/* Real C callees for c_coerced_aggregate.pas, compiled by clang so the
   Pascal side is checked against a genuine SysV lowering of the same
   struct shapes rather than against itself. */
#include <stdint.h>

typedef struct { int32_t a, b; } Pair;
typedef struct { float x, y; } FPair;
typedef struct { double u, v; } DPair;
typedef struct { int64_t lo; int32_t hi; } Wide;
typedef struct { int32_t n; float f; double d; } Mixed;

int pair_sum(Pair p) { return p.a + p.b; }
int fpair_sum(FPair p) { return (int)(p.x + p.y); }
int dpair_sum(DPair p) { return (int)(p.u + p.v); }
int wide_sum(Wide w) { return (int)(w.lo + w.hi); }
int mixed_sum(Mixed m) { return (int)(m.n + m.f + m.d); }
