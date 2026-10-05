/* Real C callees for c_aggregate_return.pas, compiled by clang so the
   Pascal side is checked against a genuine SysV return lowering of the same
   struct shapes rather than against itself: Big is MEMORY class (>16 bytes,
   returned through a hidden sret pointer), the rest are COERCED class
   (returned in one or two registers). */
#include <stdint.h>

typedef struct { int32_t a, b, c, d, e; } Big;          /* 20 bytes: MEMORY */
typedef struct { int32_t a, b; } Pair;                  /* one INTEGER eightbyte */
typedef struct { int64_t lo; int32_t hi; } Wide;        /* i64 + i32 eightbytes */
typedef struct { float x, y; } FPair;                   /* one <2 x float> eightbyte */
typedef struct { double u, v; } DPair;                  /* two SSE eightbytes */
typedef struct { int32_t n; double d; } Mixed;          /* INTEGER + SSE */

/* Zero real parameters: the sret pointer is the ONLY argument. */
Big big_const(void) {
  Big r = {1, 2, 3, 4, 5};
  return r;
}

Big big_scale(Big b, int32_t k) {
  Big r = {b.a * k, b.b * k, b.c * k, b.d * k, b.e * k};
  return r;
}

Pair pair_make(int32_t a, int32_t b) {
  Pair r = {a, b};
  return r;
}

Wide wide_make(int32_t hi) {
  Wide r = {1000000, hi};
  return r;
}

FPair fpair_make(void) {
  FPair r = {1.5f, 2.25f};
  return r;
}

DPair dpair_make(void) {
  DPair r = {10.5, 32.25};
  return r;
}

Mixed mixed_make(int32_t n) {
  Mixed r = {n, 0.5};
  return r;
}
