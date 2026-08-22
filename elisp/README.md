# pascal1981-mode

`pascal1981-mode` is a major mode for the 1981 IBM Pascal dialect.
This compiler implements that dialect.

The mode does not implement the language again. The mode sends the
buffer text to the stage binaries `lexer` and `parser`. Then the
mode uses the JSON that those binaries write.

## Requirements

Put the Native Pascal 1981 binaries on `PATH`. The mode looks for
the names `lexer` and `parser`. You can set other names:

```elisp
(setq pascal1981-lexer-program "lexer")
(setq pascal1981-parser-program "parser")
```

## Load the mode

There is no install target. Add the `elisp/` directory to
`load-path`. Then load the feature:

```elisp
(add-to-list 'load-path "/path/to/native-pascal-1981/elisp")
(require 'pascal1981-mode)
```

Emacs uses `pascal1981-mode` for `.pas` buffers.

## What the mode does

| Feature | Source |
| --- | --- |
| Font lock after idle time | Token stream from `lexer` |
| Font lock fallback | Elisp keywords, if the lexer is not available |
| Indentation | Token kinds such as `BEGIN`, `END`, `THEN`, and `DO`. `TAB` and `indent-region` both use this |
| Imenu | Parser AST decls, mapped to token positions |
| `M-x pascal1981-refresh` | Re-run `lexer` and `parser` on the buffer. Then apply faces |
| `M-x pascal1981-check-buffer` | `lexer \| parser`. Shows parser stderr, or `No parser errors` |
| Flycheck | Optional. The mode registers a checker only if flycheck is loaded |

The idle delay is `pascal1981-idle-delay` (0.4 s by default).
The indent width is `pascal1981-indent-width` (2 by default).

`C-M-\\` (`indent-region`) indents each line in the region. The mode
sets `indent-line-function` to `pascal1981-indent-line`. Emacs then
calls that function once per line.

Indent uses the lexer token stream. The parser AST has no source
spans, and the parser fails on half-typed buffers. `BEGIN`, `RECORD`,
and `REPEAT` open a block. `CASE ... OF` opens a block. `THEN`, `DO`,
and `ELSE` indent the next line only when they end that line. `SET OF`
and `ARRAY OF` do not indent. Names after `VAR`, `CONST`, or `TYPE`
align to the first identifier of that section. If `VAR` is alone on a
line, the next name indents by one width.

## Tests

Put `bin/` on `PATH`. Then run ERT from the repo root:

```sh
PATH="$PWD/bin:$PATH" emacs -Q --batch -L elisp \
  -l elisp/pascal1981-mode-tests.el \
  -f ert-run-tests-batch-and-exit
```

## I/O contract

The `lexer` binary reads Pascal source on stdin. It writes a JSON
token array on stdout. It exits with status 0.

The `parser` binary reads that JSON array on stdin. It writes a
JSON AST on stdout. On success it exits with status 0. On failure
it exits with status 1 and writes `Parser Error: ...` on stderr.

CAUTION: Do not send `[]` to the parser. The parser can crash.

Each token object has these fields: `kind`, `code`, `lexeme`,
`value`, `line`, `column`, and `flags`. Each AST object has a
`__node_type__` field.
