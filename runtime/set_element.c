/*
 * Runtime diagnostic for a set constructor element outside 0..255. A set is
 * a 256-bit bitvector, so the compiler checks each element, and each
 * endpoint of a nonempty range, before it sets a bit, and calls this on
 * failure. It reports on stderr and abort()s, the same exit as the other
 * range diagnostics (subrange.c, array_index.c).
 */

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

#include "pascalrt.h"

void pas_set_element_error(int64_t value)
{
    fflush(stdout);
    fprintf(stderr, "runtime error: set element %" PRId64 " is outside 0..255\n", value);
    fflush(stderr);
    abort();
}
