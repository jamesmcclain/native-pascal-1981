/*
 * pascalrt.h  —  Shared declarations for the Pascal-1981 C runtime.
 *
 * This header collects the types, constants, and function prototypes that
 * are common across the runtime translation units.  It replaces duplicate
 * definitions that previously lived in multiple .c files.
 */

#ifndef PASCALRT_H
#define PASCALRT_H

#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------ *
 * FCB mode constants (must match codegen/base.py and codegen/files.py)
 * ------------------------------------------------------------------ */
#define MODE_CLOSED   0
#define MODE_READ     1
#define MODE_WRITE    2
#define MODE_BITS     3
#define MODE_EOF      4
#define MODE_STD      8
#define MODE_PENDING 16
#define MODE_EOLN    32
#define MODE_OWNS_HANDLE 64
#define MODE_TEMP   128

#define STRUCT_BINARY 0
#define STRUCT_TEXT   1

/* ------------------------------------------------------------------ *
 * File-control block (FCB)
 *
 * Must match the LLVM struct literal in codegen/base.py :: file_fcb_type():
 *   { i32 elem_size, i32 structure, i32 touched, i32 mode,
 *     i8* buffer, i8* handle, i8* name, i32 filemode, i8 trap, i32 errs }
 * ------------------------------------------------------------------ */
struct pas_file_fcb {
    int          elem_size;
    int          structure;
    int          touched;
    int          mode;
    void        *buffer;
    FILE        *handle;
    char        *name;
    int          filemode;
    unsigned char trap;         /* F.TRAP  — trapped-I/O switch (manual ch.12) */
    int          errs;          /* F.ERRS  — last trapped error code           */
    unsigned char *initck_state; /* INITCK: one byte per leaf of the buffer, or
                                    NULL when the component type is untracked */
    int          initck_n;
};

/* ------------------------------------------------------------------ *
 * ADSMEM — segmented address (flat pointer + segment word).
 * Used by FILLSC, MOVESL, MOVESR.  The segment is always zero on this
 * flat-memory host; the struct is retained for ABI compatibility.
 * ------------------------------------------------------------------ */
typedef struct {
    char          *ptr;
    unsigned short seg;
} adsmem;

/* ================================================================== *
 * Function prototypes — one per externally-callable runtime entry.
 * ================================================================== */

/* ---- File-control block operations (fileops.c) ---- */

void  pas_file_attach_std(struct pas_file_fcb *in,
                          struct pas_file_fcb *out);
void  pas_std_input_sync(void);
void *pas_file_buffer(struct pas_file_fcb *f);
void  pas_file_touch_buffer(struct pas_file_fcb *f);
void  pas_file_get(struct pas_file_fcb *f);
void  pas_file_reset(struct pas_file_fcb *f);
void  pas_file_rewrite(struct pas_file_fcb *f);
void  pas_file_put(struct pas_file_fcb *f);
void  pas_file_close(struct pas_file_fcb *f);
void  pas_file_discard(struct pas_file_fcb *f);
void  pas_file_assign(struct pas_file_fcb *f,
                      const char *name, int len);

int   pas_file_eof(struct pas_file_fcb *f);
int   pas_file_eoln(struct pas_file_fcb *f);

/* Formatted WRITE (varargs) */
int   pas_write_fmt(struct pas_file_fcb *f, const char *fmt, ...);

/* Enum name lookup for WRITE (weak — user may override) */
const char *pas_enum_write_token(int32_t value, const char **names, int count);

/* File-based formatted READ */
int   pas_fread_int16(struct pas_file_fcb *f, int16_t *out);
int   pas_fread_int32(struct pas_file_fcb *f, int32_t *out);
int   pas_fread_int64(struct pas_file_fcb *f, int64_t *out);
int   pas_fread_word(struct pas_file_fcb *f, uint16_t *out);
int   pas_fread_ptr(struct pas_file_fcb *f, uint64_t *out);

/* Pointer READ token scanner shared by pas_read_ptr and pas_fread_ptr: it
 * skips whitespace, reads one token from next(), pushes the stopping
 * character back with unget(), and returns a PAS_PTR_SCAN_* code. */
typedef int (*pas_char_next_fn)(void *src);
typedef void (*pas_char_unget_fn)(void *src, int ch);
enum { PAS_PTR_SCAN_OK, PAS_PTR_SCAN_EOF, PAS_PTR_SCAN_MALFORMED, PAS_PTR_SCAN_RANGE };
int   pas_scan_ptr_token(pas_char_next_fn next, pas_char_unget_fn unget, void *src,
                         uint64_t *out);
