/* Null-only checks for ordinary host typed-pointer dereferences. */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

#include "pascalrt.h"

void pas_nilck_error(int32_t line, int32_t column)
{
    fflush(stdout);
    fprintf(stderr, "runtime error: NILCK NIL pointer dereference at line %" PRId32 " column %" PRId32 "\n", line, column);
    fflush(stderr);
    abort();
}
