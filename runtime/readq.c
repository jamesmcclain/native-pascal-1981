#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "pascalrt.h"

/* Weak fallbacks provided when fileops.o is not linked (e.g. stdin-only
 * test drivers).  The strong definitions live in fileops.c. */
__attribute__((weak))
void pas_file_attach_std(struct pas_file_fcb *in, struct pas_file_fcb *out)
{
    if (in && !(in->mode & MODE_STD)) {
        in->handle = stdin;
        in->mode = MODE_READ | MODE_STD | MODE_PENDING;
    }
    if (out && !(out->mode & MODE_STD)) {
        out->handle = stdout;
        out->mode = MODE_WRITE | MODE_EOF | MODE_STD;
    }
}

__attribute__((weak))
const char *pas_enum_write_token(int32_t value, const char **names, int count)
{
    enum { RING = 16, WIDTH = 32 };
    static char bufs[RING][WIDTH];
    static int slot = 0;
    if (value >= 0 && value < count && names)
        return names[value];
    slot = (slot + 1) % RING;
    snprintf(bufs[slot], WIDTH, "%d", value);
    return bufs[slot];
}

static int skip_ws_except_nl(void)
{
    int ch;
    while ((ch = getchar()) != EOF) {
        if (ch == '\n' || !isspace((unsigned char) ch))
            return ch;
    }
    return EOF;
}

static void unread(int ch)
{
    if (ch != EOF)
        ungetc(ch, stdin);
}

static void die(const char *msg)
{
    fprintf(stderr, "runtime error: %s\n", msg);
    fflush(stdout);
    fflush(stderr);
    abort();
}

static int read_identifier_token(char *buf, int cap)
{
    int ch = skip_ws_except_nl();
    if (ch == EOF)
        die("unexpected EOF while reading enum");
    if (!isalpha((unsigned char) ch)) {
        unread(ch);
        die("malformed enum input");
    }
    int n = 0;
    do {
        if (n + 1 < cap)
            buf[n++] = (char) toupper((unsigned char) ch);
        ch = getchar();
    } while (ch != EOF && (isalpha((unsigned char) ch) || isdigit((unsigned char) ch)));
    unread(ch);
    buf[n] = '\0';
    return 0;
}

int pas_read_enum_name(int32_t *out, const char **names, int count)
{
    int ch = skip_ws_except_nl();
    if (ch == EOF)
        die("unexpected EOF while reading enum");
    if (isdigit((unsigned char) ch) || ch == '-' || ch == '+') {
        unread(ch);
        long v;
        if (scanf("%ld", &v) != 1)
            die("malformed enum input");
        *out = (int32_t) v;
        return 0;
    }
    unread(ch);
    char tok[256];
    read_identifier_token(tok, (int) sizeof(tok));
    for (int i = 0; i < count; i++) {
        if (names && names[i] && strcmp(tok, names[i]) == 0) {
            *out = i;
            return 0;
        }
    }
    die("malformed enum input");
    return -1;
}

int pas_read_int(int32_t *out)
{
    int ch = skip_ws_except_nl();
    if (ch == EOF)
        die("unexpected EOF while reading integer");
    unread(ch);
    long v;
    if (scanf("%ld", &v) != 1)
        die("malformed integer input");
    *out = (int32_t) v;
    return 0;
}

int pas_read_word(uint16_t *out)
{
    int32_t v = 0;
    if (pas_read_int(&v) != 0)
        return -1;
    if (v < 0 || v > 65535)
        die("word out of range");
    *out = (uint16_t) v;
    return 0;
}

int pas_read_real(double *out)
{
    int ch = skip_ws_except_nl();
    if (ch == EOF)
        die("unexpected EOF while reading real");
    unread(ch);
    if (scanf("%lf", out) != 1)
        die("malformed real input");
    return 0;
}

int pas_read_char(uint8_t *out)
{
    int ch = getchar();
    if (ch == EOF)
        die("unexpected EOF while reading char");
    *out = (ch == '\n') ? ' ' : (uint8_t) ch;
    return 0;
}

int pas_read_lstring(uint8_t *buf, int cap)
{
    int ch;
    int n = 0;
    while ((ch = getchar()) != EOF && ch != '\n') {
        if (n < cap)
            buf[1 + n] = (uint8_t) ch;
        n++;
    }
    if (ch == EOF)
        die("unexpected EOF while reading string");
    if (ch == '\n')
        unread(ch);
    if (cap < 0)
        cap = 0;
    buf[0] = (uint8_t) (n < cap ? n : cap);
    return 0;
}

int pas_read_string(uint8_t *buf, int cap)
{
    /* stdin variant of pas_fread_string: fill up to cap chars, stop early
     * at the line marker (pushed back), blank-pad the remainder. */
    int ch = 0;
    int n = 0;
    while (n < cap && (ch = getchar()) != EOF && ch != '\n')
        buf[n++] = (uint8_t) ch;
    if (n < cap) {
        if (ch == EOF)
            die("unexpected EOF while reading string");
        unread(ch);
    }
    while (n < cap)
        buf[n++] = ' ';
    return 0;
}

void pas_readln_skip(void)
{
    int ch;
    while ((ch = getchar()) != EOF && ch != '\n') {
    }
}
