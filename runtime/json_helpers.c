#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <cjson/cJSON.h>

const char *pas_cjson_key(const cJSON *item)
{
    return item == NULL ? NULL : item->string;
}

const cJSON *pas_cjson_child(const cJSON *item, int index)
{
    const cJSON *child;

    if (item == NULL || index < 0)
        return NULL;
    child = item->child;
    while (child != NULL && index > 0) {
        child = child->next;
        index--;
    }
    return child;
}

/* A JSON number as a 32-bit integer, truncated toward zero.
 *
 * Pascal's TRUNC yields this dialect's INTEGER, which is 16 bits, so a JSON
 * value of 65536 comes back as 0 through it -- silently, and a long way from
 * where it was read. Anything reading a length, a limit, an array bound or a
 * byte count out of JSON needs the full 32 bits, so the conversion happens
 * here instead. See docs/dialect_notes.md.
 *
 * Out-of-range values are clamped rather than converted: casting a double
 * beyond int's range is undefined behaviour in C, and a caller checking
 * whether a value is integral will see the clamped result differ from the
 * original and reject it, which is the right answer for a number no 32-bit
 * field can hold.
 */
int pas_cjson_int32(const cJSON *item)
{
    double value;

    if (item == NULL || !cJSON_IsNumber(item))
        return 0;
    value = item->valuedouble;
    if (value > 2147483647.0)
        return 2147483647;
    if (value < -2147483648.0)
        return -2147483647 - 1;
    return (int) value;
}

/* The same, in 64 bits, for a value a 32-bit field cannot hold -- an
 * INTEGER64 literal, say. A JSON number is a double, so this is exact only
 * to 15 digits once printed; pas_cjson_get_int64 below is the exact reader for a field
 * written by pas_cjson_add_int64.
 */
long long pas_cjson_int64(const cJSON *item)
{
    double value;

    if (item == NULL || !cJSON_IsNumber(item))
        return 0;
    value = item->valuedouble;
    if (value >= 9223372036854775808.0)
        return 9223372036854775807LL;
    if (value <= -9223372036854775809.0)
        return -9223372036854775807LL - 1;
    return (long long) value;
}

/* Exact 64-bit integers between stages.
 *
 * Stages pass the AST as JSON, and cJSON keeps every number as a double, so
 * an integer of more than 15 digits used to round on its way from the lexer
 * to codegen: 9223372036854775805 compiled as 9223372036854775807. The
 * number field stays a number (so every existing reader and the AST shape
 * are unchanged), and a value the printed double may not hold also gets a
 * sibling string
 * field, KEY_int64, with its exact decimal text. pas_cjson_get_int64 prefers
 * that text. Only fields written through pas_cjson_add_int64 (jsonutil's
 * AddIntField, and the lexer's integer token value) carry it.
 */
#define PAS_INT64_EXACT_SUFFIX "_int64"

static int pas_int64_companion_key(char *buf, size_t size, const char *key)
{
    int n = snprintf(buf, size, "%s" PAS_INT64_EXACT_SUFFIX, key);
    return n > 0 && (size_t) n < size;
}

void pas_cjson_add_int64(cJSON *obj, const char *key, long long value)
{
    /* Not 2^53: cJSON prints a double with 15 significant digits and keeps
     * that text whenever it reads back within a relative epsilon, so
     * 9007199254740992 (2^53) travelled as 9.00719925474099e+15. Every
     * integer of at most 15 digits survives that round trip exactly. */
    const long long exact_limit = 999999999999999LL;
    char ckey[300];
    char text[32];

    cJSON_AddItemToObject(obj, key, cJSON_CreateNumber((double) value));
    if (value >= -exact_limit && value <= exact_limit)
        return;
    if (!pas_int64_companion_key(ckey, sizeof ckey, key))
        return;
    snprintf(text, sizeof text, "%lld", value);
    cJSON_AddItemToObject(obj, ckey, cJSON_CreateString(text));
}

