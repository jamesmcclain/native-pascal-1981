#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "pascalrt.h"

static void die(const char *msg)
{
    fprintf(stderr, "%s\n", msg);
    fflush(stdout);
    fflush(stderr);
    abort();
}

/* Trapped I/O (manual ch.12 File Field Values): when F.TRAP is set, an
 * operational I/O error records a code in F.ERRS and the operation is
 * abandoned instead of aborting; the program inspects and clears F.ERRS.
 * Returns 1 when trapped (caller must bail out), aborts otherwise.
 *
 * Error codes are internal [INFERRED] — the vintage runtime's numeric
 * codes are partly observed from the vintage runtime:
 *   1 create failed      [modern-internal]
 *   2 mode violation     [modern-internal]
 *   3 GET past EOF       [modern-internal]
 *   4 read failed        [modern-internal]
 *   5 write failed       [modern-internal]
 *   10 RESET missing/open failed [vintage-observed, D-012]
 *   14 malformed formatted READ [vintage-observed, D-013]
 * Converted sites: RESET/REWRITE open failures, GET/PUT mode violations,
 * GET-past-eof, component read/write failures, and malformed formatted
 * file READ.  Structural errors (null FCB/buffer, bad ASSIGN arguments,
 * stream_for mode aborts) still abort unconditionally. */
static int io_error(struct pas_file_fcb *f, int code, const char *msg)
{
    if (f && f->trap) {
        f->errs = code;
        return 1;
    }
    die(msg);
    return 0;                   /* unreachable */
}

static size_t elem_size(struct pas_file_fcb *f)
{
    return (size_t) (f->elem_size > 0 ? f->elem_size : 1);
}

static int current_mode(struct pas_file_fcb *f)
{
    return f->mode & MODE_BITS;
}

static int is_eof(struct pas_file_fcb *f)
{
    return (f->mode & MODE_EOF) != 0;
}

static int is_pending(struct pas_file_fcb *f)
{
    return (f->mode & MODE_PENDING) != 0;
}

/* Every buffer transition passes through here. The buffer holds a component
 * exactly when a fill succeeded in read mode (not at EOF, not pending); EOF,
 * a pending or consumed component, write mode (REWRITE, after PUT) and a
 * closed file leave it undefined. A tracked buffer's INITCK state follows,
 * wholly; Pascal writes to F^ set individual leaves in between. */
static void set_mode_flags(struct pas_file_fcb *f, int mode, int eof, int eoln, int pending)
{
    int keep = f->mode & (MODE_STD | MODE_OWNS_HANDLE | MODE_TEMP);
    f->mode = keep | mode | (eof ? MODE_EOF : 0) | (eoln ? MODE_EOLN : 0) | (pending ? MODE_PENDING : 0);
    if (f->initck_state)
        memset(f->initck_state, mode == MODE_READ && !eof && !pending, (size_t) f->initck_n);
}

static FILE *ensure_handle(struct pas_file_fcb *f)
{
    if (!f)
        die("file runtime: null fcb");
    if (f->handle)
        return f->handle;
    if (f->name) {
        f->handle = fopen(f->name, "r+b");
        if (!f->handle)
            die("file runtime: open failed");
    } else {
        f->handle = pas_project_tmpfile();
        if (!f->handle)
            die("file runtime: temporary file failed");
        f->mode |= MODE_TEMP;
    }
    f->mode |= MODE_OWNS_HANDLE;
    return f->handle;
}

static void checked_buffer(struct pas_file_fcb *f)
{
    if (!f || !f->buffer)
        die("file runtime: null buffer");
}

/* DOS CR/LF translation: vintage
 * PC-DOS TEXT files mark line ends with "\r\n".  On input, a "\r\n" pair
 * is folded into a single '\n' line marker so EOLN/READLN/F^ semantics
 * match the manual on DOS-produced files; a bare '\r' (not followed by
 * '\n') is passed through as ordinary data.  Output keeps the host's
 * '\n' marker — this is a Linux-target adaptation, not DOS emulation.
 * Binary FILE OF T never translates (component bytes are sacred). */
static int text_getc(FILE *h)
{
    int ch = fgetc(h);
    if (ch != '\r')
        return ch;
    int next = fgetc(h);
    if (next == '\n')
        return '\n';            /* fold CRLF into one marker */
    if (next != EOF)
        ungetc(next, h);
    return '\r';                /* bare CR is data */
}

