#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "pascalrt.h"

/*
 * ENCODE(dest: LSTRING; value): format `value` into the LSTRING `dest`.
 *
 *   dest_chars  - pointer to the first character cell (byte [1] of the
 *                 LSTRING aggregate).
 *   dest_cap    - declared capacity of the LSTRING (max characters), NOT its
 *                 current length.
 *   dest_raw    - pointer to the aggregate base (byte [0]); used to write the
 *                 LSTRING length-prefix byte once formatting succeeds.
 *   value       - the integer to encode.
 *   width       - optional minimum field width (`value:width`); 0 = none.
 *   precision   - reserved for REAL formatting; ignored on the integer path.
 *
 * Returns 1 on success, 0 if the formatted text would not fit in dest_cap
 * (in which case the destination is left untouched).
 */
int32_t encode_value(char *dest_chars, int32_t dest_cap, char *dest_raw, int32_t value, int32_t width, int32_t precision, int32_t reserved)
{
    (void) precision;
    (void) reserved;
    if (!dest_chars || dest_cap <= 0)
        return 0;

    char tmp[64];
    int n;
    if (width > 0) {
        if (width > (int) sizeof(tmp) - 1)
            width = (int) sizeof(tmp) - 1;
        n = snprintf(tmp, sizeof(tmp), "%*d", width, value);
    } else {
        n = snprintf(tmp, sizeof(tmp), "%d", value);
    }
    if (n < 0)
        return 0;
    if (n > dest_cap)
        return 0;               /* would overflow the LSTRING */

    memcpy(dest_chars, tmp, (size_t) n);
    if (dest_raw)
        dest_raw[0] = (char) n; /* set the LSTRING length prefix */
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
