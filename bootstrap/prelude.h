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

/* Integer arithmetic. Pascal integer operations wrap at the operation's
 * width (pasboot ignores MATHCK, as the native MATHCK- policy does). C signed
 * overflow, INT_MIN / -1 and INT_MIN % -1 are undefined behaviour, so every
 * operation goes through unsigned arithmetic of at least the operand width
 * (narrow operands would otherwise promote to int, and 65535 * 65535
 * overflows int) and converts back; the result does not depend on -fwrapv.
 * A zero divisor is a run-time error, as it is in compiled Pascal under
 * either MATHCK setting, never a SIGFPE. */
static inline void pas_div_zero(int is_mod, int64_t left, const char *file, int line)
{
    fflush(stdout);
    fprintf(stderr, "runtime error: division by zero in %s at %s line %d (left=%lld, right=0)\n", is_mod ? "MOD" : "DIV", file, line, (long long) left);
    fflush(stderr);
    abort();
}

#define PAS_INT_OPS(W, U)                                                          \
static inline int##W##_t pas_add##W(int##W##_t a, int##W##_t b)                    \
{                                                                                  \
    return (int##W##_t) (U) ((U) a + (U) b);                                       \
}                                                                                  \
static inline int##W##_t pas_sub##W(int##W##_t a, int##W##_t b)                    \
{                                                                                  \
    return (int##W##_t) (U) ((U) a - (U) b);                                       \
}                                                                                  \
static inline int##W##_t pas_mul##W(int##W##_t a, int##W##_t b)                    \
{                                                                                  \
    return (int##W##_t) (U) ((U) a * (U) b);                                       \
}                                                                                  \
static inline int##W##_t pas_neg##W(int##W##_t a)                                  \
{                                                                                  \
    return (int##W##_t) (U) ((U) 0 - (U) a);                                       \
}                                                                                  \
static inline int##W##_t pas_div##W(int##W##_t a, int##W##_t b, const char *f, int l) \
{                                                                                  \
    if (b == 0)                                                                    \
        pas_div_zero(0, a, f, l);                                                  \
    if (b == -1)                                                                   \
        return pas_neg##W(a);                                                      \
    return (int##W##_t) (a / b);                                                   \
}                                                                                  \
static inline int##W##_t pas_mod##W(int##W##_t a, int##W##_t b, const char *f, int l) \
{                                                                                  \
    if (b == 0)                                                                    \
        pas_div_zero(1, a, f, l);                                                  \
    if (b == -1)                                                                   \
        return 0;                                                                  \
    return (int##W##_t) (a % b);                                                   \
}

PAS_INT_OPS(8, uint32_t)
PAS_INT_OPS(16, uint32_t)
PAS_INT_OPS(32, uint32_t)
PAS_INT_OPS(64, uint64_t)
#undef PAS_INT_OPS

/* TRUNC: the conversion of a NaN or of a value outside INTEGER64 to an
 * integer is undefined in C, so it is a run-time error here; an in-range
 * value keeps its low 16 bits, as the native TRUNC narrowing does. */
static inline int16_t pas_trunc16(double v, const char *file, int line)
{
    if (!(v > -9223372036854775808.0 && v < 9223372036854775808.0)) {
        fflush(stdout);
        fprintf(stderr, "runtime error: TRUNC argument out of range at %s line %d\n", file, line);
        fflush(stderr);
        abort();
    }
    return (int16_t) (uint16_t) (uint64_t) (int64_t) v;
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