long long pas_cjson_get_int64(const cJSON *obj, const char *key)
{
    char ckey[300];
    const char *text;
    char *end;
    long long value;

    if (obj == NULL || key == NULL)
        return 0;
    if (pas_int64_companion_key(ckey, sizeof ckey, key)) {
        text = cJSON_GetStringValue(cJSON_GetObjectItem(obj, ckey));
        if (text != NULL && *text != '\0') {
            errno = 0;
            value = strtoll(text, &end, 10);
            if (errno == 0 && *end == '\0')
                return value;
        }
    }
    return pas_cjson_int64(cJSON_GetObjectItem(obj, key));
}

/* Exact REAL values between stages.
 *
 * cJSON prints a double with 15 significant digits and keeps that text
 * whenever it reads back within a relative epsilon, so a REAL value
 * needing 16 or 17 digits shifted between stages: 1.7976931348623157E308
 * printed as 1.79769313486232e+308, which no double holds, and came back
 * as infinity. Every stage that writes JSON prints through
 * pas_cjson_print_exact, which first turns each finite number whose cJSON
 * spelling would not read back bit for bit into a raw item holding its
 * shortest exact spelling. The text is still a JSON number, so readers
 * (cJSON_Parse reads numbers with strtod) and the AST shape are unchanged.
 * -0.0 keeps its sign the same way.
 */

/* The shortest "%.*g" spelling (at most 17 digits) that strtod reads back
 * as exactly v. v must be finite. */
static void pas_real_shortest_g(double v, char *buf, size_t size)
{
    int prec;

    for (prec = 1; prec <= 17; prec++) {
        snprintf(buf, size, "%.*g", prec, v);
        if (strtod(buf, NULL) == v)
            return;
    }
}

/* Does cJSON's own print_number spelling of v read back exactly? It
 * prints an int-range integral value with "%d" (exact, but it drops the
 * sign of -0.0) and anything else with "%1.15g", unless that reads back
 * outside a relative epsilon. */
static int pas_cjson_number_prints_exactly(double v)
{
    char buf[64];

    if (v == 0.0)
        return !signbit(v);
    if (v >= -2147483648.0 && v <= 2147483647.0 && v == (double) (int) v)
        return 1;
    snprintf(buf, sizeof buf, "%1.15g", v);
    return strtod(buf, NULL) == v;
}

static void pas_cjson_exact_numbers(cJSON *item)
{
    char text[64];
    size_t len;
    char *copy;

    for (; item != NULL; item = item->next) {
        if (item->child != NULL)
            pas_cjson_exact_numbers(item->child);
        if (!cJSON_IsNumber(item) || !isfinite(item->valuedouble) || pas_cjson_number_prints_exactly(item->valuedouble))
            continue;
        pas_real_shortest_g(item->valuedouble, text, sizeof text);
        len = strlen(text);
        copy = cJSON_malloc(len + 1);
        if (copy == NULL)
            continue;           /* keep the number; cJSON prints it as before */
        memcpy(copy, text, len + 1);
        /* Keep the key's flag bits; a number owns no valuestring. */
        item->type = cJSON_Raw | (item->type & (cJSON_IsReference | cJSON_StringIsConst));
        item->valuestring = copy;
    }
}

/* cJSON_Print (formatted != 0) or cJSON_PrintUnformatted of item, with
 * every number spelled exactly. The numbers of the tree become raw items,
 * so a stage prints its tree last. */
char *pas_cjson_print_exact(cJSON *item, int formatted)
{
    cJSON *next;

    if (item != NULL) {
        next = item->next;
        item->next = NULL;
        pas_cjson_exact_numbers(item);
        item->next = next;
    }
    return formatted ? cJSON_Print(item) : cJSON_PrintUnformatted(item);
}

/* The correctly rounded value of a REAL literal's text: len bytes at text,
 * which the lexer has matched against digit+ '.' digit+ [E [sign] digit+].
 * The text is read whole, so a literal longer than a Str255 lexeme still
 * gets its exact value. Overflow gives an infinity (see
 * pas_real_is_finite); underflow gives the nearest subnormal or zero, as
 * strtod does. */