static void raw_get(struct pas_file_fcb *f, int allow_eof)
{
    FILE *h = ensure_handle(f);
    checked_buffer(f);
    if (current_mode(f) != MODE_READ) {
        if (io_error(f, 2, "file runtime: GET requires RESET/read mode"))
            return;
    }
    if (!allow_eof && is_eof(f)) {
        if (io_error(f, 3, "file runtime: GET past eof"))
            return;
    }

    if (f->structure == STRUCT_TEXT) {
        int ch = text_getc(h);
        if (ch == EOF) {
            if (feof(h)) {
                set_mode_flags(f, MODE_READ, 1, 0, 0);
                f->touched = 0;
                return;
            }
            if (io_error(f, 4, "file runtime: read failed")) {
                set_mode_flags(f, MODE_READ, 1, 0, 0);
                return;
            }
        }
        int eoln = (ch == '\n');
        *((unsigned char *) f->buffer) = eoln ? ' ' : (unsigned char) ch;
        set_mode_flags(f, MODE_READ, 0, eoln, 0);
        f->touched = 0;
        return;
    }

    size_t n = elem_size(f);
    size_t got = fread(f->buffer, 1, n, h);
    if (got != n) {
        if (feof(h)) {
            set_mode_flags(f, MODE_READ, 1, 0, 0);
            f->touched = 0;
            return;
        }
        if (io_error(f, 4, "file runtime: read failed")) {
            set_mode_flags(f, MODE_READ, 1, 0, 0);
            return;
        }
    }
    set_mode_flags(f, MODE_READ, 0, 0, 0);
    f->touched = 0;
}

static void force_fill(struct pas_file_fcb *f)
{
    if (!f)
        return;
    if (is_pending(f))
        raw_get(f, 1);
}

/* ---- Unified character source (buffer-variable model + host stream) ----
 *
 * The FCB's current-component buffer and the host stream form one logical
 * character sequence. Formatted readers (READ/READSET/READFN/READLN-skip)
 * must consume a live buffered component before touching the stream,
 * otherwise the component supplied by RESET's implicit GET is lost.
 */

static int fcb_next_char(struct pas_file_fcb *f, FILE *h)
{
    if (!f || !f->buffer || current_mode(f) != MODE_READ)
        return fgetc(h);
    if (is_eof(f))
        return EOF;
    if (!is_pending(f)) {
        /* The buffer holds the current component: consume it. A TEXT line
         * marker is stored as a blank with MODE_EOLN set; hand the reader the
         * real '\n' so delimiter logic sees the marker. */
        int ch = *((unsigned char *) f->buffer);
        if (f->structure == STRUCT_TEXT && (f->mode & MODE_EOLN) != 0)
            ch = '\n';
        set_mode_flags(f, MODE_READ, 0, 0, 1);  /* consumed -> pending */
        f->touched = 0;
        return ch;
    }
    int ch = (f->structure == STRUCT_TEXT) ? text_getc(h) : fgetc(h);
    if (ch == EOF)
        set_mode_flags(f, MODE_READ, 1, 0, 0);
    return ch;
}

static void fcb_unget_char(struct pas_file_fcb *f, FILE *h, int ch)
{
    /* Push a character back as the FCB's current component (so F^/EOF/EOLN
     * observe it), falling back to stdio pushback when there is no FCB. */
    if (ch == EOF)
        return;
    if (!f || !f->buffer || current_mode(f) != MODE_READ) {
        ungetc(ch, h);
        return;
    }
    int eoln = (f->structure == STRUCT_TEXT && ch == '\n');
    *((unsigned char *) f->buffer) = eoln ? ' ' : (unsigned char) ch;
    set_mode_flags(f, MODE_READ, 0, eoln, 0);
    f->touched = 0;
}

void pas_file_attach_std(struct pas_file_fcb *in, struct pas_file_fcb *out)
{
    if (in && !(in->mode & MODE_STD)) {
        in->handle = stdin;
        set_mode_flags(in, MODE_READ, 0, 0, 1);
        in->mode |= MODE_STD;
    }
    if (out && !(out->mode & MODE_STD)) {
        out->handle = stdout;
        set_mode_flags(out, MODE_WRITE, 1, 0, 0);
        out->mode |= MODE_STD;
    }
}

