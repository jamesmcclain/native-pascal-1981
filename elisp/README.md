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
| Indentation | Token kinds such as `BEGIN`, `END`, `THEN`, and `DO` |
| Imenu | Parser AST decls, mapped to token positions |
| `M-x pascal1981-refresh` | Re-run `lexer` and `parser` on the buffer. Then apply faces |
| `M-x pascal1981-check-buffer` | `lexer \| parser`. Shows parser stderr, or `No parser errors` |
| Flycheck | Optional. The mode registers a checker only if flycheck is loaded |

The idle delay is `pascal1981-idle-delay` (0.4 s by default).
The indent width is `pascal1981-indent-width` (2 by default).

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