int   pas_fread_real(struct pas_file_fcb *f, double *out);
int   pas_fread_char(struct pas_file_fcb *f, uint8_t *out);
int   pas_fread_lstring(struct pas_file_fcb *f, uint8_t *buf, int cap);
int   pas_fread_string(struct pas_file_fcb *f, uint8_t *buf, int cap);
int   pas_fread_enum_name(struct pas_file_fcb *f, int32_t *out,
                          const char **names, int lo, int hi);
int   pas_fread_enum_ord(struct pas_file_fcb *f, int32_t *out, int lo, int hi);
void  pas_freadln_skip(struct pas_file_fcb *f);

/* READSET / READFN */
void  pas_freadset(struct pas_file_fcb *src,
                   unsigned char *lstr, int capacity,
                   const uint64_t *set_words);
void  pas_fread_filename(struct pas_file_fcb *src,
                         struct pas_file_fcb *target);

/* ---- Process command-line arguments (cmdline.c) ---- */

/* --- TCP sockets (netsock.c) ------------------------------------------- */
/* Read outcomes that are not byte counts. Distinct values because a caller
 * implementing a request timeout has to tell "deadline passed" from "peer
 * closed the connection". */
#define PAS_SOCK_ERROR   (-1L)
#define PAS_SOCK_TIMEOUT (-2L)

long long pas_double_to_int64(double value);
double pas_int64_to_double(long long value);

void  pas_net_init(void);
void  pas_net_autoreap(void);
int   pas_tcp_listen(const char *host, int port, int backlog);
int   pas_tcp_port(int fd);
int   pas_tcp_accept(int listen_fd);
int   pas_tcp_connect(const char *host, int port, int timeout_ms);
long  pas_sock_read(int fd, char *buf, long cap, int timeout_ms);
long  pas_sock_write(int fd, const char *buf, long len);
void  pas_sock_shutdown_write(int fd);
void  pas_sock_close(int fd);
int   pas_url_split(const char *url, char *host, int hostcap,
                    int *port, char *path, int pathcap);

int         pas_arg_count(void);
const char *pas_arg_value(int index);
char       *pas_toolchain_root(void);

/* ---- POSIX system utilities (sysutil.c) -------------------------- */

#define PAS_SYS_OK       0
#define PAS_SYS_ERROR   (-1)
#define PAS_SYS_TIMEOUT (-2)
#define PAS_SYS_SIGNAL  (-3)

#define PAS_SYS_ENTRY_OTHER 0
#define PAS_SYS_ENTRY_DIR   1
#define PAS_SYS_ENTRY_FILE  2

void *pas_sys_dir_open(const char *path);
/* Returns 0 at end, -1 on error, or entry kind + 1. */
int   pas_sys_dir_next(void *handle, char *name, int namecap);
int   pas_sys_dir_close(void *handle);
int   pas_sys_temp_dir(const char *prefix, char *out, int outcap);
const char *pas_project_temp_root(void);
char *pas_driver_temp_file(const char *suffix);
FILE *pas_project_tmpfile(void);
int   pas_sys_remove_tree(const char *path);
/* The caller releases a successful read result with pas_sys_free. */
char *pas_sys_read_file(const char *path, int *out_len);
int   pas_sys_write_file(const char *path, const char *data, int len);
void  pas_sys_free(void *ptr);
/* packed_args is a sequence of NUL-terminated argv entries, excluding argv[0].
 * timeout_ms: 0 waits indefinitely; >0 is a millisecond bound; <0 is EINVAL. */
int   pas_sys_exec(const char *executable, const char *packed_args,
                   int packed_args_len, int timeout_ms, int *exit_code,
                   int *term_signal, char *diagnostics, int diagnostics_cap,
                   int *diagnostics_len);

/* ---- stdin READ / READLN (readq.c) ---- */

int   pas_read_int16(int16_t *out);
int   pas_read_int32(int32_t *out);
int   pas_read_int64(int64_t *out);
int   pas_read_word(uint16_t *out);
int   pas_read_ptr(uint64_t *out);
int   pas_read_real(double *out);
int   pas_read_char(uint8_t *out);
int   pas_read_eof(void);
int   pas_read_eoln(void);
int   pas_read_lstring(uint8_t *buf, int cap);
int   pas_read_string(uint8_t *buf, int cap);
int   pas_read_enum_name(int32_t *out, const char **names, int lo, int hi);
int   pas_read_enum_ord(int32_t *out, int lo, int hi);
void  pas_readln_skip(void);

