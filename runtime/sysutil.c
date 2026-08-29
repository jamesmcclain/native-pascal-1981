/* POSIX substrate for filesystem and child-process utilities.  This file
 * deliberately knows nothing about a particular test suite or compiler. */
#define _POSIX_C_SOURCE 200809L

#include "pascalrt.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static long long monotonic_ms(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
        return -1;
    return (long long) ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

void *pas_sys_dir_open(const char *path)
{
    return opendir(path);
}

int pas_sys_dir_next(void *handle, char *name, int namecap)
{
    DIR *dir = handle;
    struct dirent *entry;
    struct stat st;

    if (!dir || !name || namecap < 2) {
        errno = EINVAL;
        return -1;
    }
    for (;;) {
        errno = 0;
        entry = readdir(dir);
        if (!entry)
            return errno == 0 ? 0 : -1;
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
            continue;
        if ((int) strlen(entry->d_name) >= namecap) {
            errno = ENAMETOOLONG;
            return -1;
        }
        strcpy(name, entry->d_name);
        if (fstatat(dirfd(dir), entry->d_name, &st, AT_SYMLINK_NOFOLLOW) == 0) {
            if (S_ISDIR(st.st_mode))
                return PAS_SYS_ENTRY_DIR + 1;
            if (S_ISREG(st.st_mode))
                return PAS_SYS_ENTRY_FILE + 1;
        }
        return PAS_SYS_ENTRY_OTHER + 1;
    }
}

int pas_sys_dir_close(void *handle)
{
    if (!handle) {
        errno = EINVAL;
        return -1;
    }
    return closedir(handle);
}

int pas_sys_temp_dir(const char *prefix, char *out, int outcap)
{
    const char *base;
    size_t need;

    if (!prefix || !out || outcap < 16 || strchr(prefix, '/')) {
        errno = EINVAL;
        return -1;
    }
    base = getenv("TMPDIR");
    if (!base || base[0] == '\0')
        base = "/tmp";
    need = strlen(base) + 1 + strlen(prefix) + 6 + 1;
    if (need > (size_t) outcap) {
        errno = ENAMETOOLONG;
        return -1;
    }
    memcpy(out, base, strlen(base));
    out[strlen(base)] = '/';
    memcpy(out + strlen(base) + 1, prefix, strlen(prefix));
    memcpy(out + strlen(base) + 1 + strlen(prefix), "XXXXXX", 7);
    return mkdtemp(out) ? 0 : -1;
}

static int remove_tree_fd(int fd)
{
    DIR *dir;
    struct dirent *entry;
    struct stat st;
    int child;
    int result = 0;

    dir = fdopendir(dup(fd));
    if (!dir)
        return -1;
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
            continue;
        if (fstatat(fd, entry->d_name, &st, AT_SYMLINK_NOFOLLOW) != 0) {
            result = -1;
            break;
        }
        if (S_ISDIR(st.st_mode)) {
            child = openat(fd, entry->d_name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
            if (child < 0 || remove_tree_fd(child) != 0 || unlinkat(fd, entry->d_name, AT_REMOVEDIR) != 0) {
                if (child >= 0)
                    close(child);
                result = -1;
                break;
            }
            close(child);
        } else if (unlinkat(fd, entry->d_name, 0) != 0) {
            result = -1;
            break;
        }
    }
    if (closedir(dir) != 0)
        result = -1;
    return result;
}

int pas_sys_remove_tree(const char *path)
{
    int fd;
    int result;

    fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
    if (fd < 0)
        return -1;
    result = remove_tree_fd(fd);
    close(fd);
    if (result != 0)
        return -1;
    return rmdir(path);
}

static void append_diagnostics(int fd, char *out, int outcap, int *used)
{
    char chunk[1024];
    ssize_t got;
    int room;

    for (;;) {
        got = read(fd, chunk, sizeof(chunk));
        if (got <= 0)
            return;
        room = outcap - 1 - *used;
        if (room > 0) {
            if (got > room)
                got = room;
            memcpy(out + *used, chunk, (size_t) got);
            *used += (int) got;
            out[*used] = '\0';
        }
    }
}

