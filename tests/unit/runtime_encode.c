#include <assert.h>
#include <stdint.h>
#include <string.h>
#include "../../runtime/pascalrt.h"

/* pas_encode_fmt: the ENCODE runtime. An LSTRING is a length byte followed
 * by its characters; the formatter publishes the length only when the text
 * fits the capacity and leaves everything untouched otherwise. */
int main(void)
{
    char buf[12];
    char keep[12];
    static char big[400];

    memset(buf, 'z', sizeof(buf));
    assert(pas_encode_fmt(buf + 1, 10, buf, "%d", -123) == 1);
    assert(buf[0] == 4 && memcmp(buf + 1, "-123", 4) == 0 && buf[5] == 'z');

    /* An exact fit succeeds. */
    assert(pas_encode_fmt(buf + 1, 10, buf, "%*d", 10, 7) == 1);
    assert(buf[0] == 10 && buf[1] == ' ' && buf[10] == '7' && buf[11] == 'z');

    /* One character too many: 0, and the destination is untouched. */
    memcpy(keep, buf, sizeof(buf));
    assert(pas_encode_fmt(buf + 1, 10, buf, "%s", "abcdefghijk") == 0);
    assert(memcmp(keep, buf, sizeof(buf)) == 0);

    /* WRITE's REAL and BOOLEAN formats pass through printf unchanged. */
    assert(pas_encode_fmt(buf + 1, 10, buf, "%*.*f", 8, 2, 3.25) == 1);
    assert(buf[0] == 8 && memcmp(buf + 1, "    3.25", 8) == 0);
    assert(pas_encode_fmt(buf + 1, 10, buf, "%14.7E", 3.25) == 0);
    assert(buf[0] == 8 && memcmp(buf + 1, "    3.25", 8) == 0);
    assert(pas_encode_fmt(buf + 1, 10, buf, "%*s", 6, "TRUE") == 1);
    assert(buf[0] == 6 && memcmp(buf + 1, "  TRUE", 6) == 0);

    /* Empty text is a valid, empty LSTRING. */
    assert(pas_encode_fmt(buf + 1, 10, buf, "%s", "") == 1 && buf[0] == 0);

    /* No capacity, no destination. */
    assert(pas_encode_fmt(buf + 1, 0, buf, "%d", 1) == 0);
    assert(pas_encode_fmt(NULL, 10, buf, "%d", 1) == 0);
    assert(pas_encode_fmt(buf + 1, 10, NULL, "%d", 1) == 0);

    /* A capacity above 255 is clamped to what the length byte can hold. */
    assert(pas_encode_fmt(big + 1, 399, big, "%*d", 255, 1) == 1);
    assert((unsigned char) big[0] == 255 && big[255] == '1');
    assert(pas_encode_fmt(big + 1, 399, big, "%*d", 256, 1) == 0);
    assert((unsigned char) big[0] == 255);
    return 0;
}