/* ---- ENCODE / DECODE (encode_decode.c) ---- */

/* ENCODE: vsnprintf the WRITE-style format into an LSTRING; 1 when it fits. */
int32_t pas_encode_fmt(char *dest_chars, int32_t dest_cap,
                       char *dest_raw, const char *fmt, ...);

/* DECODE: convert the whole trimmed text as READ would; 1 and a store
 * through `out` on success, 0 and no store otherwise. Never aborts. */
int32_t pas_decode_integer(const char *src, int32_t len, int32_t bits,
                           int32_t is_unsigned, int32_t has_bounds,
                           int64_t lo, int64_t hi, int64_t *out);
int32_t pas_decode_enum(const char *src, int32_t len, const char **names,
                        int32_t lo, int32_t hi, int32_t *out);
int32_t pas_decode_char(const char *src, int32_t len, int32_t lo, int32_t hi,
                        uint8_t *out);
int32_t pas_decode_real(const char *src, int32_t len, double *out);

/* ---- SCANEQ / SCANNE (scaneq.c) ---- */

int32_t scaneq(int32_t L, char P, const char *chars, int32_t length,
               int32_t I, int32_t stop_on_equal);

int32_t scanne(int32_t L, char P, const char *chars, int32_t length,
               int32_t I, int32_t stop_on_equal);

/* ---- POSITN (positn.c) ---- */

/* Legacy start-at-one ABI, retained for previously generated/imported code. */
int32_t positn(const char *haystack, int32_t haylen,
               const char *needle, int32_t needlelen);
/* POSITN(P, S, I) lowering: explicit lengths and a signed 1-based start.
 * Empty pattern returns 1; invalid nonempty start or no match returns 0. */
int32_t positn_from(const char *haystack, int32_t haylen,
                    const char *needle, int32_t needlelen, int32_t start);

/* ---- ABORT (pabort.c) ---- */

void  pabort(const char *msg, int msglen,
             unsigned short code, unsigned short status);

/* ---- FILL / MOVE (fillc.c, fillsc.c, movel.c, mover.c, movesl.c, movesr.c) ---- */

int   fillc(char *loc, unsigned short len, char val);
int   fillsc(adsmem dst, unsigned short len, char val);
int   movel(char *src, char *dst, unsigned short len);
int   mover(char *src, char *dst, unsigned short len);
int   movesl(adsmem src, adsmem dst, unsigned short len);
int   movesr(adsmem src, adsmem dst, unsigned short len);

/* ---- VLOAD/VSTORE SUPER ARRAY bounds (vector_bounds.c) ---- */

void  pas_vector_nil_error(int32_t is_store) __attribute__((noreturn));
void  pas_upper_nil_error(int32_t unused) __attribute__((noreturn));
void  pas_super_index_nil_error(void) __attribute__((noreturn));
void  pas_new_error(void) __attribute__((noreturn));
void *pas_super_new(int64_t upper_bits, int32_t upper_unsigned, int64_t lower,
                    int64_t domain_low, int64_t domain_high,
                    uint64_t stride, uint64_t alignment);
void  pas_super_import_check(void *raw, int64_t lower_bits, int32_t lower_unsigned,
                            int64_t upper_bits, int32_t upper_unsigned,
                            int64_t declared_lower, int64_t domain_low,
                            int64_t domain_high, uint64_t stride, uint64_t alignment);
void  pas_vector_range_error(int32_t is_store, int64_t idx, int32_t idx_unsigned,
                             int32_t lanes, int64_t lo, int64_t hi) __attribute__((noreturn));

/* ---- $STACKCK+ main-thread overflow reporter (stackck.c) ---- */
/* Idempotent; called at program/unit entry when the compiland has probed
 * (STACKCK+) functions. */
void pas_stackck_init(void);

/* ---- $INITCK host locals, formals, results and aggregates (initck.c) ---- */
/* Null-only ordinary host pointer dereference failure; never returns. */
/* Located diagnostics (diagnostics.c): pas_diag_file names the $INCLUDEd
 * source of the failure being reported (NULL: the primary file), and
 * pas_diag_where() is "" or " of file NAME", printed right after a
 * failure's "at line L column C". */
extern _Thread_local const char *pas_diag_file;
const char *pas_diag_where(void);

