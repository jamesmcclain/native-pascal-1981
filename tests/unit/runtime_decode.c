#include <assert.h>
#include <stdint.h>
#include <string.h>
#include "../../runtime/pascalrt.h"

/* pas_decode_*: the DECODE runtime. Each converter takes the whole text
 * (not NUL-terminated), ignores blanks and tabs at either end, answers 1
 * and stores on success, and answers 0 without storing otherwise. */
static int32_t dec_int(const char *s, int32_t bits, int32_t is_unsigned, int64_t *out)
{
    return pas_decode_integer(s, (int32_t) strlen(s), bits, is_unsigned, 0, 0, 0, out);
}

static int32_t dec_sub(const char *s, int64_t lo, int64_t hi, int64_t *out)
{
    return pas_decode_integer(s, (int32_t) strlen(s), 16, 0, 1, lo, hi, out);
}

int main(void)
{
    int64_t v = 77;
    int32_t o = 77;
    uint8_t ch = '?';
    double d = 0.5;
    static const char *colors[] = { "RED", "GREEN", "BLUE" };
    static const char *bools[] = { "FALSE", "TRUE" };

    /* INTEGER: sign, surrounding blanks and tabs, leading zeros. */
    assert(dec_int(" \t-123 \t", 16, 0, &v) == 1 && v == -123);
    assert(dec_int("+0042", 16, 0, &v) == 1 && v == 42);
    assert(dec_int("32767", 16, 0, &v) == 1 && v == 32767);
    assert(dec_int("-32768", 16, 0, &v) == 1 && v == -32768);
    v = 5;
    assert(dec_int("32768", 16, 0, &v) == 0 && v == 5);
    assert(dec_int("-32769", 16, 0, &v) == 0 && v == 5);
    assert(dec_int("", 16, 0, &v) == 0 && v == 5);
    assert(dec_int("   ", 16, 0, &v) == 0 && v == 5);
    assert(dec_int("-", 16, 0, &v) == 0 && v == 5);
    assert(dec_int("1 2", 16, 0, &v) == 0 && v == 5);
    assert(dec_int("12x", 16, 0, &v) == 0 && v == 5);
    assert(dec_int("0x10", 16, 0, &v) == 0 && v == 5);
    assert(dec_int("99999999999999999999999", 16, 0, &v) == 0 && v == 5);
    /* An embedded NUL is not a digit: the length, not a terminator, bounds the text. */
    assert(pas_decode_integer("1\0002", 3, 16, 0, 0, 0, 0, &v) == 0 && v == 5);
    assert(pas_decode_integer("123456", 3, 16, 0, 0, 0, 0, &v) == 1 && v == 123);

    /* WORD and the wide types take their bounds from the width. */
    assert(dec_int("65535", 16, 1, &v) == 1 && v == 65535);
    assert(dec_int("65536", 16, 1, &v) == 0);
    assert(dec_int("-1", 16, 1, &v) == 0);
    assert(dec_int("-0", 16, 1, &v) == 1 && v == 0);
    assert(dec_int("-128", 8, 0, &v) == 1 && v == -128);
    assert(dec_int("128", 8, 0, &v) == 0);
    assert(dec_int("255", 8, 1, &v) == 1 && v == 255);
    assert(dec_int("256", 8, 1, &v) == 0);
    assert(dec_int("2147483647", 32, 0, &v) == 1 && v == INT32_MAX);
    assert(dec_int("-2147483648", 32, 0, &v) == 1 && v == INT32_MIN);
    assert(dec_int("2147483648", 32, 0, &v) == 0);
    assert(dec_int("4294967295", 32, 1, &v) == 1 && v == 4294967295LL);
    assert(dec_int("4294967296", 32, 1, &v) == 0);
    assert(dec_int("9223372036854775807", 64, 0, &v) == 1 && v == INT64_MAX);
    assert(dec_int("-9223372036854775808", 64, 0, &v) == 1 && v == INT64_MIN);
    assert(dec_int("9223372036854775808", 64, 0, &v) == 0);
    assert(dec_int("-9223372036854775809", 64, 0, &v) == 0);
    assert(dec_int("18446744073709551615", 64, 1, &v) == 1 && (uint64_t) v == UINT64_MAX);
    assert(dec_int("18446744073709551616", 64, 1, &v) == 0);
    assert(dec_int("-1", 64, 1, &v) == 0);

    /* A subrange's bounds replace the type's. */
    assert(dec_sub("9", 1, 9, &v) == 1 && v == 9);
    assert(dec_sub("10", 1, 9, &v) == 0);
    assert(dec_sub("0", 1, 9, &v) == 0);
    assert(dec_sub("-5", -5, -1, &v) == 1 && v == -5);

    /* Enumerations: ordinals always, names when a table is given. */
    assert(pas_decode_enum("1", 1, NULL, 0, 2, &o) == 1 && o == 1);
    assert(pas_decode_enum(" 2 ", 3, NULL, 0, 2, &o) == 1 && o == 2);
    assert(pas_decode_enum("3", 1, NULL, 0, 2, &o) == 0 && o == 2);
    assert(pas_decode_enum("green", 5, NULL, 0, 2, &o) == 0 && o == 2);
    assert(pas_decode_enum("green", 5, colors, 0, 2, &o) == 1 && o == 1);
    assert(pas_decode_enum(" BLUE\t", 6, colors, 0, 2, &o) == 1 && o == 2);
    assert(pas_decode_enum("0", 1, colors, 0, 2, &o) == 1 && o == 0);
    assert(pas_decode_enum("purple", 6, colors, 0, 2, &o) == 0 && o == 0);
    assert(pas_decode_enum("green ish", 9, colors, 0, 2, &o) == 0 && o == 0);
    assert(pas_decode_enum("gree", 4, colors, 0, 2, &o) == 0 && o == 0);
    assert(pas_decode_enum("", 0, colors, 0, 2, &o) == 0 && o == 0);
    /* A subrange keeps its bounds; the names table still spans the type. */
    assert(pas_decode_enum("blue", 4, colors, 0, 1, &o) == 0 && o == 0);
    assert(pas_decode_enum("blue", 4, colors, 1, 2, &o) == 1 && o == 2);
    assert(pas_decode_enum("red", 3, colors, 1, 2, &o) == 0 && o == 2);
    /* BOOLEAN. */
    assert(pas_decode_enum("tRuE", 4, bools, 0, 1, &o) == 1 && o == 1);
    assert(pas_decode_enum("0", 1, bools, 0, 1, &o) == 1 && o == 0);
    assert(pas_decode_enum("2", 1, bools, 0, 1, &o) == 0 && o == 0);

    /* CHAR: one character once the blanks are dropped, within lo..hi. */
    assert(pas_decode_char(" x ", 3, 0, 255, &ch) == 1 && ch == 'x');
    assert(pas_decode_char("xy", 2, 0, 255, &ch) == 0 && ch == 'x');
    assert(pas_decode_char(" ", 1, 0, 255, &ch) == 0 && ch == 'x');
    assert(pas_decode_char("", 0, 0, 255, &ch) == 0 && ch == 'x');
    assert(pas_decode_char("Q", 1, 'A', 'Z', &ch) == 1 && ch == 'Q');
    assert(pas_decode_char("q", 1, 'A', 'Z', &ch) == 0 && ch == 'Q');
    assert(pas_decode_char("\xff", 1, 0, 255, &ch) == 1 && ch == 255);

    /* REAL: the whole trimmed text is one number. */
    assert(pas_decode_real(" 3.25 ", 6, &d) == 1 && d == 3.25);
    assert(pas_decode_real("1e3", 3, &d) == 1 && d == 1000.0);
    assert(pas_decode_real(".5", 2, &d) == 1 && d == 0.5);
    assert(pas_decode_real("5.", 2, &d) == 1 && d == 5.0);
    assert(pas_decode_real("-7", 2, &d) == 1 && d == -7.0);
    assert(pas_decode_real("1.2.3", 5, &d) == 0 && d == -7.0);
    assert(pas_decode_real("", 0, &d) == 0 && d == -7.0);
    assert(pas_decode_real("abc", 3, &d) == 0 && d == -7.0);
    assert(pas_decode_real("1e999", 5, &d) == 0 && d == -7.0);
    assert(pas_decode_real("\n1", 2, &d) == 0 && d == -7.0);

    /* Null arguments answer 0. */
    assert(pas_decode_integer(NULL, 1, 16, 0, 0, 0, 0, &v) == 0);
    assert(pas_decode_integer("1", 1, 16, 0, 0, 0, 0, NULL) == 0);
    assert(pas_decode_enum(NULL, 1, bools, 0, 1, &o) == 0);
    assert(pas_decode_char(NULL, 1, 0, 255, &ch) == 0);
    assert(pas_decode_real(NULL, 1, &d) == 0);
    return 0;
}
