#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <libgen.h>
#include <limits.h>

#define MAX_EXTRA_ARGS 256

static void print_usage(const char *progname)
{
    fprintf(stderr,
            "Usage: %s [options] <source.pas>\n\n"
            "Options:\n"
            "  -o <file>               Place output into <file>\n"
            "  -c                      Compile to object file only (.o)\n"
            "  -S                      Compile to LLVM IR (.ll) only\n"
            "  -O0, -O1, -O2, -O3      Optimization level (default: -O1)\n"
            "  -I <dir>                Add directory to include search path\n"
            "  -L <dir>                Add directory to library search path\n"
            "  -l <lib>                Link with library\n"
            "  --emit-ptx              Emit PTX assembly instead of LLVM IR\n"
            "  --device-triple <trig>  Set device target triple (e.g. nvptx64-nvidia-cuda)\n"
            "  --ptx-cpu <cpu>         Set PTX target GPU architecture (e.g. sm_70)\n"
            "  --device-backend <bnd>  Set device launch backend (cpu or cuda)\n"
            "  --dialect <dialect>     Accepted dialect (default: extended)\n"
            "  -v, --verbose           Print verbose pipeline and compilation commands\n"
            "  -h, --help              Display this help message\n" "  -V, --version           Display version information\n", progname);
}

static void print_version(void)
{
    printf("pascal1981-native (Native Pascal Compiler Driver) 0.1.0\n");
}

static char *get_base_dir(const char *argv0)
{
    char exe_path[PATH_MAX];
    ssize_t len = readlink("/proc/self/exe", exe_path, sizeof(exe_path) - 1);
    if (len > 0) {
        exe_path[len] = '\0';
        char *dir = dirname(exe_path);
        // If inside bin/, root is parent of bin/
        if (strcmp(basename(dir), "bin") == 0) {
            char root_buf[PATH_MAX];
            snprintf(root_buf, sizeof(root_buf), "%s/..", dir);
            return realpath(root_buf, NULL);
        }
        return strdup(dir);
    }
    // Fallback to dirname of argv0
    char *dup = strdup(argv0);
    char *dir = dirname(dup);
    char *res = realpath(dir, NULL);
    free(dup);
    return res ? res : strdup(".");
}

static char *resolve_path(const char *env_var, const char *root_dir, const char *rel_path)
{
    const char *env_val = getenv(env_var);
    if (env_val && env_val[0] != '\0') {
        return strdup(env_val);
    }
    char buf[PATH_MAX];
    snprintf(buf, sizeof(buf), "%s/%s", root_dir, rel_path);
    return strdup(buf);
}