void pas_nilck_error(int32_t line, int32_t column);
void pas_nilck_dispose_error(int32_t line, int32_t column);
void pas_initck_error(const char *name, int32_t line, int32_t column);
/* what is "local", "parameter", "result of", "component" or "part of". */
void pas_initck_fail(const char *what, const char *name, int32_t line, int32_t column);
/* Must cover MAX_PARAMS in src/cg_base.inc. */
#define PAS_INITCK_MAX_ARGS 16
extern _Thread_local void *pas_initck_args[PAS_INITCK_MAX_ARGS];
extern _Thread_local _Bool pas_initck_ret;
extern _Thread_local void *pas_initck_callee;
extern _Thread_local _Bool *pas_initck_ack;
/* Aggregate shadows: one byte per scalar leaf, nonzero when initialized. */
int32_t pas_initck_all(const unsigned char *s, int64_t n);
void pas_initck_copy(unsigned char *dst, const unsigned char *src, int64_t n, int32_t ok);
void pas_initck_fill(unsigned char *dst, int64_t n, int32_t ok);
void pas_initck_receive(unsigned char *own, const unsigned char *p, int64_t n);
void pas_initck_release_unacked(unsigned char *dst, int64_t n, int32_t acked);
/* Heap referent state (initck_heap.c), keyed by the data address NEW
 * published; unregistered or released referents read as initialized. */
void pas_initck_heap_new(const void *data, int64_t n);
unsigned char *pas_initck_heap(const void *data, int64_t n);
unsigned char *pas_initck_heap_part(const void *data, int64_t n, int64_t offset, int64_t count);
unsigned char *pas_initck_heap_at(const void *data, int64_t n, unsigned char *fallback);
unsigned char *pas_initck_heap_part_at(const void *data, int64_t n, int64_t offset, int64_t count,
                                       unsigned char *fallback);
void pas_initck_heap_release(const void *data);
void pas_initck_heap_dispose(const void *data);

/* ---- $INDEXCK fixed/SUPER ARRAY bounds failures (array_index.c) ----
 * Flush stdout, report the original ordinal and actual bounds at the first
 * index-expression token, flush stderr and abort. Legacy coordinates: 0:0. */

void  pas_array_index_error(int64_t value, int32_t value_unsigned,
                            int64_t lo, int64_t hi, int32_t line,
                            int32_t column) __attribute__((noreturn));

/* ---- MATHCK runtime failures (mathck.c) ----
 * Both flush stdout, print one located "runtime error: MATHCK ..." line,
 * flush stderr and abort. pas_math_zero is the mandatory zero-divisor
 * failure (either MATHCK setting). pas_math_overflow is MATHCK+ overflow;
 * op is 0 +, 1 -, 2 *, 3 DIV, 4 unary -, 5 SUCC, 6 PRED, 7 ABS, 8 SQR,
 * 9 VSUM, 10 VPROD (4 through 8 are unary: right ignored; for 9 and 10
 * left is the partial result and right the lane). Operands arrive widened to 64 bits with their own
 * signedness. line/column are the operator or builtin-name token's, 0:0
 * for a legacy AST without a snapshot. */
void  pas_math_zero(int32_t is_unsigned, int32_t is_mod,
                    int64_t left, int64_t right,
                    int32_t line, int32_t column) __attribute__((noreturn));
/* TRUNC/ROUND out of INTEGER range or NaN (numeric.c): always checked,
 * independent of MATHCK. kind 0 TRUNC, 1 ROUND. */
void  pas_conversion_error(int32_t kind, double value,
                           int32_t line, int32_t column) __attribute__((noreturn));
void  pas_math_overflow(int32_t is_unsigned, int32_t op,
                        int64_t left, int64_t right,
                        int32_t line, int32_t column) __attribute__((noreturn));

/* ---- NVPTX device error channel (dev_error.c) ----
 * NVPTX code cannot call the host failure routines, so a failing device check
 * records the first error in the module global PAS_DEV_ERROR_SYMBOL and the
 * thread continues with a defined (saturated) value. The CUDA launch shim
 * reads the cell after cuCtxSynchronize and, when code is nonzero, calls
 * pas_dev_error_report, which prints the host check's own diagnostic and
 * aborts. The first writer wins: a device thread claims the cell with an
 * atomic compare-and-swap of code from 0, then stores the other fields.
 * Layout (24 bytes, align 8) must match DeviceErrorCell in src/cg_expr.pas.
 * A new device check adds a code here and a case in pas_dev_error_report.
 *
 * Device code cannot hand the host a string, so a check in an $INCLUDEd file
 * stores a small file index k (1, 2, ...) in `file`, and the same module
 * defines the NUL-terminated constant string __pas_dev_file_k (the include
 * path as written; DeviceFileIndex in src/cg_expr.pas). The launch shim
 * reads that global and passes it to pas_dev_error_report, which names it
 * exactly as the host diagnostic does (" of file NAME", pas_diag_where). A
 * primary-file check leaves `file` 0. */
