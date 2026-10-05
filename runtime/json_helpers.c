#include <errno.h>
#include <stdio.h>
#include <stdlib.h>

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
