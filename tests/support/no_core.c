/* Test-only preload: RLIMIT_CORE=0 does not suppress Linux piped core
 * handlers (e.g. Apport). A constructor runs AFTER exec resets dumpability,
 * including in descendants inheriting LD_PRELOAD. Never link into runtime.
 */
#include <sys/prctl.h>
#include <unistd.h>

__attribute__((constructor)) static void disable_test_core_reports(void)
{
    if (prctl(PR_SET_DUMPABLE, 0) != 0) {
        static const char message[] = "test environment: cannot disable dumpability\n";
        (void) write(STDERR_FILENO, message, sizeof(message) - 1);
        _exit(125);
    }
}
