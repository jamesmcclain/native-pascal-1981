#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>
#include "../../../runtime/pascalrt.h"
static int armed, fail_malloc, calls;
static size_t expected_size;
void *__real_malloc(size_t size);
void *__wrap_malloc(size_t size)
{
    if (armed && (++calls != 1 || size != expected_size)) _Exit(99);
    if (armed && fail_malloc) return NULL;
    return __real_malloc(size);
}
struct failure { int64_t upper, lower, low, high; int uns; uint64_t stride, align; const char *reason; };
int main(void)
{
    const struct failure cases[] = {
        {1, 2, -32768, 32767, 0, 2, 2, "upper bound is below declared lower"},
        {40000, 2, -32768, 32767, 0, 2, 2, "upper bound is outside declared index domain"},
        {-1, 0, 0, INT64_MAX, 1, 1, 1, "upper bound is not representable"},
        {INT64_MAX, INT64_MIN, INT64_MIN, INT64_MAX, 0, 1, 1, "element count overflows"},
        {2, 0, 0, 2, 0, UINT64_MAX, 1, "byte size overflows"},
        {1, 0, 0, 1, 0, INT64_MAX, 1, "byte size overflows"},
        {0, 0, 0, 0, 0, 0, 1, "element size or alignment is unsupported"},
        {0, 0, 0, 0, 0, 1, 32, "element size or alignment is unsupported"},
        {0, 0, 0, 0, 0, 1, 3, "element size or alignment is unsupported"},
        {4, 2, -32768, 32767, 0, 2, 2, "allocation failed"}
    };
    armed = 1; expected_size = 48;
    void *p = pas_super_new(4, 0, 2, -32768, 32767, 16, 16);
    if (!p || (uintptr_t)p % 16 || calls != 1) return 1;
    free(p);
    calls = 0; expected_size = 4;
    p = pas_super_new(INT64_MIN + 1, 0, INT64_MIN, INT64_MIN, INT64_MAX, 2, 2);
    if (!p || calls != 1) return 1;
    free(p);
    for (size_t i = 0; i < sizeof(cases)/sizeof(cases[0]); ++i) {
        int fd[2]; if (pipe(fd)) return 1;
        pid_t child = fork(); if (child < 0) return 1;
        if (!child) {
            close(fd[0]); dup2(fd[1], STDERR_FILENO); close(fd[1]);
            calls = 0; fail_malloc = i == 9; expected_size = fail_malloc ? 6 : 0;
            const struct failure *f = &cases[i];
            pas_super_new(f->upper, f->uns, f->lower, f->low, f->high, f->stride, f->align);
            _Exit(98);
        }
        close(fd[1]); char actual[256] = {0}, expected[256]; size_t used = 0; ssize_t n;
        while ((n = read(fd[0], actual + used, sizeof(actual)-1-used)) > 0) used += (size_t)n;
        close(fd[0]); int status; if (waitpid(child, &status, 0) != child) return 1;
        snprintf(expected, sizeof(expected), "runtime error: NEW SUPER ARRAY %s\n", cases[i].reason);
        if (!WIFSIGNALED(status) || WTERMSIG(status) != SIGABRT || strcmp(actual, expected)) {
            fprintf(stderr, "FAIL: NEW runtime case %zu: %s", i, actual); return 1;
        }
    }
    puts("PASS: NEW runtime (2 valid, 10 rejected before publication)");
    return 0;
}
