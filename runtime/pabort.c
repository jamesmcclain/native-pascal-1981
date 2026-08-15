/*
 * Runtime support for ABORT.
 *
 * Manual: ABORT(CONST STRING, WORD, WORD) "stops program execution in the same
 * way as an internal runtime error. The STRING (or LSTRING) is an error
 * message; the first WORD is an error code ...; and the second WORD ... will
 * appear in a field called STATUS."
 *
 * We surface the message, error code, and status on stderr and then abort(),
 * matching the "same way as an internal runtime error" wording (the internal
 * runtime-error path also calls abort()). The message is passed as an explicit
 * (pointer, length) pair because Pascal STRING/LSTRING values are not
 * null-terminated.
 */

#include <stdio.h>
#include <stdlib.h>

#include "pascalrt.h"

void pabort(const char *msg, int msglen, unsigned short code, unsigned short status)
{
    fprintf(stderr, "ABORT: %.*s (error code %u, status %u)\n", msglen, msg, (unsigned) code, (unsigned) status);
    fflush(stdout);
    fflush(stderr);
    abort();
}