int pas_sys_exec(const char *executable, const char *packed_args,
                 int packed_args_len, int timeout_ms, int *exit_code, int *term_signal, char *diagnostics, int diagnostics_cap, int *diagnostics_len)
{
    const char **argv;
    int argc = 1;
    int i;
    int output_pipe[2] = { -1, -1 };
    int exec_pipe[2] = { -1, -1 };
    pid_t child;
    int status = 0;
    int exec_errno = 0;
    int done = 0;
    int timed_out = 0;
    int used = 0;
    long long deadline;

    if (!executable || !packed_args || packed_args_len < 0 || timeout_ms < 0 || !exit_code || !term_signal || !diagnostics || diagnostics_cap < 1 || !diagnostics_len) {
        errno = EINVAL;
        return PAS_SYS_ERROR;
    }
    for (i = 0; i < packed_args_len; i++)
        if (packed_args[i] == '\0')
            argc++;
    argv = calloc((size_t) argc + 1, sizeof(*argv));
    if (!argv)
        return PAS_SYS_ERROR;
    argv[0] = executable;
    argc = 1;
    for (i = 0; i < packed_args_len;) {
        argv[argc++] = packed_args + i;
        while (i < packed_args_len && packed_args[i] != '\0')
            i++;
        if (i == packed_args_len) {
            free(argv);
            errno = EINVAL;
            return PAS_SYS_ERROR;
        }
        i++;
    }
    diagnostics[0] = '\0';
    *diagnostics_len = 0;
    *exit_code = -1;
    *term_signal = 0;
    if (pipe(output_pipe) != 0 || pipe(exec_pipe) != 0) {
        if (output_pipe[0] >= 0)
            close(output_pipe[0]);
        if (output_pipe[1] >= 0)
            close(output_pipe[1]);
        if (exec_pipe[0] >= 0)
            close(exec_pipe[0]);
        if (exec_pipe[1] >= 0)
            close(exec_pipe[1]);
        free(argv);
        return PAS_SYS_ERROR;
    }
    fcntl(exec_pipe[1], F_SETFD, FD_CLOEXEC);
    child = fork();
    if (child < 0) {
        close(output_pipe[0]);
        close(output_pipe[1]);
        close(exec_pipe[0]);
        close(exec_pipe[1]);
        free(argv);
        return PAS_SYS_ERROR;
    }
    if (child == 0) {
        close(output_pipe[0]);
        close(exec_pipe[0]);
        dup2(output_pipe[1], STDOUT_FILENO);
        dup2(output_pipe[1], STDERR_FILENO);
        close(output_pipe[1]);
        execvp(executable, (char *const *) argv);
        exec_errno = errno;
        {
            ssize_t ignored = write(exec_pipe[1], &exec_errno, sizeof(exec_errno));
            (void) ignored;
        }
        _exit(127);
    }
    close(output_pipe[1]);
    close(exec_pipe[1]);
    fcntl(output_pipe[0], F_SETFL, fcntl(output_pipe[0], F_GETFL) | O_NONBLOCK);
    deadline = monotonic_ms() + timeout_ms;
    while (!done) {
        append_diagnostics(output_pipe[0], diagnostics, diagnostics_cap, &used);
        if (waitpid(child, &status, WNOHANG) == child) {
            done = 1;
            break;
        }
        if (monotonic_ms() >= deadline) {
            timed_out = 1;
            kill(child, SIGTERM);
            (void) poll(NULL, 0, 200);
            if (waitpid(child, &status, WNOHANG) == 0)
                kill(child, SIGKILL);
            while (waitpid(child, &status, 0) < 0 && errno == EINTR) {
            }
            done = 1;
            break;
        }
        (void) poll(NULL, 0, 10);
    }
    fcntl(output_pipe[0], F_SETFL, fcntl(output_pipe[0], F_GETFL) & ~O_NONBLOCK);
    append_diagnostics(output_pipe[0], diagnostics, diagnostics_cap, &used);
    close(output_pipe[0]);
    {
        ssize_t ignored = read(exec_pipe[0], &exec_errno, sizeof(exec_errno));
        (void) ignored;
    }
    close(exec_pipe[0]);
    *diagnostics_len = used;
    if (exec_errno != 0) {
        free(argv);
        errno = exec_errno;
        return PAS_SYS_ERROR;
    }
    free(argv);
    if (timed_out)
        return PAS_SYS_TIMEOUT;
    if (WIFEXITED(status)) {
        *exit_code = WEXITSTATUS(status);
        return PAS_SYS_OK;
    }
    if (WIFSIGNALED(status)) {
        *term_signal = WTERMSIG(status);
        return PAS_SYS_SIGNAL;
    }
    errno = ECHILD;
    return PAS_SYS_ERROR;
}
