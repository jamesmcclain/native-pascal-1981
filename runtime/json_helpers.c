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
 * where it was read. Anything reading a length, a limit or a byte count out
 * of JSON needs the full 32 bits, so the conversion happens here instead.
 *
 * Out-of-range values are clamped rather than converted: casting a double
 * beyond long's range is undefined behaviour in C, and a caller checking
 * whether a value is integral will see the clamped result differ from the
 * original and reject it, which is the right answer for a number no 32-bit
 * field can hold.
 */
long pas_cjson_long(const cJSON *item)
{
    double value;

    if (item == NULL || !cJSON_IsNumber(item))
        return 0;
    value = item->valuedouble;
    if (value > 2147483647.0)
        return 2147483647L;
    if (value < -2147483648.0)
        return -2147483648L;
    return (long) value;
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
