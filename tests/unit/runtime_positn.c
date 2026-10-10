#include <assert.h>
#include <limits.h>
#include <stdint.h>
#include "../../runtime/pascalrt.h"

/* These arrays deliberately have no terminator: explicit lengths own access. */
int main(void)
{
    const char s[] = {'a', 'b', 'a', 'b', 'a', 'b'};
    const char p[] = {'a', 'b'};
    assert(positn_from(s, 6, p, 2, 1) == 1);
    assert(positn_from(s, 6, p, 2, 2) == 3);
    assert(positn_from(s, 6, p, 2, 4) == 5);
    assert(positn_from(s, 6, p, 2, 5) == 5);
    assert(positn_from(s, 6, p, 2, 6) == 0);
    assert(positn_from(s, 6, p, 2, 7) == 0);
    assert(positn_from(s, 6, p, 2, 0) == 0);
    assert(positn_from(s, 6, p, 2, -1) == 0);
    assert(positn_from(s, 6, p, 2, INT32_MIN) == 0);
    assert(positn_from(s, 6, p, 2, INT32_MAX) == 0);
    assert(positn_from(s, 6, "zz", 2, 1) == 0);
    assert(positn_from(s, 6, "abababa", 7, 1) == 0);
    assert(positn_from(s, 0, p, 2, 1) == 0);
    assert(positn_from(s, 6, p, 0, 1) == 1);
    assert(positn_from(s, 6, p, 0, INT32_MIN) == 1);
    assert(positn_from(s, 6, p, 0, INT32_MAX) == 1);
    assert(positn_from(s, 0, p, 0, 1) == 1);
    assert(positn_from(s, -1, p, 2, 1) == 0);
    assert(positn_from(s, 6, p, -1, 1) == 0);
    assert(positn_from(NULL, 6, p, 2, 1) == 0);
    assert(positn_from(s, 6, NULL, 2, 1) == 0);
    assert(positn(s, 6, p, 2) == 1);
    assert(positn(s, 6, p, 0) == 1);

    const char bytes[] = {'\0', (char)0xff, '\0', (char)0xff};
    const char binary[] = {'\0', (char)0xff};
    assert(positn_from(bytes, 4, binary, 2, 1) == 1);
    assert(positn_from(bytes, 4, binary, 2, 2) == 3);
    assert(positn_from(bytes, 4, binary, 2, 4) == 0);

    /* Every short binary source/pattern and nearby starting position,
     * against an independent exhaustive byte comparison. */
    for (int len = 0; len <= 6; ++len) {
        for (unsigned bits = 0; bits < (1u << len); ++bits) {
            char hay[6];
            for (int i = 0; i < len; ++i) hay[i] = 'a' + ((bits >> i) & 1u);
            for (int plen = 0; plen <= 3; ++plen) {
                for (unsigned pb = 0; pb < (1u << plen); ++pb) {
                    char needle[3];
                    for (int i = 0; i < plen; ++i) needle[i] = 'a' + ((pb >> i) & 1u);
                    for (int start = -2; start <= len + 2; ++start) {
                        int expected = plen == 0 ? 1 : 0;
                        if (plen && start >= 1 && start <= len) {
                            for (int pos = start; pos + plen - 1 <= len; ++pos) {
                                int same = 1;
                                for (int j = 0; j < plen; ++j)
                                    if (hay[pos - 1 + j] != needle[j]) same = 0;
                                if (same) { expected = pos; break; }
                            }
                        }
                        assert(positn_from(hay, len, needle, plen, start) == expected);
                        if (start == 1) assert(positn(hay, len, needle, plen) == expected);
                    }
                }
            }
        }
    }
    return 0;
}
