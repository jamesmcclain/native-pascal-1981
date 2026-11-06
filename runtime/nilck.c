/* Null-only host pointer checks, independent of lifetime/provenance. */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

#include "pascalrt.h"

static void nilck_fail(const char *operation, int32_t line, int32_t column)
{
    fflush(stdout);
    fprintf(stderr, "runtime error: NILCK NIL pointer %s at line %" PRId32 " column %" PRId32 "%s\n", operation, line, column, pas_diag_where());
    fflush(stderr);
    abort();
}

void pas_nilck_error(int32_t line, int32_t column)
{
    nilck_fail("dereference", line, column);
}

void pas_nilck_dispose_error(int32_t line, int32_t column)
{
    nilck_fail("passed to DISPOSE", line, column);
}
