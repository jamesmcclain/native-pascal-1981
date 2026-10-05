#include <assert.h>
#include <stdint.h>
#include "../../runtime/pascalrt.h"

int main(void)
{
    const char s[] = {'a', 'a', 'b', 'a'};
    assert(scaneq(4, 'b', s, 4, 1, 1) == 2);
    assert(scaneq(-4, 'b', s, 4, 4, 1) == -1);
    assert(scanne(4, 'a', s, 4, 1, 0) == 2);
    assert(scanne(-4, 'a', s, 4, 4, 0) == -1);
    /* No match: return the requested count, not the clipped length. */
    assert(scaneq(10, 'z', s, 4, 1, 1) == 10);
    assert(scaneq(-10, 'z', s, 4, 4, 1) == -10);
    assert(scanne(10, 'a', s, 2, 1, 0) == 10);
    assert(scanne(-10, 'a', s, 2, 2, 0) == -10);
    assert(scaneq(10, 'z', s, 4, 5, 1) == 0);
    assert(scaneq(0, 'a', s, 4, 1, 1) == 0);
    assert(scaneq(10, 'a', s, 0, 1, 1) == 0);
    assert(scaneq(10, 'a', s, 4, 0, 1) == 0);
    assert(scaneq(-32768, 'z', s, 4, 4, 1) == -32768);
    return 0;
}
