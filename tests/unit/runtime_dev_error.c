/* Host side of the NVPTX device error channel (runtime/dev_error.c).
 *
 * pas_dev_error_report must return for an empty cell and, for a set cell,
 * print exactly the host check's diagnostic and abort; a cell whose file
 * index names an included file adds " of file NAME" exactly as the host
 * check does, and the file index maps to its module global's name. Each
 * failing case runs in a child process whose stderr is captured through a
 * pipe.
 */
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "../../runtime/pascalrt.h"

static int failures;

static void expect_abort(const char *label, pas_dev_error_cell cell, const char *file, const char *expected)
{
    int fds[2];
    char buf[512];
    size_t len = 0;
    ssize_t got;
    int status;
    pid_t pid;

    fflush(stdout);
    if (pipe(fds) != 0)
        exit(2);
    pid = fork();
    if (pid < 0)
        exit(2);
    if (pid == 0) {
        close(fds[0]);
        dup2(fds[1], 2);
        pas_dev_error_report(&cell, file);
        _exit(0);       /* reached only if the report returned */
    }
    close(fds[1]);
    while (len < sizeof buf - 1 && (got = read(fds[0], buf + len, sizeof buf - 1 - len)) > 0)
        len += (size_t) got;
    buf[len] = '\0';
    close(fds[0]);
    waitpid(pid, &status, 0);
    if (!WIFSIGNALED(status) || WTERMSIG(status) != SIGABRT) {
        printf("FAIL: %s: did not abort\n", label);
        failures++;
    }
    if (strcmp(buf, expected) != 0) {
        printf("FAIL: %s: stderr\n  expected: %s  got:      %s", label, expected, buf);
        failures++;
    }
}

int main(void)
{
    pas_dev_error_cell none = { 0 };
    pas_dev_error_cell trunc_big = { PAS_DEV_ERROR_TRUNC, 7, 16, 0, 1.0e10 };
    pas_dev_error_cell round_half = { PAS_DEV_ERROR_ROUND, 5, 17, 0, 32767.5 };
    pas_dev_error_cell nan_cell = { PAS_DEV_ERROR_ROUND, 3, 4, 0, 0.0 };
    pas_dev_error_cell unknown = { 99, 1, 2, 0, 0.0 };
    pas_dev_error_cell trunc_inc = { PAS_DEV_ERROR_TRUNC, 2, 18, 1, 1.0e10 };
    pas_dev_error_cell round_inc = { PAS_DEV_ERROR_ROUND, 3, 11, 2, -32768.5 };
    pas_dev_error_cell unknown_inc = { 99, 1, 2, 1, 0.0 };
    char symbol[64];

    if (sizeof(pas_dev_error_cell) != 24) {
        printf("FAIL: cell is %zu bytes, codegen emits 24\n", sizeof(pas_dev_error_cell));
        failures++;
    }
    pas_dev_error_report(&none, NULL);  /* must return */
    pas_dev_error_report(&none, "x.inc");
    pas_dev_error_report(NULL, NULL);
    nan_cell.value = __builtin_nan("");
    expect_abort("TRUNC", trunc_big, NULL, "runtime error: TRUNC result out of INTEGER range at line 7 column 16 (value=10000000000)\n");
    expect_abort("ROUND", round_half, NULL, "runtime error: ROUND result out of INTEGER range at line 5 column 17 (value=32767.5)\n");
    expect_abort("NaN", nan_cell, NULL, "runtime error: ROUND result out of INTEGER range at line 3 column 4 (value=NaN)\n");
    expect_abort("unknown", unknown, NULL, "runtime error: device check 99 failed at line 1 column 2\n");
    /* Included-file sites: the same suffix as pas_diag_where on the host. */
    expect_abort("TRUNC file", trunc_inc, "convck_kinc.inc",
                 "runtime error: TRUNC result out of INTEGER range at line 2 column 18 of file convck_kinc.inc (value=10000000000)\n");
    expect_abort("ROUND file", round_inc, "dir/convck_kround.inc",
                 "runtime error: ROUND result out of INTEGER range at line 3 column 11 of file dir/convck_kround.inc (value=-32768.5)\n");
    expect_abort("unknown file", unknown_inc, "x.inc", "runtime error: device check 99 failed at line 1 column 2 of file x.inc\n");
    /* A file index whose global was not found reports without a name; a
     * primary-file cell ignores any name. */
    expect_abort("TRUNC file missing", trunc_inc, NULL,
                 "runtime error: TRUNC result out of INTEGER range at line 2 column 18 (value=10000000000)\n");
    expect_abort("TRUNC primary", trunc_big, "stale.inc",
                 "runtime error: TRUNC result out of INTEGER range at line 7 column 16 (value=10000000000)\n");
    if (!pas_dev_error_file_symbol(1, symbol, sizeof symbol) || strcmp(symbol, "__pas_dev_file_1") != 0) {
        printf("FAIL: file symbol 1\n");
        failures++;
    }
    if (!pas_dev_error_file_symbol(64, symbol, sizeof symbol) || strcmp(symbol, "__pas_dev_file_64") != 0) {
        printf("FAIL: file symbol 64\n");
        failures++;
    }
    if (pas_dev_error_file_symbol(0, symbol, sizeof symbol) || pas_dev_error_file_symbol(-1, symbol, sizeof symbol)
        || pas_dev_error_file_symbol(1, symbol, 4)) {
        printf("FAIL: file symbol for no file or a short buffer\n");
        failures++;
    }
    if (failures)
        return 1;
    printf("PASS: device error cell reports\n");
    return 0;
}