void *pas_file_buffer(struct pas_file_fcb *f)
{
    force_fill(f);
    return f ? f->buffer : NULL;
}

void pas_file_touch_buffer(struct pas_file_fcb *f)
{
    if (f)
        f->touched = 1;
}

void pas_file_get(struct pas_file_fcb *f)
{
    /* If RESET's implicit GET is still pending, materialize the current
     * component first so an explicit GET advances to the *next* one. */
    force_fill(f);
    raw_get(f, 0);
}

void pas_file_reset(struct pas_file_fcb *f)
{
    if (!f)
        die("file runtime: null fcb");
    if (!f->handle && f->name) {
        f->handle = fopen(f->name, "r+b");
        if (!f->handle) {
            if (io_error(f, 10, "file runtime: open failed"))
                return;
        }
        f->mode |= MODE_OWNS_HANDLE;
    }
    FILE *h = ensure_handle(f);
    if (current_mode(f) == MODE_WRITE && fflush(h) != 0)
        die("file runtime: flush failed");
    rewind(h);
    /* The manual-required implicit first GET is deferred: the current
     * component is marked PENDING and materialized by force_fill at the
     * first F^ / EOF / EOLN / formatted-read use site, so the buffer-variable
     * model and the formatted readers share a single fill path. */
    set_mode_flags(f, MODE_READ, 0, 0, 1);
}

void pas_file_rewrite(struct pas_file_fcb *f)
{
    if (!f)
        die("file runtime: null fcb");
    if (f->mode & MODE_STD) {
        if (f->handle && fflush(f->handle) != 0)
            die("file runtime: flush failed");
        set_mode_flags(f, MODE_WRITE, 1, 0, 0);
        return;
    }
    if (f->handle && (f->mode & MODE_OWNS_HANDLE))
        fclose(f->handle);
    f->handle = NULL;
    f->mode &= ~MODE_OWNS_HANDLE;
    if (f->name) {
        f->handle = fopen(f->name, "w+b");
        if (!f->handle) {
            perror(f->name ? f->name : "<unnamed>");
            if (io_error(f, 1, "file runtime: create failed"))
                return;
        }
        f->mode &= ~MODE_TEMP;
    } else {
        f->handle = pas_project_tmpfile();
        if (!f->handle)
            die("file runtime: temporary file failed");
        f->mode |= MODE_TEMP;
    }
    f->mode |= MODE_OWNS_HANDLE;
    set_mode_flags(f, MODE_WRITE, 1, 0, 0);
    f->touched = 0;
}

void pas_file_put(struct pas_file_fcb *f)
{
    FILE *h = ensure_handle(f);
    checked_buffer(f);
    if (current_mode(f) != MODE_WRITE) {
        if (io_error(f, 2, "file runtime: PUT requires REWRITE/write mode"))
            return;
    }

    size_t n = f->structure == STRUCT_TEXT ? 1 : elem_size(f);
    if (fwrite(f->buffer, 1, n, h) != n) {
        if (io_error(f, 5, "file runtime: write failed"))
            return;
    }
    int eoln = (f->structure == STRUCT_TEXT && *((unsigned char *) f->buffer) == '\n');
    set_mode_flags(f, MODE_WRITE, 1, eoln, 0);
    f->touched = 0;
}

/* CR/LF note: with text_getc translation in place, the final-marker probe
 * below needs no change — a DOS file ending in "\r\n" has '\n' as its last
 * byte, so the existing last-byte check already recognizes the marker. */
static void append_final_text_marker_if_needed(struct pas_file_fcb *f)
{
    if (!f || f->structure != STRUCT_TEXT || current_mode(f) != MODE_WRITE || !f->handle || (f->mode & MODE_STD))
        return;
    FILE *h = f->handle;
    if (fflush(h) != 0)
        die("file runtime: flush failed");
    long pos = ftell(h);
    if (pos <= 0)
        return;
    if (fseek(h, -1, SEEK_END) != 0)
        die("file runtime: seek failed");
    int ch = fgetc(h);
    if (ch != '\n') {
        if (fseek(h, 0, SEEK_END) != 0)
            die("file runtime: seek failed");
        if (fputc('\n', h) == EOF)
            die("file runtime: final line marker write failed");
    }
    fflush(h);
}

