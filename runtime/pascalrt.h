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
int   pas_fread_int(struct pas_file_fcb *f, int32_t *out);
int   pas_fread_int16(struct pas_file_fcb *f, int16_t *out);
int   pas_fread_int32(struct pas_file_fcb *f, int32_t *out);
int   pas_fread_int64(struct pas_file_fcb *f, int64_t *out);
int   pas_fread_word(struct pas_file_fcb *f, uint16_t *out);
int   pas_fread_ptr(struct pas_file_fcb *f, uint64_t *out);
int   pas_fread_real(struct pas_file_fcb *f, double *out);
int   pas_fread_char(struct pas_file_fcb *f, uint8_t *out);
int   pas_fread_lstring(struct pas_file_fcb *f, uint8_t *buf, int cap);
int   pas_fread_string(struct pas_file_fcb *f, uint8_t *buf, int cap);
int   pas_fread_enum_name(struct pas_file_fcb *f, int32_t *out,
                          const char **names, int count);
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

int   pas_read_int(int32_t *out);
int   pas_read_int16(int16_t *out);
int   pas_read_int32(int32_t *out);
int   pas_read_int64(int64_t *out);
int   pas_read_word(uint16_t *out);
int   pas_read_ptr(uint64_t *out);
int   pas_read_real(double *out);
int   pas_read_char(uint8_t *out);
int   pas_read_lstring(uint8_t *buf, int cap);
int   pas_read_string(uint8_t *buf, int cap);
int   pas_read_enum_name(int32_t *out, const char **names, int count);
void  pas_readln_skip(void);

/* ---- ENCODE / DECODE (encode_decode.c) ---- */

int32_t encode_value(char *dest_chars, int32_t dest_cap,
                     char *dest_raw, int32_t value,
                     int32_t width, int32_t precision, int32_t reserved);

int32_t decode_value(char *src_chars, int32_t src_len,
                     char *dest_raw, int32_t dest_size,
                     int32_t reserved3, int32_t reserved4, int32_t reserved5);

/* ---- SCANEQ / SCANNE (scaneq.c) ---- */

int32_t scaneq(int32_t L, char P, const char *chars, int32_t length,
               int32_t I, int32_t stop_on_equal);

int32_t scanne(int32_t L, char P, const char *chars, int32_t length,
               int32_t I, int32_t stop_on_equal);

/* ---- POSITN (positn.c) ---- */

int32_t positn(const char *haystack, int32_t haylen,
               const char *needle, int32_t needlelen);

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

/* ---- $INITCK host locals, formals, results and aggregates (initck.c) ---- */
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

/* ---- $INDEXCK fixed-array indexes (array_index.c) ---- */

void  pas_array_index_error(int64_t value, int32_t value_unsigned,
                            int64_t lo, int64_t hi) __attribute__((noreturn));

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

/* ---- IBM never-trapping 16-bit arithmetic (overflow_ok.c) ----
 * For programs that declare these EXTERN as the manual (11-21) says; an
 * undeclared call is lowered inline. Only the low 16 bits of a and b are
 * read. Return true when the wrapped result stored in *c did not overflow. */
_Bool SADDOK(uint32_t a, uint32_t b, int16_t *c);
_Bool SMULOK(uint32_t a, uint32_t b, int16_t *c);
_Bool UADDOK(uint32_t a, uint32_t b, uint16_t *c);
_Bool UMULOK(uint32_t a, uint32_t b, uint16_t *c);

/* ---- $RANGECK subrange stores (subrange.c) ---- */

void  pas_subrange_error(int64_t value, int32_t value_unsigned,
                         int64_t lo, int64_t hi) __attribute__((noreturn));

/* ---- set constructor elements outside 0..255 (set_element.c) ---- */

void  pas_set_element_error(int64_t value) __attribute__((noreturn));

#ifdef __cplusplus
}
#endif

#endif /* PASCALRT_H */
