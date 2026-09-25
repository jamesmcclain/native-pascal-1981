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

int main(void)
{
    if (check("no number\n", 0) || check("2147483648\n", 0) ||
        check("-9223372036854775809\n", 1) || check("+\n", 1)) {
        fputs("wide file trap regression\n", stderr);
        return 1;
    }
    puts("PASS: wide file malformed/overflow trap code 14, destination unchanged");
    return 0;
}
