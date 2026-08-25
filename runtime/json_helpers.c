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