void pas_file_close(struct pas_file_fcb *f)
{
    if (!f)
        die("file runtime: null fcb");
    append_final_text_marker_if_needed(f);
    if (f->handle && (f->mode & MODE_OWNS_HANDLE))
        fclose(f->handle);
    f->handle = NULL;
    f->mode &= ~(MODE_OWNS_HANDLE | MODE_PENDING | MODE_EOF | MODE_EOLN);
    set_mode_flags(f, MODE_CLOSED, 0, 0, 0);
}

void pas_file_discard(struct pas_file_fcb *f)
{
    if (!f)
        die("file runtime: null fcb");
    char *name = f->name ? strdup(f->name) : NULL;
    int was_temp = (f->mode & MODE_TEMP) != 0;
    pas_file_close(f);
    if (name) {
        remove(name);
        free(name);
    } else if (was_temp) {
        /* Anonymous temporary storage is deleted by fclose. */
    }
}

static void assign_name_closed(struct pas_file_fcb *f, const char *name, int len)
{
    if (!f)
        die("file runtime: null fcb");
    if (current_mode(f) != MODE_CLOSED || f->handle)
        die("file runtime: ASSIGN on open file");
    if (!name || len < 0)
        die("file runtime: bad ASSIGN name");
    while (len > 0 && name[len - 1] == ' ')
        len--;
    if (len == 0)
        die("file runtime: empty filename in ASSIGN");
    if (f->name)
        free(f->name);
    f->name = NULL;
    f->mode &= ~MODE_TEMP;
    if (len == 1 && name[0] == '\0') {
        f->mode |= MODE_TEMP;
        return;
    }
    f->name = (char *) malloc((size_t) len + 1);
    if (!f->name)
        die("file runtime: filename allocation failed");
    memcpy(f->name, name, (size_t) len);
    f->name[len] = '\0';
}

void pas_file_assign(struct pas_file_fcb *f, const char *name, int len)
{
    assign_name_closed(f, name, len);
}

static void require_text_read(struct pas_file_fcb *f)
{
    if (!f)
        die("file runtime: null fcb");
    if (f->structure != STRUCT_TEXT)
        die("file runtime: TEXT file required");
    if (current_mode(f) == MODE_CLOSED)
        pas_file_reset(f);
    if (current_mode(f) != MODE_READ)
        die("file runtime: read requires RESET/read mode");
}

static int is_leading_skip(int ch)
{
    return ch == ' ' || ch == '\t' || ch == '\f' || ch == '\n';
}

static int set_contains(const uint64_t *set_words, int ch)
{
    if (ch < 0 || ch > 255)
        return 0;
    return (set_words[ch / 64] & ((uint64_t) 1 << (ch % 64))) != 0;
}

void pas_freadset(struct pas_file_fcb *src, unsigned char *lstr, int capacity, const uint64_t *set_words)
{
    if (!lstr || capacity < 0 || !set_words)
        die("file runtime: bad READSET argument");
    require_text_read(src);
    FILE *h = ensure_handle(src);
    int ch;
    while ((ch = fcb_next_char(src, h)) != EOF && is_leading_skip(ch)) {
    }
    int len = 0;
    while (ch != EOF && ch != '\n' && len < capacity && set_contains(set_words, ch)) {
        lstr[1 + len++] = (unsigned char) ch;
        ch = fcb_next_char(src, h);
    }
    if (ch == EOF) {
        set_mode_flags(src, MODE_READ, 1, 0, 0);
    } else {
        /* Delimiter (line marker, non-member, or capacity overflow char)
         * becomes the current component again. */
        fcb_unget_char(src, h, ch);
    }
    lstr[0] = (unsigned char) len;
}

void pas_fread_filename(struct pas_file_fcb *src, struct pas_file_fcb *target)
{
    if (!target)
        die("file runtime: null target fcb");
    require_text_read(src);
    FILE *h = ensure_handle(src);
    char namebuf[260];
    int len = 0;
    int ch;
    while ((ch = fcb_next_char(src, h)) != EOF && is_leading_skip(ch)) {
    }
    while (ch != EOF && ch != '\n' && ch != ' ' && ch != '\t' && ch != '\f' && len < (int) sizeof(namebuf)) {
        namebuf[len++] = (char) ch;
        ch = fcb_next_char(src, h);
    }
    if (ch == EOF) {
        set_mode_flags(src, MODE_READ, 1, 0, 0);
    } else {
        /* READFN never consumes the line marker; the trailing delimiter
         * becomes the current component again. */
        fcb_unget_char(src, h, ch);
    }
    assign_name_closed(target, namebuf, len);
}

