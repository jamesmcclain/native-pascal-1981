#include <ctype.h>
#include <errno.h>
#include <float.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
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
 * DECODE(CONST src: STRING; VAR X:M:N): convert the text of a STRING or
 * LSTRING to a value as READ would (manual 11-15), one entry point per
 * value family. Each returns 1 and stores through `out` when the whole
 * text, less leading and trailing blanks and tabs, is one valid
 * representation of a value in range; otherwise it returns 0 and stores
 * nothing. Nothing here aborts: a bad string is DECODE's FALSE result,
 * not a runtime error, whatever RANGECK says.
 *
 *   src     - pointer to the first source character (not NUL-terminated).
 *   len     - number of source characters.
 */

/* Drop the blanks and tabs the manual ignores at either end. */
static void decode_trim(const char **src, int32_t *len)
{
    const char *s = *src;
    int32_t n = *len < 0 ? 0 : *len;
    while (n > 0 && (s[0] == ' ' || s[0] == '\t')) {
        s++;
        n--;
    }
    while (n > 0 && (s[n - 1] == ' ' || s[n - 1] == '\t'))
        n--;
    *src = s;
    *len = n;
}

/* The decimal integer token READ accepts: an optional sign and digits,
 * nothing else. The magnitude is accumulated unsigned so that every 64-bit
 * value, WORD64's included, is exact; wider text is an overflow. */
static int decode_decimal(const char *s, int32_t n, int *negative, uint64_t *magnitude)
{
    int32_t i = 0;
    uint64_t v = 0;
    *negative = 0;
    if (i < n && (s[i] == '+' || s[i] == '-')) {
        *negative = s[i] == '-';
        i++;
    }
    if (i >= n)
        return 0;               /* no digits at all */
    for (; i < n; i++) {
        if (s[i] < '0' || s[i] > '9')
            return 0;           /* not part of a decimal representation */
        unsigned d = (unsigned) (s[i] - '0');
        if (v > (UINT64_MAX - d) / 10)
            return 0;           /* overflow */
        v = v * 10 + d;
    }
    *magnitude = v;
    return 1;
}

/*
 * The integer family. `bits` and `is_unsigned` name the destination type
 * (INTEGER 16, WORD 16 unsigned, INTEGER8/32/64, WORD8/32/64); with
 * `has_bounds`, lo..hi is the declared subrange instead, which is always
 * narrower than 64 signed bits. A value outside the type or the subrange
 * is a 0 result, as the manual requires regardless of RANGECK.
 */
int32_t pas_decode_integer(const char *src, int32_t len, int32_t bits, int32_t is_unsigned, int32_t has_bounds, int64_t lo, int64_t hi, int64_t *out)
{
    int negative;
    uint64_t mag;
    if (!src || !out)
        return 0;
    decode_trim(&src, &len);
    if (!decode_decimal(src, len, &negative, &mag))
        return 0;
    if (negative && mag == 0)
        negative = 0;
    if (is_unsigned && bits == 64 && !has_bounds) {
        if (negative)
            return 0;
        *out = (int64_t) mag;
        return 1;
    }
    /* Every other case fits a signed 64-bit comparison. */
    int64_t value;
    if (negative) {
        if (mag > (uint64_t) INT64_MAX + 1)
            return 0;
        value = (mag == (uint64_t) INT64_MAX + 1) ? INT64_MIN : -(int64_t) mag;
    } else {
        if (mag > (uint64_t) INT64_MAX)
            return 0;
        value = (int64_t) mag;
    }
    if (!has_bounds) {
        if (is_unsigned) {
            lo = 0;
            hi = bits >= 64 ? INT64_MAX : (int64_t) ((UINT64_C(1) << bits) - 1);
        } else if (bits >= 64) {
            lo = INT64_MIN;
            hi = INT64_MAX;
        } else {
            hi = (int64_t) ((UINT64_C(1) << (bits - 1)) - 1);
            lo = -hi - 1;
        }
    }
    if (value < lo || value > hi)
        return 0;
    *out = value;
    return 1;
}

/*
 * Enumerations and BOOLEAN: an ordinal in lo..hi, or, when `names` is
 * given (the extended dialect's symbolic enumeration I/O, and BOOLEAN's
 * TRUE/FALSE in both dialects), a member identifier matched without regard
 * to letter case. `names` is indexed by ordinal over the whole host type,
 * so a subrange starting above zero still finds its members.
 */
int32_t pas_decode_enum(const char *src, int32_t len, const char **names, int32_t lo, int32_t hi, int32_t *out)
{
    if (!src || !out)
        return 0;
    decode_trim(&src, &len);
    if (len <= 0)
        return 0;
    if (isdigit((unsigned char) src[0]) || src[0] == '+' || src[0] == '-') {
        int64_t v;
        if (!pas_decode_integer(src, len, 32, 0, 1, lo, hi, &v))
            return 0;
        *out = (int32_t) v;
        return 1;
    }
    if (!names)
        return 0;               /* vintage enumerations read ordinals only */
    for (int32_t i = lo; i <= hi; i++) {
        const char *name = names[i];
        if (!name)
            continue;
        size_t n = strlen(name);
        if (n == (size_t) len && strncasecmp(name, src, n) == 0) {
            *out = i;
            return 1;
        }
    }
    return 0;
}

/* CHAR: exactly one character once the surrounding blanks are dropped,
 * within the declared subrange lo..hi (0..255 for CHAR itself). */
int32_t pas_decode_char(const char *src, int32_t len, int32_t lo, int32_t hi, uint8_t *out)
{
    if (!src || !out)
        return 0;
    decode_trim(&src, &len);
    if (len != 1)
        return 0;
    int ch = (unsigned char) src[0];
    if (ch < lo || ch > hi)
        return 0;
    *out = (uint8_t) ch;
    return 1;
}

/* REAL: the C conversion READ's scanf("%lf") uses, applied to the whole
 * trimmed text, so a leading or trailing decimal point is accepted as the
 * manual says (12-19). */
int32_t pas_decode_real(const char *src, int32_t len, double *out)
{
    char buf[512];
    char *end = NULL;
    if (!src || !out)
        return 0;
    decode_trim(&src, &len);
    if (len <= 0 || len >= (int32_t) sizeof(buf))
        return 0;
    memcpy(buf, src, (size_t) len);
    buf[len] = '\0';
    if (isspace((unsigned char) buf[0]))
        return 0;               /* strtod would skip it; READ's token cannot start with it */
    errno = 0;
    double v = strtod(buf, &end);
    if (end == buf || *end != '\0')
        return 0;
    if (errno == ERANGE && (v > DBL_MAX || v < -DBL_MAX))
        return 0;               /* overflow; an underflow is a tiny REAL */
    *out = v;
    return 1;
}