int main(int argc, char **argv)
{
    const char *input_file = NULL;
    const char *output_file = NULL;
    int compile_only = 0;
    int asm_only = 0;
    int verbose = 0;
    const char *opt_level = "-O1";
    const char *dialect = "extended";
    const char *emit_ptx = NULL;
    const char *device_triple = NULL;
    const char *ptx_cpu = NULL;
    const char *device_backend = NULL;

    const char *extra_clang_args[MAX_EXTRA_ARGS];
    int extra_clang_argc = 0;

    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "-o") == 0) {
            if (++i >= argc) {
                fprintf(stderr, "error: -o requires an argument\n");
                return 1;
            }
            output_file = argv[i];
        } else if (strcmp(argv[i], "-c") == 0) {
            compile_only = 1;
        } else if (strcmp(argv[i], "-S") == 0) {
            asm_only = 1;
        } else if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--verbose") == 0) {
            verbose = 1;
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else if (strcmp(argv[i], "-V") == 0 || strcmp(argv[i], "--version") == 0) {
            print_version();
            return 0;
        } else if (strncmp(argv[i], "-O", 2) == 0) {
            opt_level = argv[i];
        } else if (strcmp(argv[i], "--dialect") == 0) {
            if (++i >= argc) {
                fprintf(stderr, "error: --dialect requires an argument\n");
                return 1;
            }
            dialect = argv[i];
        } else if (strcmp(argv[i], "--emit-ptx") == 0) {
            emit_ptx = "1";
        } else if (strcmp(argv[i], "--device-triple") == 0) {
            if (++i >= argc) {
                fprintf(stderr, "error: --device-triple requires an argument\n");
                return 1;
            }
            device_triple = argv[i];
        } else if (strcmp(argv[i], "--ptx-cpu") == 0) {
            if (++i >= argc) {
                fprintf(stderr, "error: --ptx-cpu requires an argument\n");
                return 1;
            }
            ptx_cpu = argv[i];
        } else if (strcmp(argv[i], "--device-backend") == 0) {
            if (++i >= argc) {
                fprintf(stderr, "error: --device-backend requires an argument\n");
                return 1;
            }
            device_backend = argv[i];
        } else if (strncmp(argv[i], "-I", 2) == 0 || strncmp(argv[i], "-L", 2) == 0 || strncmp(argv[i], "-l", 2) == 0) {
            if (extra_clang_argc < MAX_EXTRA_ARGS - 1) {
                extra_clang_args[extra_clang_argc++] = argv[i];
            }
        } else if (argv[i][0] == '-') {
            fprintf(stderr, "error: unrecognized command line option: %s\n", argv[i]);
            print_usage(argv[0]);
            return 1;
        } else {
            if (input_file != NULL) {
                fprintf(stderr, "error: multiple input files are not supported: '%s' and '%s'\n", input_file, argv[i]);
                return 1;
            }
            input_file = argv[i];
        }
    }

    if (!input_file) {
        fprintf(stderr, "error: no input file specified\n");
        print_usage(argv[0]);
        return 1;
    }

    (void) dialect;             // Dialect defaults to extended for native toolchain

    // Determine output file if not explicitly set
    char default_out[PATH_MAX + 16];
    if (!output_file) {
        char base[PATH_MAX];
        strncpy(base, input_file, sizeof(base) - 8);
        base[sizeof(base) - 8] = '\0';
        char *dot = strrchr(base, '.');
        if (dot && strcmp(dot, ".pas") == 0) {
            *dot = '\0';
        }
        if (asm_only) {
            snprintf(default_out, sizeof(default_out), "%s.ll", base);
        } else if (compile_only) {
            snprintf(default_out, sizeof(default_out), "%s.o", base);
        } else {
            snprintf(default_out, sizeof(default_out), "%s", base);
        }
        output_file = default_out;
    }

    char *root_dir = get_base_dir(argv[0]);
    char *lexer_bin = resolve_path("PASCAL1981_LEXER", root_dir, "bin/lexer");
    char *parser_bin = resolve_path("PASCAL1981_PARSER", root_dir, "bin/parser");
    char *typechecker_bin = resolve_path("PASCAL1981_TYPECHECKER", root_dir, "bin/typechecker");
    char *codegen_bin = resolve_path("PASCAL1981_CODEGEN", root_dir, "bin/codegen");
    char *runtime_lib = resolve_path("PASCAL1981_RUNTIME_LIB", root_dir, "runtime/build/libpascalrt.a");

    // Check that stage binaries exist
    if (access(lexer_bin, X_OK) != 0 || access(parser_bin, X_OK) != 0 || access(typechecker_bin, X_OK) != 0 || access(codegen_bin, X_OK) != 0) {
        fprintf(stderr, "error: compiler stage binaries not found in bin/. Please run 'make bootstrap' first.\n");
        free(root_dir);
        free(lexer_bin);
        free(parser_bin);
        free(typechecker_bin);
        free(codegen_bin);
        free(runtime_lib);
        return 1;
    }
    // Set environment overrides for codegen if requested
    if (emit_ptx)
        setenv("PASCAL_EMIT_PTX", emit_ptx, 1);
    if (device_triple)
        setenv("PASCAL_DEVICE_TRIPLE", device_triple, 1);
    if (ptx_cpu)
        setenv("PASCAL_PTX_CPU", ptx_cpu, 1);
    if (device_backend)
        setenv("PASCAL_DEVICE_BACKEND", device_backend, 1);

    // Open input file
    int in_fd = open(input_file, O_RDONLY);
    if (in_fd < 0) {
        perror("error opening input file");
        return 1;
    }
    // Determine target for codegen output
    char temp_ll[PATH_MAX] = "";
    int out_fd = -1;
    if (asm_only) {
        out_fd = open(output_file, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (out_fd < 0) {
            perror("error opening output file for IR");
            close(in_fd);
            return 1;
        }
    } else {
        snprintf(temp_ll, sizeof(temp_ll), "/tmp/pascal1981_XXXXXX.ll");
        out_fd = mkstemps(temp_ll, 3);
        if (out_fd < 0) {
            perror("error creating temporary IR file");
            close(in_fd);
            return 1;
        }
    }

    if (verbose) {
        fprintf(stderr, "[pipeline] %s < %s | %s | %s | %s > %s\n", lexer_bin, input_file, parser_bin, typechecker_bin, codegen_bin, asm_only ? output_file : temp_ll);
    }

    int p1[2], p2[2], p3[2];
    if (pipe(p1) < 0 || pipe(p2) < 0 || pipe(p3) < 0) {
        perror("pipe creation failed");
        return 1;
    }

    pid_t pid1 = fork();
    if (pid1 == 0) {
        dup2(in_fd, STDIN_FILENO);
        dup2(p1[1], STDOUT_FILENO);
        close(in_fd);
        close(p1[0]);
        close(p1[1]);
        close(p2[0]);
        close(p2[1]);
        close(p3[0]);
        close(p3[1]);
        close(out_fd);
        execl(lexer_bin, "lexer", (char *) NULL);
        perror("exec lexer failed");
        _exit(127);
    }

    pid_t pid2 = fork();
    if (pid2 == 0) {
        dup2(p1[0], STDIN_FILENO);
        dup2(p2[1], STDOUT_FILENO);
        close(in_fd);
        close(p1[0]);
        close(p1[1]);
        close(p2[0]);
        close(p2[1]);
        close(p3[0]);
        close(p3[1]);
        close(out_fd);
        execl(parser_bin, "parser", (char *) NULL);
        perror("exec parser failed");
        _exit(127);
    }

    pid_t pid3 = fork();
    if (pid3 == 0) {
        dup2(p2[0], STDIN_FILENO);
        dup2(p3[1], STDOUT_FILENO);
        close(in_fd);
        close(p1[0]);
        close(p1[1]);
        close(p2[0]);
        close(p2[1]);
        close(p3[0]);
        close(p3[1]);
        close(out_fd);
        execl(typechecker_bin, "typechecker", (char *) NULL);
        perror("exec typechecker failed");
        _exit(127);
    }

    pid_t pid4 = fork();
    if (pid4 == 0) {
        dup2(p3[0], STDIN_FILENO);
        dup2(out_fd, STDOUT_FILENO);
        close(in_fd);
        close(p1[0]);
        close(p1[1]);
        close(p2[0]);
        close(p2[1]);
        close(p3[0]);
        close(p3[1]);
        close(out_fd);
        execl(codegen_bin, "codegen", (char *) NULL);
        perror("exec codegen failed");
        _exit(127);
    }

    close(in_fd);
    close(p1[0]);
    close(p1[1]);
    close(p2[0]);
    close(p2[1]);
    close(p3[0]);
    close(p3[1]);
    close(out_fd);

    int status1 = 0, status2 = 0, status3 = 0, status4 = 0;
    waitpid(pid1, &status1, 0);
    waitpid(pid2, &status2, 0);
    waitpid(pid3, &status3, 0);
    waitpid(pid4, &status4, 0);

    int fail_code = 0;
    if (WIFEXITED(status1) && WEXITSTATUS(status1) != 0)
        fail_code = WEXITSTATUS(status1);
    else if (WIFEXITED(status2) && WEXITSTATUS(status2) != 0)
        fail_code = WEXITSTATUS(status2);
    else if (WIFEXITED(status3) && WEXITSTATUS(status3) != 0)
        fail_code = WEXITSTATUS(status3);
    else if (WIFEXITED(status4) && WEXITSTATUS(status4) != 0)
        fail_code = WEXITSTATUS(status4);
    else if (WIFSIGNALED(status1) || WIFSIGNALED(status2) || WIFSIGNALED(status3) || WIFSIGNALED(status4))
        fail_code = 1;

    if (fail_code != 0) {
        if (temp_ll[0] != '\0')
            unlink(temp_ll);
        free(root_dir);
        free(lexer_bin);
        free(parser_bin);
        free(typechecker_bin);
        free(codegen_bin);
        free(runtime_lib);
        return fail_code;
    }
    // If -S was requested, we are done
    if (asm_only) {
        if (verbose)
            fprintf(stderr, "[driver] Emitted IR to: %s\n", output_file);
        free(root_dir);
        free(lexer_bin);
        free(parser_bin);
        free(typechecker_bin);
        free(codegen_bin);
        free(runtime_lib);
        return 0;
    }
    // Run Clang for assembling / linking
    char cmd[16384];
    size_t offset = 0;
    if (compile_only) {
        offset += snprintf(cmd + offset, sizeof(cmd) - offset, "clang %s -c \"%s\" -o \"%s\"", opt_level, temp_ll, output_file);
    } else {
        offset += snprintf(cmd + offset, sizeof(cmd) - offset, "clang %s \"%s\" \"%s\" -lcjson", opt_level, temp_ll, runtime_lib);
        for (int i = 0; i < extra_clang_argc; ++i) {
            offset += snprintf(cmd + offset, sizeof(cmd) - offset, " %s", extra_clang_args[i]);
        }
        offset += snprintf(cmd + offset, sizeof(cmd) - offset, " -o \"%s\"", output_file);
    }

    if (verbose) {
        fprintf(stderr, "[clang] %s\n", cmd);
    }

    int clang_res = system(cmd);
    if (temp_ll[0] != '\0') {
        unlink(temp_ll);
    }

    free(root_dir);
    free(lexer_bin);
    free(parser_bin);
    free(typechecker_bin);
    free(codegen_bin);
    free(runtime_lib);

    if (clang_res != 0) {
        return WEXITSTATUS(clang_res) ? WEXITSTATUS(clang_res) : 1;
    }

    return 0;
}
