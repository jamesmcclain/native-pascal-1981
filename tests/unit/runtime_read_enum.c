/* Direct FCB test: verify pas_fread_enum_name and pas_fread_ptr leave destinations
 * untouched on trapped I/O failure (f.trap = 1), and that every numeric
 * reader leaves F^ on the character that stopped the token. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "../../runtime/pascalrt.h"

static int check_enum_trap(const char *text, const char **names, int lo, int hi, int32_t sentinel)
{
    FILE *h = pas_project_tmpfile();
    if (!h) return 1;
    fputs(text, h);
    rewind(h);
    unsigned char component = 0;
    struct pas_file_fcb f = {0};
    f.elem_size = 1;
    f.structure = STRUCT_TEXT;
    f.mode = MODE_READ | MODE_PENDING;
    f.buffer = &component;
    f.handle = h;
    f.trap = 1;
    int32_t val = sentinel;
    int rc = pas_fread_enum_name(&f, &val, names, lo, hi);
    int failed = (rc != -1 || f.errs != 14 || val != sentinel);
    fclose(h);
    return failed;
}

static int check_enum_ok(const char *text, const char **names, int lo, int hi, int32_t expected)
{
    FILE *h = pas_project_tmpfile();
    if (!h) return 1;
    fputs(text, h);
    rewind(h);
    unsigned char component = 0;
    struct pas_file_fcb f = {0};
    f.elem_size = 1;
    f.structure = STRUCT_TEXT;
    f.mode = MODE_READ | MODE_PENDING;
    f.buffer = &component;
    f.handle = h;
    f.trap = 1;
    int32_t val = -999;
    int rc = pas_fread_enum_name(&f, &val, names, lo, hi);
    int failed = (rc != 0 || f.errs != 0 || val != expected);
    fclose(h);
    return failed;
}

static int check_ptr_trap(const char *text, uint64_t sentinel)
{
    FILE *h = pas_project_tmpfile();
    if (!h) return 1;
    fputs(text, h);
    rewind(h);
    unsigned char component = 0;
    struct pas_file_fcb f = {0};
    f.elem_size = 1;
    f.structure = STRUCT_TEXT;
    f.mode = MODE_READ | MODE_PENDING;
    f.buffer = &component;
    f.handle = h;
    f.trap = 1;
    uint64_t val = sentinel;
    int rc = pas_fread_ptr(&f, &val);
    int failed = (rc != -1 || f.errs != 14 || val != sentinel);
    fclose(h);
    return failed;
}

static FILE *open_text(struct pas_file_fcb *f, unsigned char *component, const char *text)
{
    FILE *h = pas_project_tmpfile();
    if (!h) return NULL;
    fputs(text, h);
    rewind(h);
    memset(f, 0, sizeof(*f));
    f->elem_size = 1;
    f->structure = STRUCT_TEXT;
    f->mode = MODE_READ | MODE_PENDING;
    f->buffer = component;
    f->handle = h;
    f->trap = 1;
    return h;
}

/* After a trapped failure on text, F^ is the character after the sign. */
static int check_resync(const char *which, const char *text, char expect)
{
    unsigned char component = 0;
    struct pas_file_fcb f;
    FILE *h = open_text(&f, &component, text);
    if (!h) return 1;
    int32_t i32 = 7;
    uint64_t u64 = 7;
    const char *names[] = {"A", "B"};
    int rc;
    if (strcmp(which, "ord") == 0)
        rc = pas_fread_enum_ord(&f, &i32, 0, 1);
    else if (strcmp(which, "ptr") == 0)
        rc = pas_fread_ptr(&f, &u64);
    else
        rc = pas_fread_enum_name(&f, &i32, names, 0, 1);
    const char *buf = pas_file_buffer(&f);
    int failed = (rc != -1 || f.errs != 14 || i32 != 7 || u64 != 7 || !buf || *buf != expect);
    fclose(h);
    if (failed)
        fprintf(stderr, "%s: F^ not resynchronized after trapped '%s'\n", which, text);
    return failed;
}

static int check_ptr_ok(const char *text, uint64_t expected, char next)
{
    unsigned char component = 0;
    struct pas_file_fcb f;
    FILE *h = open_text(&f, &component, text);
    if (!h) return 1;
    uint64_t val = 0;
    int rc = pas_fread_ptr(&f, &val);
    const char *buf = pas_file_buffer(&f);
    int failed = (rc != 0 || val != expected || !buf || *buf != next);
    fclose(h);
    if (failed)
        fprintf(stderr, "ptr: reading '%s' failed\n", text);
    return failed;
}

