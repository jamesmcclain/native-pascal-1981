#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "pascalrt.h"

/*
 * ENCODE(VAR dest: LSTRING; X:M:N): format a WRITE-style argument into the
 * LSTRING `dest` (manual 11-14).
 *
 *   dest_chars  - pointer to the first character cell (byte [1] of the
 *                 LSTRING aggregate).
 *   dest_cap    - declared capacity of the LSTRING (max characters), NOT its
 *                 current length.
 *   dest_raw    - pointer to the aggregate base (byte [0]); receives the
 *                 LSTRING length-prefix byte once formatting succeeds.
 *   fmt, ...    - the printf format and arguments the compiler builds for
 *                 WRITE(X:M:N) of the same value (cg_expr_support.pas's
 *                 EmitScalarWriteArg), so ENCODE and WRITE agree exactly.
 *
 * Returns 1 on success, 0 if the formatted text would not fit in dest_cap
 * (in which case the destination is left untouched). The length byte holds
 * at most 255 characters, whatever the declared capacity.
 */
int32_t pas_encode_fmt(char *dest_chars, int32_t dest_cap, char *dest_raw, const char *fmt, ...)
{
    if (!dest_chars || !dest_raw || !fmt || dest_cap <= 0)
        return 0;
    if (dest_cap > 255)
        dest_cap = 255;

    char tmp[512];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(tmp, sizeof(tmp), fmt, ap);
    va_end(ap);
    if (n < 0 || n >= (int) sizeof(tmp))
        return 0;
    if (n > dest_cap)
        return 0;               /* would overflow the LSTRING */

    memcpy(dest_chars, tmp, (size_t) n);
    dest_raw[0] = (char) n;     /* set the LSTRING length prefix */
    return 1;
}

/*
 * DECODE(src: STRING/LSTRING; VAR dest): parse an integer out of `src` and
 * store it into `dest`.
 *
 *   src_chars  - pointer to the first source character.
 *   src_len    - number of source characters.
 *   dest_raw   - address of the destination variable.
 *   dest_size  - destination width in bytes (CHAR=1, WORD=2, INTEGER=4).
 *
 * Returns 1 if the whole source parsed as a single integer (optionally with
 * trailing blanks), 0 otherwise. The previous version discarded the parsed
 * value entirely, leaving `dest` unchanged.
 */
int32_t decode_value(char *src_chars, int32_t src_len, char *dest_raw, int32_t dest_size, int32_t reserved3, int32_t reserved4, int32_t reserved5)
{
    (void) reserved3;
    (void) reserved4;
    (void) reserved5;
    if (!src_chars || !dest_raw)
        return 0;

    char buf[512];
    if (src_len < 0)
        src_len = 0;
    if (src_len > 511)
        src_len = 511;
    memcpy(buf, src_chars, (size_t) src_len);
    buf[src_len] = '\0';

    char *end = NULL;
    long parsed = strtol(buf, &end, 10);
    if (end == buf)
        return 0;               /* no digits at all */
    while (*end == ' ' || *end == '\t')
        ++end;
    if (*end != '\0')
        return 0;               /* trailing junk */

    switch (dest_size) {
    case 1:
        *(int8_t *) dest_raw = (int8_t) parsed;
        break;
    case 2:
        *(int16_t *) dest_raw = (int16_t) parsed;
        break;
    default:
        *(int32_t *) dest_raw = (int32_t) parsed;
        break;
    }
    return 1;
}
