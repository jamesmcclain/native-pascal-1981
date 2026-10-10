/* Located host diagnostic for a checked fixed/SUPER ARRAY subscript. */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

#include "pascalrt.h"

void pas_array_index_error(int64_t value, int32_t value_unsigned, int64_t lo, int64_t hi, int32_t line, int32_t column)
{
    fflush(stdout);
    if (value_unsigned)
        fprintf(stderr, "runtime error: array index %" PRIu64 " is outside bounds %" PRId64 "..%" PRId64 " at line %" PRId32 " column %" PRId32 "\n", (uint64_t) value, lo, hi,
                line, column);
    else
        fprintf(stderr, "runtime error: array index %" PRId64 " is outside bounds %" PRId64 "..%" PRId64 " at line %" PRId32 " column %" PRId32 "\n", value, lo, hi, line, column);
    fflush(stderr);
    abort();
}