double pas_real_literal_value(const char *text, int len)
{
    char small[128];
    char *buf = small;
    double v;

    if (len < 0)
        len = 0;
    if ((size_t) len >= sizeof small) {
        buf = malloc((size_t) len + 1);
        if (buf == NULL)
            return HUGE_VAL;    /* reported as out of range */
    }
    memcpy(buf, text, (size_t) len);
    buf[len] = '\0';
    v = strtod(buf, NULL);
    if (buf != small)
        free(buf);
    return v;
}

/* A JSON string of the len bytes at text, which need not end in NUL. The
 * lexer stores a numeric literal's lexeme with it, so a literal longer
 * than a Str255 keeps its whole text in the token. NULL if out of memory
 * (cJSON then omits the item). */
cJSON *pas_cjson_create_string_span(const char *text, int len)
{
    char *buf;
    cJSON *item;

    if (len < 0)
        len = 0;
    buf = malloc((size_t) len + 1);
    if (buf == NULL)
        return NULL;
    memcpy(buf, text, (size_t) len);
    buf[len] = '\0';
    item = cJSON_CreateString(buf);
    free(buf);
    return item;
}

int pas_real_is_finite(double v)
{
    return isfinite(v) ? 1 : 0;
}

/* The shortest spelling of v as a REAL literal of the dialect's grammar
 * (digit+ '.' digit+ [E [-] digit+], after a '-' for a negative v) that
 * reads back as exactly v: plain decimal for decimal exponents from -5 to
 * 15, scientific otherwise. pretty81 prints REAL literals with it. Empty
 * for a non-finite v, which no literal spells. The result is in a static
 * buffer. */
const char *pas_real_literal_text(double v)
{
    static char out[64];
    char sci[40];
    char digits[24];
    char *p;
    char *e;
    int prec;
    int nd = 0;
    int exp10;
    int i;
    size_t o = 0;

    if (!isfinite(v))
        return "";
    /* The shortest "%.*e" that reads back exactly: d.dddde[+-]XX. */
    for (prec = 0; prec <= 16; prec++) {
        snprintf(sci, sizeof sci, "%.*e", prec, v);
        if (strtod(sci, NULL) == v)
            break;
    }
    p = sci;
    if (*p == '-') {
        out[o++] = '-';
        p++;
    }
    e = strchr(p, 'e');
    if (e == NULL)
        return "";
    exp10 = (int) strtol(e + 1, NULL, 10);
    for (; p < e && nd < 20; p++)
        if (*p != '.')
            digits[nd++] = *p;
    /* The shortest digits end in a nonzero digit, except for zero itself. */
    while (nd > 1 && digits[nd - 1] == '0')
        nd--;
    if (exp10 >= -5 && exp10 < 16) {
        if (exp10 < 0) {
            out[o++] = '0';
            out[o++] = '.';
            for (i = -1; i > exp10; i--)
                out[o++] = '0';
            for (i = 0; i < nd; i++)
                out[o++] = digits[i];
        } else {
            for (i = 0; i <= exp10; i++)
                out[o++] = i < nd ? digits[i] : '0';
            out[o++] = '.';
            if (nd > exp10 + 1)
                for (i = exp10 + 1; i < nd; i++)
                    out[o++] = digits[i];
            else
                out[o++] = '0';
        }
        out[o] = '\0';
    } else {
        out[o++] = digits[0];
        out[o++] = '.';
        if (nd > 1)
            for (i = 1; i < nd; i++)
                out[o++] = digits[i];
        else
            out[o++] = '0';
        snprintf(out + o, sizeof out - o, "E%d", exp10);
    }
    return out;
}

char *pas_read_text_file(const char *path)
{
    FILE *stream;
    long size;
    char *text;

    stream = fopen(path, "rb");
    if (stream == NULL)
        return NULL;
    if (fseek(stream, 0, SEEK_END) != 0) {
        fclose(stream);
        return NULL;
    }
    size = ftell(stream);
    if (size < 0 || fseek(stream, 0, SEEK_SET) != 0) {
        fclose(stream);
        return NULL;
    }
    text = malloc((size_t) size + 1);
    if (text == NULL) {
        fclose(stream);
        return NULL;
    }
    if (fread(text, 1, (size_t) size, stream) != (size_t) size) {
        free(text);
        fclose(stream);
        return NULL;
    }
    text[size] = '\0';
    fclose(stream);
    return text;
}