int pas_file_eof(struct pas_file_fcb *f)
{
    if (!f)
        die("file runtime: EOF null file");
    force_fill(f);
    return current_mode(f) == MODE_WRITE || is_eof(f);
}

int pas_file_eoln(struct pas_file_fcb *f)
{
    if (!f)
        die("file runtime: EOLN null file");
    force_fill(f);
    if (pas_file_eof(f))
        die("file runtime: EOLN at eof");
    if (f->structure != STRUCT_TEXT)
        die("file runtime: EOLN requires TEXT file");
    return (f->mode & MODE_EOLN) != 0;
}

static FILE *stream_for(struct pas_file_fcb *f, int writing)
{
    if (!f)
        return writing ? stdout : stdin;
    if (writing) {
        /* Writing requires generation mode. Silently flipping a read-mode
         * file here used to clobber bytes at the current offset. When the
         * trapped-I/O subsystem (F.TRAP/F.ERRS) lands, these die sites
         * become the trap dispatch points. */
        if (current_mode(f) == MODE_READ)
            die("file runtime: WRITE requires REWRITE/write mode");
        if (current_mode(f) == MODE_CLOSED)
            die("file runtime: WRITE to closed file requires REWRITE");
    } else {
        if (current_mode(f) == MODE_WRITE)
            die("file runtime: READ requires RESET/read mode");
        /* Reading a closed file performs the implicit RESET (consistent with
         * require_text_read for READSET/READFN). */
        if (current_mode(f) == MODE_CLOSED)
            pas_file_reset(f);
    }
    return ensure_handle(f);
}

