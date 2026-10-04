/* Real C callees for c_mixed_aggregate.pas. */
#include <stdint.h>

typedef struct { int32_t a, b; } Pair;
typedef struct { int32_t v[8]; } Big;
typedef struct { int32_t v[3]; } Trio;

int mixed_call(int n, Pair p, Big big, Pair q, int k) {
  int s = n + p.a + p.b + q.a + q.b + k;
  for (int i = 0; i < 8; ++i) s += big.v[i];
  return s;
}

int trio_sum(Trio t) { return t.v[0] + t.v[1] + t.v[2]; }
