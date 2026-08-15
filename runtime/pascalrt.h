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
int   pas_fread_word(struct pas_file_fcb *f, uint16_t *out);
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

/* ---- stdin READ / READLN (readq.c) ---- */

int   pas_read_int(int32_t *out);
int   pas_read_word(uint16_t *out);
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

#ifdef __cplusplus
}
#endif

#endif /* PASCALRT_H */