int pas_write_fmt(struct pas_file_fcb *f, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int r = vfprintf(stream_for(f, 1), fmt, ap);
    va_end(ap);
    return r;
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

static int fcb_skip_ws_except_nl(struct pas_file_fcb *f, FILE *h)
{
    int ch;
    while ((ch = fcb_next_char(f, h)) != EOF) {
        if (ch == '\n' || !isspace((unsigned char) ch))
            return ch;
    }
    return EOF;
}

/* Parse through the FCB character source, including RESET's buffered first
 * character. Do not touch the destination when a trapped read fails. */
static int fread_wide_decimal(struct pas_file_fcb *f, int bits, int64_t *out)
{
    FILE *h = stream_for(f, 0);
    int ch;
    /* Skip newlines too, as the vintage reader's fscanf("%ld") does. */
    do
        ch = fcb_next_char(f, h);
    while (ch != EOF && isspace((unsigned char) ch));
    if (ch == EOF)
        die("runtime error: unexpected EOF while reading integer");
    char token[32];
    int n = 0, overflow = 0;
    if (ch == '+' || ch == '-') {
        token[n++] = (char) ch;
        ch = fcb_next_char(f, h);
    }
    if (ch == EOF || !isdigit((unsigned char) ch)) {
        fcb_unget_char(f, h, ch);
        return io_error(f, 14, "runtime error: malformed integer input") ? -1 : 0;
    }
    /* Leading zeros do not count toward the token's length limit. */
    int sign_len = n;
    do {
        if (n == sign_len && ch == '0');
        else if (n < (int) sizeof(token) - 1)
            token[n++] = (char) ch;
        else
            overflow = 1;
        ch = fcb_next_char(f, h);
    } while (ch != EOF && isdigit((unsigned char) ch));
    fcb_unget_char(f, h, ch);
    if (n == sign_len)
        token[n++] = '0';
    token[n] = '\0';
    errno = 0;
    long long value = strtoll(token, NULL, 10);
    if (overflow || errno == ERANGE || (bits == 32 && (value < INT32_MIN || value > INT32_MAX))
        || (bits == 16 && (value < INT16_MIN || value > INT16_MAX)))
        return io_error(f, 14, "runtime error: integer out of range") ? -1 : 0;
    *out = (int64_t) value;
    return 0;
}

/* File counterpart of pas_read_int16: range-checked, never wrapped. */
int pas_fread_int16(struct pas_file_fcb *f, int16_t *out)
{
    int64_t value;
    if (fread_wide_decimal(f, 16, &value) != 0)
        return -1;
    *out = (int16_t) value;
    return 0;
}

int pas_fread_int32(struct pas_file_fcb *f, int32_t *out)
{
    int64_t value;
    if (fread_wide_decimal(f, 32, &value) != 0)
        return -1;
    *out = (int32_t) value;
    return 0;
}

int pas_fread_int64(struct pas_file_fcb *f, int64_t *out)
{
    return fread_wide_decimal(f, 64, out);
}

/* An enum READ by number: an ordinal of the type, lo..hi, so BOOLEAN 2 is
 * no TRUE and an enum subrange keeps its lower bound. Like the readers
 * above, it parses through the FCB character source, so a trapped failure
 * leaves F^ on the character that stopped the token. */
int pas_fread_enum_ord(struct pas_file_fcb *f, int32_t *out, int lo, int hi)
{
    int64_t v;
    if (fread_wide_decimal(f, 64, &v) != 0)
        return -1;
    if (v < lo || v > hi)
        return io_error(f, 14, "runtime error: enum value out of range") ? -1 : 0;
    *out = (int32_t) v;
    return 0;
}

int pas_fread_word(struct pas_file_fcb *f, uint16_t *out)
{
    /* As in pas_read_word, check the full value, not a 32-bit narrowing. */
    int64_t v = 0;
    if (fread_wide_decimal(f, 64, &v) != 0)
        return -1;
    if (v < 0 || v > 65535)
        die("runtime error: word out of range");
    *out = (uint16_t) v;
    return 0;
}

static int is_base_digit(int ch, int base)
{
    if (ch == EOF)
        return 0;
    if (base == 16)
        return isxdigit((unsigned char) ch);
    if (base == 8)
        return ch >= '0' && ch <= '7';
    return isdigit((unsigned char) ch);
}

/* The pointer token scanner shared by pas_read_ptr and pas_fread_ptr (see
 * pascalrt.h). The syntax is strtoll's (decimal, 0x hex, 0 octal, optional
 * sign), but leading zeros carry no magnitude and the magnitude is
 * unsigned, so every value WRITE can emit for a 64-bit pointer (unsigned
 * decimal) reads back, however it is padded. */
int pas_scan_ptr_token(pas_char_next_fn next, pas_char_unget_fn unget, void *src, uint64_t *out)
{
    int ch;
    do
        ch = next(src);
    while (ch != EOF && isspace((unsigned char) ch));
    if (ch == EOF)
        return PAS_PTR_SCAN_EOF;
    char token[32];
    int n = 0, overflow = 0, base = 10, negative = 0, seen = 0;
    if (ch == '+' || ch == '-') {
        negative = ch == '-';
        ch = next(src);
    }
    if (ch == '0') {
        seen = 1;
        ch = next(src);
        base = 8;
        if (ch == 'x' || ch == 'X') {
            ch = next(src);
            base = 16;
        }
    }
    while (ch == '0') {
        seen = 1;
        ch = next(src);
    }
    while (is_base_digit(ch, base)) {
        seen = 1;
        if (n < (int) sizeof(token) - 1)
            token[n++] = (char) ch;
        else
            overflow = 1;
        ch = next(src);
    }
    unget(src, ch);
    if (!seen)
        return PAS_PTR_SCAN_MALFORMED;
    token[n] = '\0';
    errno = 0;
    unsigned long long v = n ? strtoull(token, NULL, base) : 0;
    if (overflow || errno == ERANGE)
        return PAS_PTR_SCAN_RANGE;
    *out = negative ? -(uint64_t) v : (uint64_t) v;
    return PAS_PTR_SCAN_OK;
}

struct fcb_source {
    struct pas_file_fcb *f;
    FILE *h;
};

static int fcb_source_next(void *src)
{
    struct fcb_source *s = src;
    return fcb_next_char(s->f, s->h);
}

static void fcb_source_unget(void *src, int ch)
{
    struct fcb_source *s = src;
    fcb_unget_char(s->f, s->h, ch);
}

/* File counterpart of pas_read_ptr (see readq.c for the format), parsed
 * through the FCB character source like fread_wide_decimal. */
int pas_fread_ptr(struct pas_file_fcb *f, uint64_t *out)
{
    struct fcb_source src = { f, stream_for(f, 0) };
    switch (pas_scan_ptr_token(fcb_source_next, fcb_source_unget, &src, out)) {
    case PAS_PTR_SCAN_EOF:
        die("runtime error: unexpected EOF while reading pointer");
        break;
    case PAS_PTR_SCAN_MALFORMED:
        return io_error(f, 14, "runtime error: malformed pointer input") ? -1 : 0;
    case PAS_PTR_SCAN_RANGE:
        return io_error(f, 14, "runtime error: pointer out of range") ? -1 : 0;
    }
    return 0;
}

int pas_fread_enum_name(struct pas_file_fcb *f, int32_t *out, const char **names, int lo, int hi)
{
    FILE *h = stream_for(f, 0);
    int ch = fcb_skip_ws_except_nl(f, h);
    if (ch == EOF)
        die("runtime error: unexpected EOF while reading enum");
    if (isdigit((unsigned char) ch) || ch == '-' || ch == '+') {
        fcb_unget_char(f, h, ch);
        return pas_fread_enum_ord(f, out, lo, hi);
    }
    if (!isalpha((unsigned char) ch)) {
        fcb_unget_char(f, h, ch);
        if (io_error(f, 14, "runtime error: malformed enum input"))
            return -1;
    }
    char tok[256];
    int n = 0;
    do {
        if (n + 1 < (int) sizeof(tok))
            tok[n++] = (char) toupper((unsigned char) ch);
        ch = fcb_next_char(f, h);
    } while (ch != EOF && (isalpha((unsigned char) ch) || isdigit((unsigned char) ch)));
    fcb_unget_char(f, h, ch);
    tok[n] = '\0';
    for (int i = lo; i <= hi; i++) {
        if (names && names[i] && strcasecmp(tok, names[i]) == 0) {
            *out = i;
            return 0;
        }
    }
    if (io_error(f, 14, "runtime error: malformed enum input"))
        return -1;
    return -1;
}

int pas_fread_real(struct pas_file_fcb *f, double *out)
{
    FILE *h = stream_for(f, 0);
    int ch = fcb_skip_ws_except_nl(f, h);
    if (ch == EOF)
        die("runtime error: unexpected EOF while reading real");
    ungetc(ch, h);
    if (fscanf(h, "%lf", out) != 1) {
        if (io_error(f, 14, "runtime error: malformed real input"))
            return -1;
    }
    return 0;
}

int pas_fread_char(struct pas_file_fcb *f, uint8_t *out)
{
    FILE *h = stream_for(f, 0);
    int ch = fcb_next_char(f, h);
    if (ch == EOF)
        die("runtime error: unexpected EOF while reading char");
    *out = (ch == '\n') ? ' ' : (uint8_t) ch;
    return 0;
}

int pas_fread_lstring(struct pas_file_fcb *f, uint8_t *buf, int cap)
{
    FILE *h = stream_for(f, 0);
    int ch, n = 0;
    while ((ch = fcb_next_char(f, h)) != EOF && ch != '\n') {
        if (n < cap)
            buf[1 + n] = (uint8_t) ch;
        n++;
    }
    if (ch == EOF)
        die("runtime error: unexpected EOF while reading string");
    fcb_unget_char(f, h, ch);   /* line marker stays the current component */
    if (cap < 0)
        cap = 0;
    buf[0] = (uint8_t) (n < cap ? n : cap);
    return 0;
}

int pas_fread_string(struct pas_file_fcb *f, uint8_t *buf, int cap)
{
    /* READ into STRING(n): copy up to cap characters, stopping early at the
     * line marker (which stays the current component, like the LSTRING
     * reader); the remainder of the destination is blank-padded.  Unlike
     * LSTRING, reading stops once the destination is full — the rest of the
     * line is left unconsumed for subsequent READs.  [INFERRED] semantics. */
    FILE *h = stream_for(f, 0);
    int ch, n = 0;
    while (n < cap && (ch = fcb_next_char(f, h)) != EOF && ch != '\n') {
        buf[n++] = (uint8_t) ch;
    }
    if (n < cap) {
        if (ch == EOF)
            die("runtime error: unexpected EOF while reading string");
        fcb_unget_char(f, h, ch);       /* line marker stays the current component */
    }
    while (n < cap)
        buf[n++] = ' ';
    return 0;
}

void pas_freadln_skip(struct pas_file_fcb *f)
{
    FILE *h = stream_for(f, 0);
    int ch;
    while ((ch = fcb_next_char(f, h)) != EOF && ch != '\n') {
    }
}
