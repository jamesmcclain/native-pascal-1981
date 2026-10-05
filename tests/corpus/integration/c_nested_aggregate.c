/* Real C callees for c_nested_aggregate.pas. */
#include <stdint.h>

typedef struct { int32_t a, b; } Inner;
typedef struct { Inner inner; int32_t c; } Outer;
typedef struct { Inner inner; int32_t pad[3]; } BigOuter;
typedef struct { int32_t v[2]; } SmallVec;
typedef struct { int32_t v[20]; } BigVec;

int outer_sum(Outer o) { return o.inner.a + o.inner.b + o.c; }

int big_outer_sum(BigOuter o) {
  return o.inner.a + o.inner.b + o.pad[0] + o.pad[1] + o.pad[2];
}

int small_vec_sum(SmallVec v) { return v.v[0] + v.v[1]; }

int big_vec_sum(BigVec v) {
  int s = 0;
  for (int i = 0; i < 20; ++i) s += v.v[i];
  return s;
}

Outer make_outer(int a, int b, int c) {
  Outer o;
  o.inner.a = a;
  o.inner.b = b;
  o.c = c;
  return o;
}
