/* Prologue of every C translation unit pasboot writes. It carries the few
 * run-time helpers the bootstrap subset needs and depends on nothing but
 * libc; the Pascal runtime library (runtime/) is linked only for the [C]
 * routines the compiled sources themselves declare. */
#ifndef PASBOOT_PRELUDE_H
#define PASBOOT_PRELUDE_H

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* libpascalrt: records argv for pas_arg_count/pas_arg_value. */
void pas_args_init(int argc, char **argv);

/* Compare two length-prefixed strings (an LSTRING's bytes, length at [0]):
 * memcmp over the shorter length, then the shorter string is smaller. */
static inline int pas_scmp(const uint8_t *a, const uint8_t *b)
{
    int la = a[0], lb = b[0];
    int c = memcmp(a + 1, b + 1, (size_t)(la < lb ? la : lb));
    if (c != 0)
        return c < 0 ? -1 : 1;
    return la < lb ? -1 : la > lb ? 1 : 0;
}

/* CONCAT(d, s): append s to the LSTRING d of capacity cap. Overflowing the
 * capacity is a run-time error, as it is in compiled Pascal. */
static inline void pas_concat(uint8_t *d, int cap, const uint8_t *s)
{
    int ld = d[0], ls = s[0];
    if (ld + ls > cap) {
        fputs("runtime error: CONCAT overflows its destination string\n", stderr);
        abort();
    }
    memmove(d + 1 + ld, s + 1, (size_t)ls);
    d[0] = (uint8_t)(ld + ls);
}

static inline void pas_wr_str(const uint8_t *s)
{
    fwrite(s + 1, 1, s[0], stdout);
}

static inline void pas_wr_ch(uint8_t c)
{
    putchar(c);
}

#endif