int main(void)
{
    const char *colors[] = {"RED", "GREEN", "BLUE"};
    const char *bools[] = {"FALSE", "TRUE"};

    /* Valid enum name and numeric reading */
    if (check_enum_ok("RED\n", colors, 0, 2, 0) ||
        check_enum_ok("GREEN\n", colors, 0, 2, 1) ||
        check_enum_ok("BLUE\n", colors, 0, 2, 2) ||
        check_enum_ok("2\n", colors, 0, 2, 2)) {
        fputs("enum ok reading failed\n", stderr);
        return 1;
    }

    /* Valid boolean name and numeric reading */
    if (check_enum_ok("FALSE\n", bools, 0, 1, 0) ||
        check_enum_ok("TRUE\n", bools, 0, 1, 1) ||
        check_enum_ok("0\n", bools, 0, 1, 0) ||
        check_enum_ok("1\n", bools, 0, 1, 1)) {
        fputs("boolean ok reading failed\n", stderr);
        return 1;
    }

    /* Trapped enum failures must leave destination untouched */
    if (check_enum_trap("YELLOW\n", colors, 0, 2, 42) ||
        check_enum_trap("???\n", colors, 0, 2, 42) ||
        check_enum_trap("+\n", colors, 0, 2, 42) ||
        check_enum_trap("--\n", colors, 0, 2, 42) ||
        check_enum_trap("3\n", colors, 0, 2, 42) ||
        check_enum_trap("-1\n", colors, 0, 2, 42) ||
        check_enum_trap("4294967297\n", colors, 0, 2, 42)) {
        fputs("enum trap destination preservation failed\n", stderr);
        return 1;
    }

    /* Names match case-insensitively, as identifiers do: a program that
     * declares its members in lower case still reads them by name. */
    {
        const char *lower[] = {"red", "Green", "blue"};
        if (check_enum_ok("RED\n", lower, 0, 2, 0) ||
            check_enum_ok("green\n", lower, 0, 2, 1) ||
            check_enum_ok("Blue\n", lower, 0, 2, 2)) {
            fputs("case-insensitive enum name reading failed\n", stderr);
            return 1;
        }
    }

    /* An enum subrange (GREEN..BLUE) keeps its lower bound by name and by
     * number; the names table still spans the host type. */
    if (check_enum_ok("GREEN\n", colors, 1, 2, 1) ||
        check_enum_ok("2\n", colors, 1, 2, 2) ||
        check_enum_trap("RED\n", colors, 1, 2, 42) ||
        check_enum_trap("0\n", colors, 1, 2, 42) ||
        check_enum_trap("3\n", colors, 1, 2, 42)) {
        fputs("enum subrange reading failed\n", stderr);
        return 1;
    }

    /* Trapped boolean failures must leave destination untouched */
    if (check_enum_trap("MAYBE\n", bools, 0, 1, 99) ||
        check_enum_trap("!invalid\n", bools, 0, 1, 99) ||
        check_enum_trap("+\n", bools, 0, 1, 99) ||
        check_enum_trap("2\n", bools, 0, 1, 99) ||
        check_enum_trap("3\n", bools, 0, 1, 99) ||
        check_enum_trap("-1\n", bools, 0, 1, 99)) {
        fputs("boolean trap destination preservation failed\n", stderr);
        return 1;
    }

    /* Trapped pointer failure must leave destination untouched */
    if (check_ptr_trap("not_a_ptr\n", 0xDEADBEEF00ULL) ||
        check_ptr_trap("??\n", 0xCAFEBABE11ULL) ||
        check_ptr_trap("18446744073709551616\n", 0xCAFEBABE11ULL) ||
        check_ptr_trap("0x10000000000000000\n", 0xCAFEBABE11ULL) ||
        check_ptr_trap("1234567890123456789012345678901234567890\n", 0xCAFEBABE11ULL)) {
        fputs("pointer trap destination preservation failed\n", stderr);
        return 1;
    }

    /* Vintage enum ordinals are range-checked like the numeric names */
    {
        unsigned char component = 0;
        struct pas_file_fcb f;
        int failed = 0;
        const char *texts[] = {"2\n", "3\n", "-1\n", "4294967297\n"};
        for (int i = 0; i < 4; i++) {
            FILE *h = open_text(&f, &component, texts[i]);
            if (!h) return 1;
            int32_t val = 5;
            int rc = pas_fread_enum_ord(&f, &val, 0, 2);
            failed |= i == 0 ? (rc != 0 || val != 2) : (rc != -1 || f.errs != 14 || val != 5);
            fclose(h);
        }
        /* A subrange 1..2 rejects 0 as well as 3. */
        const char *sub_texts[] = {"1\n", "0\n", "3\n"};
        for (int i = 0; i < 3; i++) {
            FILE *h = open_text(&f, &component, sub_texts[i]);
            if (!h) return 1;
            int32_t val = 5;
            int rc = pas_fread_enum_ord(&f, &val, 1, 2);
            failed |= i == 0 ? (rc != 0 || val != 1) : (rc != -1 || f.errs != 14 || val != 5);
            fclose(h);
        }
        if (failed) {
            fputs("enum ordinal range check failed\n", stderr);
            return 1;
        }
    }

    /* Every numeric reader parses through F^, never around it */
    if (check_resync("ord", "+x\n", 'x') ||
        check_resync("ptr", "+x\n", 'x') ||
        check_resync("enum", "+x\n", 'x') ||
        check_resync("ptr", "-;\n", ';')) {
        fputs("trapped numeric read left F^ out of step\n", stderr);
        return 1;
    }
    if (check_ptr_ok("  1234;", 1234, ';') ||
        check_ptr_ok("\n0x1F,", 31, ',') ||
        check_ptr_ok("017 ", 15, ' ') ||
        check_ptr_ok("12ab", 12, 'a') ||
        /* Leading zeros carry no magnitude, however many there are. */
        check_ptr_ok("0000000000000000000000000000000012345 ", 012345, ' ') ||
        check_ptr_ok("0x00000000000000000000000000000000ff;", 0xff, ';') ||
        check_ptr_ok("0 ", 0, ' ') ||
        check_ptr_ok("0x;", 0, ';') ||
        /* The magnitude is unsigned: high-half pointers round-trip. */
        check_ptr_ok("0xffff800000000000 ", 0xffff800000000000ULL, ' ') ||
        check_ptr_ok("18446744073709551615 ", UINT64_MAX, ' ') ||
        check_ptr_ok("-1 ", UINT64_MAX, ' ')) {
        fputs("pointer reading failed\n", stderr);
        return 1;
    }

    puts("PASS: enum, boolean, and pointer trapped file reads preserve destination");
    return 0;
}
