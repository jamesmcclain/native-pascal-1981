/* pasboot: a translator from the bootstrap subset of the extended 1981 IBM
 * Pascal dialect to C99. It exists only to build generation 1 of the
 * self-hosting compiler; docs/bootstrap_subset.md defines the subset.
 *
 * The pipeline is lex.c (tokens, comments, $INCLUDE splicing) -> parse.c
 * (recursive descent into the AST below) -> sem.c (types, symbols, the
 * unit model) -> emit.c (C text). Anything outside the subset is reported
 * as "file:line: unsupported: <construct>" and ends the run. */
#ifndef PASBOOT_H
#define PASBOOT_H

#include <stdint.h>
#include <stdio.h>

/* ---- utilities (main.c) ---- */

typedef struct Loc {
    const char *file;
    int line;
} Loc;

void *xmalloc(size_t n);
void *xrealloc(void *p, size_t n);
char *xstrdup(const char *s);
char *xfmt(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
void fatal(Loc loc, const char *fmt, ...) __attribute__((format(printf, 2, 3), noreturn));
void unsupported(Loc loc, const char *what) __attribute__((noreturn));

/* A growable byte buffer. */
typedef struct Buf {
    char *p;
    size_t len, cap;
} Buf;

void buf_put(Buf * b, const char *s);
void buf_printf(Buf * b, const char *fmt, ...) __attribute__((format(printf, 2, 3)));

/* A growable array of pointers. */
typedef struct Vec {
    void **p;
    int n, cap;
} Vec;

void vec_push(Vec * v, void *x);

/* ---- tokens (lex.c) ---- */

enum TokKind { T_EOF, T_IDENT, T_INT, T_REAL, T_STR, T_CHAR, T_PUNCT };

enum Punct {
    P_LPAREN = 1, P_RPAREN, P_LBRACK, P_RBRACK, P_COMMA, P_SEMI, P_COLON,
    P_ASSIGN, P_DOT, P_DOTDOT, P_CARET, P_PLUS, P_MINUS, P_STAR, P_SLASH,
    P_EQ, P_NE, P_LT, P_LE, P_GT, P_GE
};

typedef struct Token {
    int kind;
    int punct;
    char *text;                 /* identifiers: folded to lower case */
    char *orig;                 /* identifiers: as spelled */
    int64_t ival;               /* T_INT, and the byte of a T_CHAR */
    double rval;                /* T_REAL */
    unsigned char *sval;        /* T_STR bytes (not NUL terminated) */
    int slen;
    Loc loc;
} Token;

/* Tokenize a compiland, splicing every $INCLUDE relative to the directory of
 * the file that names it. The result ends with one T_EOF token. */
Token *lex_file(const char *path, int *ntok);
const char *punct_text(int p);

/* ---- AST (parse.c) ---- */

typedef struct Expr Expr;
typedef struct Stmt Stmt;
typedef struct TypeExpr TypeExpr;
typedef struct Type Type;
typedef struct Sym Sym;

enum TypeExprKind { TE_NAME, TE_LSTRING, TE_ARRAY, TE_RECORD, TE_POINTER, TE_ENUM };

typedef struct FieldGroup {
    Vec names;                  /* char * */
    TypeExpr *te;
    Loc loc;
} FieldGroup;

struct TypeExpr {
    int kind;
    Loc loc;
    char *name;                 /* TE_NAME, TE_POINTER target */
    Expr *lo, *hi;              /* TE_ARRAY bounds, TE_LSTRING capacity (lo) */
    TypeExpr *elem;             /* TE_ARRAY */
    Vec fields;                 /* TE_RECORD: FieldGroup * */
    Vec names;                  /* TE_ENUM: char * */
};

enum ExprKind {
    E_INT, E_REAL, E_STR, E_CHAR, E_NAME, E_CALL, E_INDEX, E_FIELD, E_DEREF,
    E_BIN, E_UN, E_ADR
};

enum Op {
    OP_ADD = 1, OP_SUB, OP_MUL, OP_RDIV, OP_IDIV, OP_MOD, OP_AND, OP_OR,
    OP_ANDTHEN, OP_EQ, OP_NE, OP_LT, OP_LE, OP_GT, OP_GE, OP_NEG, OP_NOT
};

struct Expr {
    int kind;
    Loc loc;
    int op;
    char *name;                 /* E_NAME, E_CALL, E_FIELD, E_ADR */
    int64_t ival;
    double rval;
    unsigned char *s;           /* E_STR */
    int slen;
    Expr *a, *b;                /* operands; E_INDEX/E_FIELD/E_DEREF base in a */
    Vec args;                   /* E_CALL: Expr * */
};

enum StmtKind {
    S_EMPTY, S_ASSIGN, S_CALL, S_IF, S_WHILE, S_FOR, S_BLOCK, S_RETURN,
    S_BREAK, S_CYCLE
};

struct Stmt {
    int kind;
    Loc loc;
    Expr *lhs, *rhs;            /* S_ASSIGN; S_CALL uses lhs */
    Expr *cond;                 /* S_IF, S_WHILE */
    Stmt *then, *els, *body;
    Vec stmts;                  /* S_BLOCK: Stmt * */
    char *var;                  /* S_FOR */
    Loc varloc;
    Expr *from, *to;
    int down;
};

typedef struct ConstDecl {
    char *name;
    Loc loc;
    Expr *val;
} ConstDecl;

typedef struct TypeDecl {
    char *name;
    Loc loc;
    TypeExpr *te;
} TypeDecl;

typedef struct VarDecl {
    Vec names;                  /* char * */
    Loc loc;
    TypeExpr *te;
} VarDecl;

typedef struct ParamGroup {
    Vec names;                  /* char * */
    int is_var;
    TypeExpr *te;
    Loc loc;
} ParamGroup;

enum DeclKind { D_CONST, D_TYPE, D_VAR, D_ROUTINE };

typedef struct Routine Routine;

typedef struct Decl {
    int kind;
    Loc loc;
    Vec items;                  /* ConstDecl * / TypeDecl * / VarDecl * */
    Routine *routine;
} Decl;

struct Routine {
    char *name;                 /* folded */
    char *orig;                 /* as spelled: the C symbol of a [C] routine */
    Loc loc;
    int is_func;
    int has_params;             /* a parenthesized list was written */
    Vec params;                 /* ParamGroup * */
    TypeExpr *result;
    int is_c;                   /* [C] */
    int is_extern;              /* EXTERN; */
    int is_forward;             /* FORWARD; */
    int has_body;
    Vec decls;                  /* local CONST/TYPE/VAR sections: Decl * */
    Stmt *body;
};

typedef struct Interface {
    char *unit;
    Loc loc;
    Vec uses;                   /* char * */
    Vec decls;                  /* Decl * */
} Interface;

typedef struct Compiland {
    Vec ifaces;                 /* Interface *, in splice order */
    int is_program;
    char *name;                 /* program or implemented unit */
    Loc loc;
    Vec uses;                   /* char * */
    Vec decls;                  /* Decl * */
    Stmt *body;
} Compiland;

Compiland *parse_compiland(Token * toks, int ntok);

/* ---- semantics and emission (sem.c, emit.c) ---- */

enum TypeKind {
    TY_INT, TY_REAL, TY_BOOL, TY_CHAR, TY_ADRMEM, TY_ENUM, TY_LSTR, TY_ARRAY,
    TY_RECORD, TY_PTR, TY_NIL, TY_STRLIT, TY_VOID
};

typedef struct Field {
    char *name;
    Type *ty;
} Field;

struct Type {
    int kind;
    int width;                  /* TY_INT: 16, 32 or 64 */
    const char *iname;          /* TY_INT: the Pascal name, for messages */
    int cap;                    /* TY_LSTR capacity */
    int64_t lo, hi;             /* TY_ARRAY bounds; TY_ENUM ordinal range */
    Type *elem;                 /* TY_ARRAY */
    Field *fields;              /* TY_RECORD */
    int nfields;
    Type *target;               /* TY_PTR */
    char *pending;              /* TY_PTR: target name awaiting resolution */
    Loc loc;
    int id;
    int emitted;                /* C definition written */
    int declared;               /* C struct tag forward-declared */
};

enum SymKind { SY_CONST, SY_TYPE, SY_VAR, SY_ROUTINE };

typedef struct ParamInfo {
    char *name;
    Type *ty;
    int is_var;
} ParamInfo;

struct Sym {
    char *name;                 /* folded */
    int kind;
    Loc loc;
    Type *ty;                   /* const/var type, function result, type */
    /* SY_CONST */
    int64_t ival;
    double rval;
    unsigned char *sval;
    int slen;
    /* SY_VAR */
    int is_varparam;            /* reached through a pointer */
    int is_result;              /* the hidden result of the current function */
    /* SY_VAR and SY_ROUTINE */
    char *cname;                /* the C spelling */
    int unit_level;             /* declared at compiland scope */
    int from_iface;             /* declared in a spliced interface */
    char *owner;                /* interface unit that declared it */
    /* SY_ROUTINE */
    Routine *routine;
    ParamInfo *params;
    int nparams;
    int is_c;
    int defined;                /* a body has been emitted */
    int prototyped;             /* a C prototype has been emitted */
};

/* sem.c: the type model, scopes, constants, and C type spellings. */
extern Type *t_integer, *t_int32, *t_cint, *t_int64, *t_clong, *t_csize;
extern Type *t_real, *t_bool, *t_char, *t_adrmem, *t_nil, *t_strlit, *t_void;
extern Buf types_buf;           /* C type definitions, written on demand */

void sem_init(void);
void scope_push(void);
void scope_pop(void);
int scope_depth(void);
Sym *new_sym(const char *name, int kind, Loc loc);
Sym *lookup(const char *name);
Sym *lookup_innermost(const char *name);
void define(Sym * s);
Type *resolve_type(TypeExpr * te);
void resolve_pending_pointers(void);
Sym *const_eval(Expr * e);
Type *int_type_for(int64_t v);
int is_int(Type * t);
int is_ptr(Type * t);           /* ^T, ADRMEM or NIL */
int same_type(Type * a, Type * b);
const char *type_name(Type * t);
const char *ctype(Type * t);

/* Translate one parsed compiland to C. Returns 0 on success. When
 * check_only is set, nothing is written. */
int translate(Compiland * c, FILE * out, int check_only);

#endif
