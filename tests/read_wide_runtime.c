/* Direct FCB test: Pascal does not currently expose F.TRAP as a selector. */
#include <stdint.h>
#include <stdio.h>
#include "../runtime/pascalrt.h"

static int check(const char *text, int wide64)
{
    FILE *h = tmpfile();
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
    int32_t n32 = 123;
    int64_t n64 = 456;
    int rc = wide64 ? pas_fread_int64(&f, &n64) : pas_fread_int32(&f, &n32);
    int failed = rc != -1 || f.errs != 14 || n32 != 123 || n64 != 456;
    fclose(h);
    return failed;
}

/* Leading newlines and zeros are not malformed input. */
static int check_ok(const char *text, int64_t expected)
{
    FILE *h = tmpfile();
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
    int64_t n64 = 0;
    int rc = pas_fread_int64(&f, &n64);
    fclose(h);
    return rc != 0 || f.errs != 0 || n64 != expected;
}

int main(void)
{
    if (check("no number\n", 0) || check("2147483648\n", 0) ||
        check("-9223372036854775809\n", 1) || check("+\n", 1) ||
        check("\n\nx\n", 1) ||
        check_ok("\n \n 17\n", 17) ||
        check_ok("-0000000000000000000000000000000000000042\n", -42) ||
        check_ok("000000000000000000000000000000000000000\n", 0)) {
        fputs("wide file trap regression\n", stderr);
        return 1;
    }
    puts("PASS: wide file malformed/overflow trap code 14, destination unchanged");
    return 0;
}
