;;; pascal1981-mode.el --- Major mode for Native Pascal 1981 -*- lexical-binding: t; -*-

;; Author: Native Pascal 1981 project
;; Keywords: languages pascal
;; URL: https://github.com/jamesmcclain/native-pascal-1981

;;; Commentary:
;; Major mode for the 1981 IBM Pascal dialect as implemented by
;; the Native Pascal 1981 compiler.  Uses the stage binaries
;; `lexer' and `parser' as out-of-process language servers:
;; buffer text is piped to stdin, JSON comes back on stdout.

;;; Code:
(require 'json)
(require 'cl-lib)

(defgroup pascal1981 nil
  "Major mode for Native Pascal 1981."
  :group 'languages
  :prefix "pascal1981-")

(defcustom pascal1981-lexer-program "lexer"
  "Executable for the Pascal 1981 lexer stage.
Assumed to be on `exec-path' / PATH."
  :type 'string :group 'pascal1981)

(defcustom pascal1981-parser-program "parser"
  "Executable for the Pascal 1981 parser stage."
  :type 'string :group 'pascal1981)

(defcustom pascal1981-idle-delay 0.4
  "Seconds of idle time before refreshing highlighting / indentation."
  :type 'number :group 'pascal1981)

(defvar pascal1981--token-cache nil
  "Buffer-local cache of last lexer output (vector of alists).")
(make-variable-buffer-local 'pascal1981--token-cache)

(defvar pascal1981--ast-cache nil
  "Buffer-local cache of last parser AST.")
(make-variable-buffer-local 'pascal1981--ast-cache)

(defvar pascal1981--idle-timer nil)
(make-variable-buffer-local 'pascal1981--idle-timer)

;; -------------------------------------------------------------------
;; Low-level process helpers — pipe text through stage binaries
;; -------------------------------------------------------------------

(defun pascal1981--call-process-to-json (program stdin-text)
  "Pipe STDIN-TEXT to PROGRAM (found via PATH) and parse stdout as JSON.
Return (STATUS . PAYLOAD) where STATUS is `ok' or `error'.
On `ok', PAYLOAD is the parsed JSON.  On `error', PAYLOAD is a
string with stderr / exit info.  PROGRAM is resolved via
`exec-path' so callers just pass \"lexer\" or \"parser\"."
  (let ((out-buf (generate-new-buffer " *pascal1981-out*"))
        (err-file (make-temp-file "pascal1981-err")))
    (unwind-protect
        (let ((exit-code
               (with-temp-buffer
                 (insert stdin-text)
                 (call-process-region (point-min) (point-max)
                                      program nil (list out-buf err-file) nil))))
          (let ((stdout (with-current-buffer out-buf (buffer-string)))
                (stderr (with-temp-buffer
                          (insert-file-contents err-file)
                          (buffer-string))))
            (if (zerop exit-code)
                (condition-case err
                    (cons 'ok (json-parse-string stdout
                                                  :object-type 'alist
                                                  :array-type 'array))
                  (error (cons 'error (format "JSON parse failed: %s\nraw: %s" err stdout))))
              (cons 'error (if (string-empty-p stderr)
                               (format "%s exited %d" program exit-code)
                             stderr)))))
      (kill-buffer out-buf)
      (ignore-errors (delete-file err-file)))))

(defun pascal1981-lex-string (source)
  "Lex SOURCE (a string of Pascal) via the `lexer' binary.
Return (ok . TOKENS) or (error . MESSAGE).  TOKENS is a vector of
alists with keys kind, code, lexeme, value, line, column, flags."
  (pascal1981--call-process-to-json pascal1981-lexer-program source))

(defun pascal1981-lex-region (start end)
  "Lex buffer region START..END.  See `pascal1981-lex-string'."
  (pascal1981-lex-string (buffer-substring-no-properties start end)))

(defun pascal1981-parse-tokens-json (tokens-json-text)
  "Parse TOKENS-JSON-TEXT (JSON array as produced by the lexer).
Return (ok . AST) or (error . MESSAGE).  AST is the ProgramUnit alist."
  (pascal1981--call-process-to-json pascal1981-parser-program tokens-json-text))

(defun pascal1981-parse-string (source)
  "Lex and parse SOURCE through the lexer | parser pipeline.
Return (ok . AST) or (error . MESSAGE).  On error the message comes
from the parser's stderr (e.g. \"Parser Error: ...\")."
  (let ((lex (pascal1981-lex-string source)))
    (if (eq (car lex) 'error)
        lex
      (pascal1981-parse-tokens-json (json-serialize (cdr lex))))))

(defun pascal1981--refresh-caches ()
  "Lex the current buffer, paint from tokens, then parse for the AST.
Highlighting does not wait for the parser."
  (let ((lex (pascal1981-lex-string (buffer-substring-no-properties (point-min) (point-max)))))
    (if (eq (car lex) 'error)
        (setq pascal1981--token-cache nil pascal1981--ast-cache nil)
      (setq pascal1981--token-cache (cdr lex))
      (pascal1981--apply-token-highlighting)
      (let ((ast (pascal1981-parse-tokens-json (json-serialize (cdr lex)))))
        (setq pascal1981--ast-cache (when (eq (car ast) 'ok) (cdr ast)))))))

(defun pascal1981-refresh ()
  "Re-lex and re-parse the current buffer, then reapply token faces."
  (interactive)
  (pascal1981--refresh-caches)
  (pascal1981--apply-token-highlighting)
  (message "pascal1981: %s tokens%s"
           (if pascal1981--token-cache (length pascal1981--token-cache) 0)
           (if pascal1981--ast-cache ", AST ok" "")))

;; -------------------------------------------------------------------
;; Token -> face mapping (lexer-driven highlighting)
;; -------------------------------------------------------------------

(defconst pascal1981--keyword-kinds
  '("PROGRAM" "MODULE" "INTERFACE" "IMPLEMENTATION" "USES"
    "CONST" "TYPE" "VAR" "VALUE" "LABEL"
    "PROCEDURE" "FUNCTION" "BEGIN" "END"
    "IF" "THEN" "ELSE" "FOR" "TO" "DOWNTO" "DO"
    "REPEAT" "UNTIL" "WHILE" "CASE" "OF" "OTHERWISE" "WITH"
    "GOTO" "BREAK" "CYCLE" "RETURN"
    "EXTERN" "EXTERNAL" "FORWARD" "PACKED" "SUPER"
    "ARRAY" "RECORD" "SET" "FILE" "LSTRING" "ORIGIN"
    "READONLY" "PUBLIC" "STATIC" "PURE" "OVERLAY" "FORTRAN"
    "UNIT" "VARS" "CONSTS")
  "Token kinds treated as keywords.")

(defconst pascal1981--type-kinds
  '("INTEGER" "REAL" "BOOLEAN" "CHAR" "WORD" "ADRMEM")
  "Built-in type names, highlighted as types when they appear as lexemes.")

(defun pascal1981--token-face (tok)
  "Return face symbol for token alist TOK, or nil."
  (let ((kind (alist-get 'kind tok)))
    (cond
     ((member kind pascal1981--keyword-kinds) 'font-lock-keyword-face)
     ((member kind '("INTEGER_LITERAL" "REAL_LITERAL")) 'font-lock-constant-face)
     ((member kind '("STRING_LITERAL" "CHAR_LITERAL")) 'font-lock-string-face)
     ((member kind '("BOOLEAN_LITERAL" "NIL")) 'font-lock-constant-face)
     ((member kind '("IDENTIFIER"))
      (when (member (alist-get 'lexeme tok) pascal1981--type-kinds)
        'font-lock-type-face))
     ((member kind '("LINE_COMMENT" "BLOCK_COMMENT")) 'font-lock-comment-face)
     (t nil))))

(defun pascal1981--line-col-pos (line col)
  "Buffer position of 1-based LINE and 1-based character column COL.
The lexer counts a TAB as one column, so this walks characters.
`move-to-column' would count a TAB as its display width instead.
The position is clamped to the end of LINE."
  (save-excursion
    (goto-char (point-min))
    (forward-line (1- line))
    (goto-char (min (line-end-position) (+ (point) (max 0 (1- col)))))
    (point)))

(defun pascal1981--token-bounds (tok)
  "Return (BEG . END) for token alist TOK, or nil if it is off-buffer."
  (let* ((line (alist-get 'line tok))
         (col  (alist-get 'column tok))
         (lex  (or (alist-get 'lexeme tok) "")))
    (when (and line col (> (length lex) 0))
      (let* ((beg (pascal1981--line-col-pos line col))
             (end (+ beg (length lex))))
        (when (and (>= beg (point-min)) (<= end (point-max)))
          (cons beg end))))))

(defun pascal1981--font-lock-from-tokens (limit)
  "Font-lock matcher: apply faces from `pascal1981--token-cache' up to LIMIT.
When the token cache is live, skip the regex fallback by advancing
point to LIMIT after the tokens are painted."
  (when pascal1981--token-cache
    (cl-loop for tok across pascal1981--token-cache
             for face = (pascal1981--token-face tok)
             for bounds = (and face (pascal1981--token-bounds tok))
             when (and bounds (< (car bounds) limit) (>= (cdr bounds) (point)))
             do (add-face-text-property (car bounds) (cdr bounds) face))
    (goto-char limit)
    t))

(defun pascal1981--apply-token-highlighting ()
  "Ask font-lock to repaint from the current token cache."
  (when (fboundp 'font-lock-flush)
    (font-lock-flush))
  (when (fboundp 'font-lock-ensure)
    (font-lock-ensure)))

(defun pascal1981--schedule-refresh ()
  "Debounce: refresh caches and highlighting after `pascal1981-idle-delay'."
  (when pascal1981--idle-timer (cancel-timer pascal1981--idle-timer))
  (setq pascal1981--idle-timer
        (run-with-idle-timer pascal1981-idle-delay nil
                             (lambda (buf)
                               (when (buffer-live-p buf)
                                 (with-current-buffer buf
                                   (pascal1981--refresh-caches)
                                   (pascal1981--apply-token-highlighting))))
                             (current-buffer))))

;; -------------------------------------------------------------------
;; Syntax table
;; -------------------------------------------------------------------

(defvar pascal1981-mode-syntax-table
  (let ((st (make-syntax-table)))
    ;; '_' is part of words (IDENTIFIER)
    (modify-syntax-entry ?_ "w" st)
    ;; ''' delimits string/char literals; doubled '' is escaped —
    ;; Emacs' string syntax handles the common case; the lexer is
    ;; still the authority for highlighting.
    (modify-syntax-entry ?' "\"" st)
    ;; { ... }  comment (brace, style a)
    (modify-syntax-entry ?{ "<" st)
    (modify-syntax-entry ?} ">" st)
    ;; (* ... *)  comment (paren-star, style b).
    ;; Matching char must be the partner paren; ")4" would match ?4.
    (modify-syntax-entry ?\( "()1b" st)
    (modify-syntax-entry ?\) ")(4b" st)
    (modify-syntax-entry ?* ". 23b" st)
    st)
  "Syntax table for `pascal1981-mode'.")

;; -------------------------------------------------------------------
;; Comment handling + font-lock fallback (used when lexer unavailable)
;; -------------------------------------------------------------------

(defconst pascal1981--font-lock-keywords-fallback
  (let* ((kw (regexp-opt pascal1981--keyword-kinds 'words))
         (ty (regexp-opt pascal1981--type-kinds 'words)))
    `((,kw . font-lock-keyword-face)
      (,ty . font-lock-type-face)
      ("\\b[0-9]+#[0-9A-Fa-f]+\\b" . font-lock-constant-face)
      ("\\b[0-9]+\\.[0-9]+\\([eE][+-]?[0-9]+\\)?\\b" . font-lock-constant-face)
      ("\\b[0-9]+\\b" . font-lock-constant-face)
      ("'[^']*'" . font-lock-string-face)))
  "Fallback `font-lock-keywords' when lexer output is unavailable.")

(defconst pascal1981--font-lock-keywords
  `((pascal1981--font-lock-from-tokens)
    ,@pascal1981--font-lock-keywords-fallback)
  "Font-lock keywords: token matcher first, then the regex fallback.")

;; -------------------------------------------------------------------
;; Indentation  (token-driven with optional AST assist)
;; -------------------------------------------------------------------

(defcustom pascal1981-indent-width 2
  "Indentation width for `pascal1981-mode'."
  :type 'integer :group 'pascal1981)

(defconst pascal1981--indent-block-openers
  '("BEGIN" "RECORD" "REPEAT")
  "Keywords that open a block until END or UNTIL.")

(defconst pascal1981--indent-block-closers
  '("END" "UNTIL")
  "Keywords that close a BEGIN/RECORD/REPEAT/CASE block.")

(defconst pascal1981--indent-hangers
  '("THEN" "DO" "ELSE")
  "Keywords that indent the next line only, and only if they end the line.")

(defconst pascal1981--indent-comment-kinds
  '("LINE_COMMENT" "BLOCK_COMMENT")
  "Token kinds ignored when computing indent.")

(defconst pascal1981--indent-decl-starters
  '("CONST" "TYPE" "VAR" "VALUE" "LABEL")
  "Declaration-section keywords.  A following identifier sets the align column.")

(defconst pascal1981--indent-decl-breakers
  '("PROCEDURE" "FUNCTION" "BEGIN" "END" "PROGRAM" "MODULE"
    "INTERFACE" "IMPLEMENTATION")
  "Keywords that leave a declaration section.")

(defun pascal1981--token-kind (tok)
  "Return the kind string of TOK."
  (alist-get 'kind tok))

(defun pascal1981--significant-p (tok)
  "Non-nil when TOK is not a comment."
  (not (member (pascal1981--token-kind tok) pascal1981--indent-comment-kinds)))

(defun pascal1981--tokens-before-line (line)
  "Return list of tokens strictly before LINE from `pascal1981--token-cache'."
  (when pascal1981--token-cache
    (cl-loop for tok across pascal1981--token-cache
             when (< (alist-get 'line tok) line)
             collect tok)))

(defun pascal1981--tokens-on-line (line)
  "Return list of tokens on LINE from `pascal1981--token-cache'."
  (when pascal1981--token-cache
    (cl-loop for tok across pascal1981--token-cache
             when (= (alist-get 'line tok) line)
             collect tok)))

(defun pascal1981--last-significant (toks)
  "Last non-comment token in TOKS, or nil."
  (car (last (cl-remove-if-not #'pascal1981--significant-p toks))))

(defun pascal1981--first-significant (toks)
  "First non-comment token in TOKS, or nil."
  (cl-find-if #'pascal1981--significant-p toks))

(defun pascal1981--compute-indent (line)
  "Compute desired indentation for LINE (1-indexed).
Block depth comes from BEGIN/RECORD/REPEAT and from CASE...OF.
THEN/DO/ELSE indent the next line only when they end that line.
SET OF / ARRAY OF do not indent.  Names after VAR/CONST/TYPE align
to the first identifier of that section."
  (if (null pascal1981--token-cache)
      0
    (let ((depth 0)
          (case-pending nil)
          (decl-align nil))
      (dolist (tok (pascal1981--tokens-before-line line))
        (when (pascal1981--significant-p tok)
          (let ((k (pascal1981--token-kind tok)))
            (cond
             ((member k pascal1981--indent-decl-starters)
              (setq decl-align 'pending))
             ((and (eq decl-align 'pending) (equal k "IDENTIFIER"))
              (setq decl-align (1- (alist-get 'column tok))))
             ((member k pascal1981--indent-decl-breakers)
              (setq decl-align nil)))
            (cond
             ((equal k "CASE")
              (setq case-pending t))
             ((equal k "OF")
              (when case-pending
                (cl-incf depth)
                (setq case-pending nil)))
             ((member k pascal1981--indent-block-openers)
              (cl-incf depth)
              (setq case-pending nil))
             ((member k pascal1981--indent-block-closers)
              (cl-decf depth)
              (setq case-pending nil))))))
      (let* ((here (pascal1981--tokens-on-line line))
             (first (pascal1981--first-significant here))
             (first-kind (and first (pascal1981--token-kind first)))
             (prev (pascal1981--last-significant
                    (pascal1981--tokens-on-line (1- line))))
             (prev-kind (and prev (pascal1981--token-kind prev)))
             (hang (and (member prev-kind pascal1981--indent-hangers)
                        (not (member first-kind
                                     (append pascal1981--indent-block-openers
                                             pascal1981--indent-block-closers
                                             '("ELSE")))))))
        (when (member first-kind pascal1981--indent-block-closers)
          (cl-decf depth))
        (cond
         ((member first-kind (append pascal1981--indent-decl-starters
                                     pascal1981--indent-decl-breakers))
          (max 0 (* depth pascal1981-indent-width)))
         ((and (numberp decl-align) (not hang))
          decl-align)
         ((and (eq decl-align 'pending) (not hang))
          (max 0 (* (+ depth 1) pascal1981-indent-width)))
         (t (max 0 (* (+ depth (if hang 1 0)) pascal1981-indent-width))))))))

(defun pascal1981-indent-line ()
  "Indent current line as Pascal 1981 code."
  (interactive)
  (let* ((line (line-number-at-pos))
         (want (pascal1981--compute-indent line))
         (cur  (current-indentation)))
    (unless (= want cur)
      (save-excursion (indent-line-to want)))
    (when (< (current-column) want) (move-to-column want))))

;; -------------------------------------------------------------------
;; AST helpers + imenu
;; -------------------------------------------------------------------

(defun pascal1981--ast-block-decls (ast)
  "Return decls vector from AST's block, or nil."
  (when ast
    (let* ((blk (alist-get 'block ast)))
      (when blk (alist-get 'decls blk)))))

(defun pascal1981--decl-names (decl)
  "Return the list of names DECL declares, or nil.
A VarDecl holds a `names' vector.  `VAR X, YY: INTEGER;' is one
VarDecl with two names, and each name is its own imenu entry."
  (let ((ty (alist-get '__node_type__ decl)))
    (cond
     ((member ty '("VarDecl"))
      (cl-remove-if-not #'stringp (append (alist-get 'names decl) nil)))
     ((member ty '("ConstDecl" "TypeDecl")) (list (alist-get 'name decl)))
     ((member ty '("ProcDecl" "FuncDecl" "ProcedureDecl" "FunctionDecl"
                  "ProcedureHeader" "FunctionHeader"))
      (list (alist-get 'name decl)))
     (t (list (or (alist-get 'name decl) ty))))))

(defun pascal1981--token-pos (tok)
  "Buffer position of token alist TOK, or nil if it is off-buffer."
  (when tok
    (let* ((line (alist-get 'line tok))
           (col  (alist-get 'column tok)))
      (when (and line col)
        (pascal1981--line-col-pos line col)))))

(defun pascal1981--name-pos (name)
  "Position of the first IDENTIFIER token whose lexeme is NAME."
  (when (and name pascal1981--token-cache)
    (cl-loop for tok across pascal1981--token-cache
             when (and (equal (alist-get 'kind tok) "IDENTIFIER")
                        (equal (alist-get 'lexeme tok) name))
             return (pascal1981--token-pos tok))))

(defun pascal1981-imenu-index ()
  "Build imenu index from `pascal1981--ast-cache' or by re-parsing."
  (unless pascal1981--ast-cache (pascal1981--refresh-caches))
  (when pascal1981--ast-cache
    (let ((decls (pascal1981--ast-block-decls pascal1981--ast-cache)))
      (when decls
        (cl-loop for d across decls
                 append (cl-loop for nm in (pascal1981--decl-names d)
                                 when (and nm (stringp nm))
                                 collect (cons nm (or (pascal1981--name-pos nm)
                                                      (point-min)))))))))

;; -------------------------------------------------------------------
;; Diagnostics  (flycheck / flymake friendly)
;; -------------------------------------------------------------------

(defun pascal1981-check-buffer ()
  "Check current buffer via lexer | parser pipeline.
Return nil on success, or an error string on failure."
  (interactive)
  (let* ((res (pascal1981-parse-string
               (buffer-substring-no-properties (point-min) (point-max))))
         (err (when (eq (car res) 'error) (cdr res))))
    (when (called-interactively-p 'interactive)
      (message "%s" (or err "No parser errors")))
    err))

(defun pascal1981--flycheck-start (checker callback)
  "Flycheck start function for `pascal1981'.
CHECKER and CALLBACK are the flycheck start-function arguments."
  (let ((err (pascal1981-check-buffer)))
    (funcall callback
             (if (null err)
                 'finished
               (list (funcall (intern "flycheck-error-new-at")
                              1 1 'error err :checker checker))))))

;; Flycheck is optional.  The checker is registered only when the
;; package is already loaded so byte-compilation does not choke on
;; the `flycheck-define-checker' macro.
(when (fboundp 'flycheck-define-checker)
  (eval
   '(progn
      (flycheck-define-checker pascal1981-lexer-parser
        "Native Pascal 1981 syntax checker (lexer | parser)."
        :command ("sh" "-c" "lexer | parser 2>&1")
        :standard-input t
        :error-patterns ((error line-start (message) line-end))
        :modes (pascal1981-mode))
      (add-to-list 'flycheck-checkers 'pascal1981-lexer-parser))))

;; -------------------------------------------------------------------
;; Major mode definition
;; -------------------------------------------------------------------

;;;###autoload
(define-derived-mode pascal1981-mode prog-mode "Pascal1981"
  "Major mode for Native Pascal 1981."
  :syntax-table pascal1981-mode-syntax-table
  (setq-local comment-start "{"
                comment-end "}"
                comment-start-skip "{\\|(\\*"
                font-lock-defaults '(pascal1981--font-lock-keywords)
                indent-line-function #'pascal1981-indent-line
                imenu-create-index-function #'pascal1981-imenu-index)
  ;; Trigger initial lex/parse and hook up idle refresh.
  (pascal1981--refresh-caches)
  (pascal1981--apply-token-highlighting)
  (add-hook 'after-change-functions (lambda (&rest _) (pascal1981--schedule-refresh)) nil t))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.pas\\'" . pascal1981-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.inc\\'" . pascal1981-mode))

(provide 'pascal1981-mode)
;;; pascal1981-mode.el ends here
