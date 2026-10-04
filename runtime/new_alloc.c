/* Ordinary NEW: a failed allocation is a runtime error (IBM error 2001,
 * "No Room In Heap"), raised before anything is registered or published,
 * like the SUPER ARRAY form (super_descriptor.c). */
#include <stdio.h>
#include <stdlib.h>
#include "pascalrt.h"

void pas_new_error(void)
{
    fflush(stdout);
    fputs("runtime error: NEW allocation failed\n", stderr);
    fflush(stderr);
    abort();
}
