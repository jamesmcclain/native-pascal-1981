/* Independent arithmetic/alignment boundary checks, including addresses that
 * must never be dereferenced. Imported metadata does not establish capacity. */
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include "../../../runtime/pascalrt.h"

static void check_case(int which)
{
    _Alignas(16) int32_t data[8];
    void *raw = data;
    int64_t lower = 2, upper = 4, domain_high = 32767;
    uint64_t stride = 4, alignment = 4;
    int32_t lower_unsigned = 0, upper_unsigned = 0;
    switch (which) {
    case 1: lower = 3; break;
    case 2: upper = -1; upper_unsigned = 1; domain_high = INT64_MAX; break;
    case 3: raw = NULL; break;
    case 4: raw = (char *)data + 1; break;
    case 5: upper = 1; break;
    case 6: upper = 40000; break;
    case 7: domain_high = INT64_MAX; upper = INT64_MAX; stride = 8; break;
    case 8: raw = (void *)(uintptr_t)(UINTPTR_MAX - 15); stride = 16; alignment = 16; break;
    case 9: lower = -1; lower_unsigned = 1; break;
    }
    pas_super_import_check(raw, lower, lower_unsigned, upper, upper_unsigned,
                           2, -32768, domain_high, stride, alignment);
}

int main(void)
{
    check_case(0);
    const char *reasons[] = {
        "lower bound does not match declared lower",
        "upper bound is outside declared index domain",
        "requires non-NIL data",
        "data is not correctly aligned",
        "upper bound is outside declared index domain",
        "upper bound is outside declared index domain",
        "byte span or address arithmetic overflows",
        "byte span or address arithmetic overflows",
        "lower bound does not match declared lower"
    };
    for (int which = 1; which <= 9; ++which) {
        int fds[2], status;
        if (pipe(fds)) return 1;
        pid_t pid = fork();
        if (pid < 0) return 1;
        if (!pid) {
            close(fds[0]);
            if (dup2(fds[1], STDERR_FILENO) < 0) _Exit(1);
            close(fds[1]);
            check_case(which);
            _Exit(0);
        }
        close(fds[1]);
        char actual[256] = {0}, expected[256];
        size_t used = 0;
        ssize_t n;
        while ((n = read(fds[0], actual + used, sizeof actual - used - 1)) > 0)
            used += (size_t)n;
        close(fds[0]);
        if (waitpid(pid, &status, 0) != pid) return 1;
        snprintf(expected, sizeof expected, "runtime error: UNSAFESUPER %s\n", reasons[which - 1]);
        if (!WIFSIGNALED(status) || WTERMSIG(status) != SIGABRT || strcmp(actual, expected)) {
            fprintf(stderr, "FAIL: import runtime case %d: %s", which, actual);
            return 1;
        }
    }
    puts("PASS: unsafe import runtime arithmetic/alignment (1 valid, 9 rejected)");
    return 0;
}