#define PAS_DEV_ERROR_SYMBOL "__pas_dev_error"
#define PAS_DEV_FILE_SYMBOL  "__pas_dev_file_"  /* + decimal file index */
#define PAS_DEV_ERROR_NONE  0
#define PAS_DEV_ERROR_TRUNC 1   /* TRUNC out of INTEGER range or NaN */
#define PAS_DEV_ERROR_ROUND 2   /* ROUND out of INTEGER range or NaN */
typedef struct {
    int32_t code;       /* PAS_DEV_ERROR_*; 0 = no error */
    int32_t line;       /* source location of the failing check */
    int32_t column;
    int32_t file;       /* 0: primary file; k: __pas_dev_file_k */
    double  value;      /* TRUNC/ROUND: the REAL argument */
} pas_dev_error_cell;
/* Returns only when code is PAS_DEV_ERROR_NONE. file is the string the
 * cell's file index names, or NULL (primary file, or not found). */
void  pas_dev_error_report(const pas_dev_error_cell *cell, const char *file);
/* The module global holding file index `file` ("__pas_dev_file_<k>") into
 * buf; false when the index names no file (0 or negative). */
_Bool pas_dev_error_file_symbol(int32_t file, char *buf, size_t size);

/* ---- IBM never-trapping 16-bit arithmetic (overflow_ok.c) ----
 * For programs that declare these EXTERN as the manual (11-21) says; an
 * undeclared call is lowered inline. Only the low 16 bits of a and b are
 * read. Return true when the wrapped result stored in *c did not overflow. */
_Bool SADDOK(uint32_t a, uint32_t b, int16_t *c);
_Bool SMULOK(uint32_t a, uint32_t b, int16_t *c);
_Bool UADDOK(uint32_t a, uint32_t b, uint16_t *c);
_Bool UMULOK(uint32_t a, uint32_t b, uint16_t *c);

/* ---- $RANGECK subrange stores, CONCAT/COPYLST, LSTRING length, CHR/BYWORD and CASE (subrange.c) ---- */

/* COPYSTR overflow is error 2150, always caught: no switch disables it. */
void  pas_copystr_error(uint64_t length, int32_t capacity,
                        int32_t line, int32_t column) __attribute__((noreturn));
/* INSERT and DELETE errors are error 2151, always caught. */
void  pas_insert_error(uint64_t length, int32_t capacity,
                       int32_t line, int32_t column) __attribute__((noreturn));
void  pas_insert_position_error(int32_t position, int32_t count, int32_t length,
                                int32_t line, int32_t column) __attribute__((noreturn));
void  pas_delete_error(int32_t position, int32_t count, int32_t length,
                       int32_t line, int32_t column) __attribute__((noreturn));

void  pas_copylst_error(uint64_t length, int32_t capacity,
                        int32_t line, int32_t column) __attribute__((noreturn));
void  pas_concat_error(uint64_t length, int32_t capacity,
                       int32_t line, int32_t column) __attribute__((noreturn));

void  pas_lstring_length_error(uint64_t length, int32_t capacity,
                               int32_t line, int32_t column) __attribute__((noreturn));

void  pas_chr_error(int64_t value, int32_t value_unsigned,
                    int32_t line, int32_t column) __attribute__((noreturn));

void  pas_byword_error(int64_t value, int32_t value_unsigned,
                       int32_t line, int32_t column) __attribute__((noreturn));

void  pas_case_error(int64_t value, int32_t value_unsigned,
                     int32_t line, int32_t column) __attribute__((noreturn));

void  pas_subrange_error(int64_t value, int32_t value_unsigned,
                         int64_t lo, int64_t hi,
                         int32_t line, int32_t column) __attribute__((noreturn));

/* ---- set constructor elements outside 0..255 (set_element.c) ---- */

void  pas_set_element_error(int64_t value) __attribute__((noreturn));

#ifdef __cplusplus
}
#endif

#endif /* PASCALRT_H */
