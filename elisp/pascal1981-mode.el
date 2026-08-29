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
(require 'url)
(require 'url-http)

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
  "Seconds to debounce highlighting / indentation refreshes."
  :type 'number :group 'pascal1981)

(defcustom pascal1981-refresh-timeout 5
  "Maximum seconds allowed for one asynchronous lexer or parser stage."
  :type 'number :group 'pascal1981)

(defcustom pascal1981-completion-enabled nil
  "If non-nil, TAB at end-of-line requests an LLM completion.

The completion proxy's lifecycle is out-of-band from Emacs: the
user starts and stops it themselves.  Emacs never spawns,
health-checks, or supervises the proxy process; it only ever
speaks HTTP to whatever is already listening at
`pascal1981-completion-proxy-url'.  If nothing is listening,
requests simply fail (timeout / connection-refused) and TAB
falls back to indentation."
  :type 'boolean :group 'pascal1981)

(defcustom pascal1981-completion-proxy-url "http://127.0.0.1:8790/complete"
  "URL of the local completion proxy's `/complete' endpoint."
  :type 'string :group 'pascal1981)

(defcustom pascal1981-completion-debug-log nil
  "When non-nil, log completion requests to `*pascal1981-completion-log*'.

Each record identifies the request, source buffer, modification tick, and
point.  This is diagnostic instrumentation for correlating Emacs requests
with completion-proxy or LLM-call logs."
  :type 'boolean :group 'pascal1981)

(defcustom pascal1981-completion-goal
  "Continue this Pascal 1981 program plausibly toward a correct, complete, idiomatic finish."
  "Goal text sent to the completion proxy with each request, as a leading
comment ahead of the buffer (see `pascal1981--completion-payload' and
the proxy's `build_prompt').

This exact wording is deliberate, not a placeholder: the mode's prior
default (\"Complete the Pascal source at point with the smallest
correct insertion.\") was found, live, to reliably break LLM1 on at
least one realistic buffer -- retyping the entire program from its
`PROGRAM' header instead of continuing from the cursor, or exhausting
its reasoning budget outright, in 5 of 6 trials on that buffer. Neither
omitting the goal field entirely nor this replacement wording (the
completion corpus's own goal-comment style, now at
tests/proxy/corpus/, validated at full-corpus scale) reproduced that failure in the same isolated A/B test. The
proxy's own full-corpus validation of its system prompt never covered
elisp's old default wording at all -- only the corpus's own per-item
goal text -- so that specific combination was shipped unvalidated.
Changing this default away from the corpus-validated style again
should not be done without re-testing it the same way."
  :type 'string :group 'pascal1981)

(defcustom pascal1981-completion-timeout 20
  "Seconds to wait for the completion proxy before giving up.

Paired with the proxy's own `--upstream-timeout' (same default, 20).
Keep the two equal; this side must never be the shorter of the pair.
It used to be -- this defaulted to 8 while the proxy's upstream budget
ran to 20 -- so every slow request died here with a blind \"timed
out\": the proxy's own diagnosis of what went wrong never reached the
user, and its forked child went on holding the upstream call open
after Emacs had already walked away.

The wait is actually this value plus `pascal1981--completion-timeout-
grace', so that at equal settings the proxy's own error response wins
the race rather than the two deadlines expiring together."
  :type 'number :group 'pascal1981)

(defconst pascal1981--completion-timeout-grace 2
  "Seconds added to `pascal1981-completion-timeout' before giving up.

Not a user knob: it exists only so the client's deadline sits strictly
after the proxy's identical one, leaving room for the proxy to notice
its own upstream timeout and send a 502 that says so. Without it, two
equal deadlines race and the user gets the less informative of the two
outcomes about half the time.")

(defcustom pascal1981-completion-max-chars 8192
  "Reject a completion longer than this many characters.

Independent backstop against the proxy's own `_MAX_COMPLETION_CHARS'
cap, not a duplicate of it: this mode speaks HTTP to whatever is
listening at `pascal1981-completion-proxy-url', which need not be the
bundled proxy at all, and a runaway completion becomes an overlay
`after-string' that stalls redisplay for the whole editor before the
user can do anything about it.  Deliberately generous -- 30 lines of
Pascal rarely exceeds 1500 characters."
  :type 'integer :group 'pascal1981)

(defcustom pascal1981-completion-buffer-limit 65536
  "Maximum size, in characters, of what is actually sent to the completion
proxy for one request -- the whole buffer when it fits under
`pascal1981-completion-lexical-unit-threshold', or the sliced lexical
unit otherwise (see that variable). If even the chosen text still
exceeds this, nothing is sent; TAB falls back to indentation instead."
  :type 'integer :group 'pascal1981)

(defcustom pascal1981-completion-lexical-unit-threshold 4000
  "Buffer size, in characters, above which a completion request sends
only the innermost enclosing PROCEDURE/FUNCTION body around point (plus
the top-level declarations), instead of the whole buffer.

This exists so a large file does not have to fit `pascal1981-completion-
buffer-limit' in its entirety just to get a completion somewhere inside
it: only the relevant lexical unit needs to fit. If point is not inside
any PROCEDURE/FUNCTION (e.g. it is in the top-level declarations or main
block), the whole buffer is sent regardless of this threshold -- there is
no unit to slice to. See `pascal1981--completion-enclosing-unit-span'."
  :type 'integer :group 'pascal1981)

(defun pascal1981-completion-toggle ()
  "Toggle `pascal1981-completion-enabled' on or off.

Formerly also took a numeric prefix argument to set a candidate count
for a multi-candidate request; the proxy no longer supports requesting
more than one candidate per request (see `pascal1981-completion-reveal-
more'/`pascal1981-completion-reveal-fewer' for how a single generous
completion is browsed instead), so that prefix-argument behavior is
gone -- this command is now a plain toggle."
  (interactive)
  (setq pascal1981-completion-enabled (not pascal1981-completion-enabled))
  (message "pascal1981: LLM completion %s"
           (if pascal1981-completion-enabled "enabled" "disabled")))

(defvar pascal1981--token-cache nil
  "Buffer-local cache of last lexer output (vector of alists).")
(make-variable-buffer-local 'pascal1981--token-cache)

(defvar pascal1981--ast-cache nil
  "Buffer-local cache of last parser AST.")
(make-variable-buffer-local 'pascal1981--ast-cache)

(defvar-local pascal1981--idle-timer nil
  "Pending debounced cache-refresh timer for this buffer.")
(defvar-local pascal1981--refresh-process nil
  "Current asynchronous lexer or parser process for this buffer.")
(defvar-local pascal1981--refresh-generation 0
  "Generation number used to discard superseded refresh results.")
(defvar-local pascal1981--refresh-reindent nil
  "(START-LINE END-LINE TICK) for deferred completion reindentation.")
(defvar-local pascal1981--refresh-inhibit nil
  "Non-nil while a refresh-owned edit must not schedule another refresh.")
(defvar-local pascal1981--completion-accept-barrier nil)
(defvar-local pascal1981--completion-accept-tick nil)
(defvar-local pascal1981--completion-accept-point nil)

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
        ;; `call-process-region' signals `file-missing' when PROGRAM is not
        ;; on `exec-path' -- it does not return non-zero.  An uncaught
        ;; signal there escapes every caller, including `pascal1981-mode'
        ;; itself (which refreshes on entry, so visiting any .pas file
        ;; without the stage binaries installed fails outright) and
        ;; `pascal1981--completion-insert' (which refreshes from inside an
        ;; `atomic-change-group', partway through modifying the user's
        ;; buffer).  A missing binary is an ordinary, expected condition --
        ;; the mode's whole fallback story rests on it -- so it is reported
        ;; through the same (error . MESSAGE) channel as any other failure
        ;; rather than raised.
        (let ((exit-code
               (condition-case err
                   (with-temp-buffer
                     (insert stdin-text)
                     (call-process-region (point-min) (point-max)
                                          program nil (list out-buf err-file) nil))
                 (error (format "could not run %s: %s"
                                 program (error-message-string err))))))
          (let ((stdout (with-current-buffer out-buf (buffer-string)))
                (stderr (with-temp-buffer
                          (insert-file-contents err-file)
                          (buffer-string))))
            (cond
             ;; A string exit-code is the condition-case's message above.
             ((stringp exit-code) (cons 'error exit-code))
             ((zerop exit-code)
              (condition-case err
                  (cons 'ok (json-parse-string stdout
                                                :object-type 'alist
                                                :array-type 'array))
                (error (cons 'error (format "JSON parse failed: %s\nraw: %s" err stdout)))))
             (t
              (cons 'error (if (string-empty-p stderr)
                               (format "%s exited %d" program exit-code)
                             stderr))))))
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

(defun pascal1981--refresh-json (program stdin callback)
  "Run PROGRAM asynchronously with STDIN, then call CALLBACK with its result."
  (let ((out (generate-new-buffer " *pascal1981-refresh-out*"))
        (err (generate-new-buffer " *pascal1981-refresh-err*")))
    (condition-case problem
        (let ((proc
               (make-process
                :name (format "pascal1981-%s" program) :buffer out :stderr err
                :command (list program) :connection-type 'pipe :noquery t
                :sentinel
                (lambda (process _event)
                  (when (memq (process-status process) '(exit signal))
                    (let ((timer (process-get process 'pascal1981-timeout)))
                      (when timer (cancel-timer timer)))
                    (let ((status (process-exit-status process))
                          (stdout (with-current-buffer out (buffer-string)))
                          (stderr (with-current-buffer err (buffer-string))))
                      (unwind-protect
                          (funcall callback
                                   (if (zerop status)
                                       (condition-case json-error
                                           (cons 'ok (json-parse-string stdout :object-type 'alist :array-type 'array))
                                         (error (cons 'error (error-message-string json-error))))
                                     (cons 'error (if (string-empty-p stderr)
                                                      (format "%s exited %d" program status)
                                                    stderr))))
                        (kill-buffer out) (kill-buffer err))))))))
          (process-send-string proc stdin)
          (process-send-eof proc)
          (process-put proc 'pascal1981-timeout
                       (run-at-time pascal1981-refresh-timeout nil
                                    (lambda (process)
                                      (when (process-live-p process)
                                        (delete-process process)))
                                    proc))
          proc)
      (error (kill-buffer out) (kill-buffer err)
             (funcall callback (cons 'error (error-message-string problem)))
             nil))))

(defun pascal1981--refresh-apply-lexer (buf generation tick result)
  "Apply lexer RESULT for BUF only if its snapshot is still current."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (when (and (= generation pascal1981--refresh-generation)
                 (= tick (buffer-modified-tick)))
        (if (eq (car result) 'error)
            (setq pascal1981--token-cache nil pascal1981--ast-cache nil)
          (setq pascal1981--token-cache (cdr result))
          (pascal1981--apply-token-highlighting)
          (let ((reindent pascal1981--refresh-reindent))
            (when (and reindent (= tick (nth 2 reindent)))
              (setq pascal1981--refresh-inhibit t)
              (unwind-protect
                  (save-excursion
                    (cl-loop for line from (1+ (nth 0 reindent)) to (nth 1 reindent)
                             do (goto-char (point-min))
                             do (forward-line (1- line))
                             do (pascal1981-indent-line)))
                (setq pascal1981--refresh-inhibit nil
                      pascal1981--refresh-reindent nil))))
          (let ((tokens (json-serialize (cdr result))))
            (setq pascal1981--refresh-process
                  (pascal1981--refresh-json
                   pascal1981-parser-program tokens
                   (lambda (parse-result)
                     (when (and (buffer-live-p buf)
                                (with-current-buffer buf
                                  (and (= generation pascal1981--refresh-generation)
                                       (= tick (buffer-modified-tick)))))
                       (with-current-buffer buf
                         (setq pascal1981--ast-cache
                               (when (eq (car parse-result) 'ok) (cdr parse-result))))))))))))))

(defun pascal1981--refresh-start (buf generation)
  "Start the current asynchronous lexer refresh for BUF."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (when (= generation pascal1981--refresh-generation)
        (let ((tick (buffer-modified-tick))
              (source (buffer-substring-no-properties (point-min) (point-max))))
          (setq pascal1981--refresh-process
                (pascal1981--refresh-json
                 pascal1981-lexer-program source
                 (lambda (result)
                   (pascal1981--refresh-apply-lexer buf generation tick result)))))))))

(defun pascal1981--schedule-refresh ()
  "Debounce an asynchronous cache refresh after `pascal1981-idle-delay'."
  (unless pascal1981--refresh-inhibit
    (cl-incf pascal1981--refresh-generation)
    (when (timerp pascal1981--idle-timer) (cancel-timer pascal1981--idle-timer))
    (let ((buf (current-buffer)) (generation pascal1981--refresh-generation))
      (setq pascal1981--idle-timer
            (run-at-time pascal1981-idle-delay nil
                         #'pascal1981--refresh-start buf generation)))))

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
;; LLM completion
;; -------------------------------------------------------------------

(defun pascal1981--completion-allowed-at-point-p ()
  "Return non-nil when point sits before only whitespace on this line.

This is the TAB eligibility rule: a completion request is only
sent when nothing but spaces or tabs stand between point and the
end of the current line.  A non-whitespace character to the
right of point means TAB keeps its normal indentation behavior
instead."
  (looking-at-p "[ \t]*$"))

(defvar-local pascal1981--completion-request-counter 0
  "Monotonic counter used to mint completion request ids.")

(defvar-local pascal1981--completion-pending-id nil
  "Request id of the in-flight completion request, or nil if none.
A response whose request id no longer matches this is stale and is
discarded unread.")

(defvar-local pascal1981--completion-timeout-timer nil
  "Timer that fires if the current completion request does not answer
within `pascal1981-completion-timeout' seconds.")

(defun pascal1981--completion-line-column ()
  "Return (LINE . COLUMN) at point, 1-based, matching the proxy's scheme.
COLUMN counts characters from the start of the line and a TAB counts
as one column -- the same convention `pascal1981--line-col-pos'
decodes on the way back."
  (cons (line-number-at-pos)
        (1+ (- (point) (line-beginning-position)))))

(defun pascal1981--completion-payload (goal buffer-text line column)
  "Build the JSON request body for a `/complete' request."
  (json-encode `((goal . ,goal)
                 (buffer . ,buffer-text)
                 (cursor . ((line . ,line) (column . ,column))))))

(defun pascal1981--completion-insert (text)
  "Insert TEXT at point as a single atomic undo step.
When TEXT spans multiple lines (the proxy's completions are no longer
capped at one line by default -- see its `--max-lines' flag), the raw
model text carries no reliable indentation of its own.  Reindentation
therefore waits for the next asynchronous lexer refresh; TAB itself
only inserts text and returns.

Two conditions guard that reindent pass, because getting either wrong
damages the user's file rather than merely formatting it oddly:

- The refresh must actually have produced a token cache.
  `pascal1981--compute-indent' answers 0 for every line when
  `pascal1981--token-cache' is nil, so reindenting against a nil cache
  does not leave indentation alone -- it flattens every touched line to
  column 0.  A nil cache here is the expected case, not a remote one:
  the text just inserted came from an LLM, and a partial statement or
  an unbalanced quote is exactly what a low-parameter model produces,
  which is precisely when the lexer fails and the cache goes nil.  The
  same happens whenever the `lexer' binary is simply not on PATH.
  Inserting the model's text unreindented is a small cosmetic loss;
  flattening the surrounding code is not.

- Only lines strictly after START-LINE are touched.  START-LINE holds
  text the user wrote and did not ask to have reindented; the
  completion was inserted at point, partway into it."
  (atomic-change-group
    (let ((start-line (line-number-at-pos)))
      (insert text)
      (when (string-match-p "\n" text)
        ;; The lexer/parser must not run in TAB's command path.  The next
        ;; asynchronous refresh reindents these lines only if this exact edit
        ;; is still current when lexer output arrives.
        (setq pascal1981--refresh-reindent
              (list start-line (line-number-at-pos) nil))))
    (when pascal1981--refresh-reindent
      (setf (nth 2 pascal1981--refresh-reindent) (buffer-modified-tick)))
    (pascal1981--schedule-refresh)))

;; -------------------------------------------------------------------
;; Lexical-unit slicing -- send an enclosing PROCEDURE/FUNCTION instead
;; of the whole buffer once it exceeds
;; `pascal1981-completion-lexical-unit-threshold'.
;; -------------------------------------------------------------------

(defconst pascal1981--block-openers '("RECORD" "BEGIN" "CASE")
  "Token kinds that open a block which a matching END closes.
Shared by `pascal1981--completion-proc-span-end' and
`pascal1981--decl-end-index'.")

(defun pascal1981--completion-proc-span-end (start-index)
  "Return the token-cache index just past the SEMICOLON ending the
PROCEDURE/FUNCTION declaration starting at token index START-INDEX (its
own `PROCEDURE'/`FUNCTION' token), or nil if the cache runs out first.

A naive reuse of `pascal1981--decl-end-index' does NOT give the whole
declaration's span: a procedure header always ends in its own `;'
before any `BEGIN' or further declarations (e.g. `PROCEDURE
Foo(X: INTEGER);' on its own line), so the very first SEMICOLON at
block-depth 0/paren-depth 0 is never the real end by itself -- it
either introduces an EXTERN/EXTERNAL/FORWARD modifier (no body at all,
so the *next* such SEMICOLON is the end), or it introduces the real
body, in which case every further depth-0/paren-0 SEMICOLON before
this procedure's own `BEGIN' belongs to one of ITS declarations
(VAR/CONST/TYPE, or a nested PROCEDURE/FUNCTION's own header) and must
be skipped rather than mistaken for the end. The true end in that case
is the SEMICOLON immediately following the point where block depth,
having gone above 0 at least once, returns to 0.

A genuinely nested PROCEDURE/FUNCTION declaration (one appearing in
this declaration's own decls section, before its own `BEGIN') is NOT
just skipped by depth-tracking alone: its own `BEGIN...END' pair would
otherwise be mistaken for THIS declaration's body boundary, ending the
scan far too early. Such a nested declaration is instead skipped over
as a whole via a recursive call to this same function, jumping the
scan index past its entire span (header through its own trailing `;')
without ever looking at its internal tokens -- each recursive call has
its own independent DEPTH/PAREN/PAST-HEADER/SEEN-OPEN state, so nothing
about a nested declaration's internals can perturb the outer scan."
  (when pascal1981--token-cache
    (let ((depth 0) (paren 0) (i start-index)
          (n (length pascal1981--token-cache))
          (past-header nil) (externp nil) (seen-open nil)
          (found nil))
      (while (and (null found) (< i n))
        (let ((kind (alist-get 'kind (aref pascal1981--token-cache i))))
          (cond
           ((and past-header (not seen-open)
                 (member kind '("PROCEDURE" "FUNCTION")))
            (let ((nested-end (pascal1981--completion-proc-span-end i)))
              (when nested-end (setq i (1- nested-end)))))
           ((member kind pascal1981--block-openers)
            (cl-incf depth) (setq seen-open t))
           ((equal kind "END") (setq depth (max 0 (1- depth))))
           ((equal kind "LPAREN") (cl-incf paren))
           ((equal kind "RPAREN") (setq paren (max 0 (1- paren))))
           ((and (equal kind "SEMICOLON") (= depth 0) (= paren 0))
            (cond
             ((not past-header)
              (setq past-header t)
              (setq externp
                    (and (< (1+ i) n)
                         (member (alist-get 'kind
                                            (aref pascal1981--token-cache (1+ i)))
                                 '("EXTERN" "EXTERNAL" "FORWARD")))))
             (externp (setq found (1+ i)))
             (seen-open (setq found (1+ i)))
             ;; Else: a nested declaration's own SEMICOLON before this
             ;; procedure's own BEGIN -- ignore it, keep scanning.
             ))))
        (setq i (1+ i)))
      found)))

(defun pascal1981--completion-enclosing-unit-span (pos)
  "Return (START . END), the buffer positions of the innermost
PROCEDURE/FUNCTION declaration containing POS, or nil if POS is not
inside any such declaration (e.g. it is in the top-level declarations
or main BEGIN...END). Chooses the smallest containing span when
several nest around POS -- well-formed spans nest cleanly, so this is
enough to find the innermost one without building an explicit tree."
  (when pascal1981--token-cache
    (let ((best nil) (best-width nil)
          (n (length pascal1981--token-cache)))
      (cl-loop for i from 0 below n
               for tok = (aref pascal1981--token-cache i)
               when (member (alist-get 'kind tok) '("PROCEDURE" "FUNCTION"))
               do (let* ((start (pascal1981--token-pos tok))
                         (end-index (pascal1981--completion-proc-span-end i))
                         (end (if (and end-index (< end-index n))
                                  (pascal1981--token-pos
                                   (aref pascal1981--token-cache end-index))
                                (point-max))))
                    (when (and start end (<= start pos) (<= pos end))
                      (let ((width (- end start)))
                        (when (or (null best-width) (< width best-width))
                          (setq best (cons start end) best-width width))))))
      best)))

(defun pascal1981--completion-toplevel-decls-end ()
  "Position just before the first top-level PROCEDURE, FUNCTION, or
BEGIN token -- i.e. the end of the PROGRAM header plus any top-level
CONST/TYPE/VAR/LABEL declarations. Nothing can be nested before the
very first occurrence of any of these three kinds, so no depth
tracking is needed. Returns `point-max' if the token cache is empty or
none of these kinds ever occurs."
  (if pascal1981--token-cache
      (let ((tok (cl-find-if
                  (lambda (tok)
                    (member (alist-get 'kind tok)
                            '("PROCEDURE" "FUNCTION" "BEGIN")))
                  pascal1981--token-cache)))
        (if tok (pascal1981--token-pos tok) (point-max)))
    (point-max)))

(defun pascal1981--completion-build-slice (unit-start unit-end orig-point)
  "Build (TEXT . (LINE . COLUMN)) for a lexical-unit slice: the
top-level declarations (`pascal1981--completion-toplevel-decls-end')
followed by the buffer text from UNIT-START to UNIT-END, with
LINE/COLUMN computed relative to that combined text at ORIG-POINT
(which must lie within [UNIT-START, UNIT-END]).

Builds LINE/COLUMN by reusing `pascal1981--completion-line-column'
inside a scratch `with-temp-buffer' at exactly the inserted position
that corresponds to ORIG-POINT, rather than computing the offset by
hand -- the temp buffer's own notion of \"where point is\" already
matches what is needed once the text is assembled in the same order
it will be sent."
  (let ((decls-text (buffer-substring-no-properties
                      (point-min) (pascal1981--completion-toplevel-decls-end)))
        (before (buffer-substring-no-properties unit-start orig-point))
        (after (buffer-substring-no-properties orig-point unit-end)))
    (with-temp-buffer
      (insert decls-text)
      (unless (bolp) (insert "\n"))
      (insert before)
      (let ((line-column (pascal1981--completion-line-column)))
        (insert after)
        (cons (buffer-string) line-column)))))

(defun pascal1981--completion-request-text ()
  "Return (TEXT . (LINE . COLUMN)) to send for a `/complete' request at
point: the whole buffer when its size is at or under
`pascal1981-completion-lexical-unit-threshold'; above that, the
innermost enclosing PROCEDURE/FUNCTION's text plus the top-level
declarations (see `pascal1981--completion-enclosing-unit-span' and
`pascal1981--completion-build-slice'), with LINE/COLUMN adjusted to be
relative to that slice. Falls back to the whole buffer when no
enclosing unit is found (point is at the top level) or the token cache
is unavailable -- a crude line-window slice was considered and
rejected as more likely to produce a confusing or invalid excerpt than
a clean procedure-boundary one."
  (if (<= (buffer-size) pascal1981-completion-lexical-unit-threshold)
      (cons (buffer-substring-no-properties (point-min) (point-max))
            (pascal1981--completion-line-column))
    (let ((span (pascal1981--completion-enclosing-unit-span (point))))
      (if span
          (pascal1981--completion-build-slice (car span) (cdr span) (point))
        (cons (buffer-substring-no-properties (point-min) (point-max))
              (pascal1981--completion-line-column))))))

(defun pascal1981--completion-oversized-p (&optional request-text)
  "Non-nil when what `pascal1981--completion-request-text' would send
for point right now exceeds `pascal1981-completion-buffer-limit'.

REQUEST-TEXT is that function's (TEXT . (LINE . COLUMN)) result,
computed afresh when not supplied.  Callers pass it in so the answer
and the request that follows it share one computation: building it
scans the token cache and may slice out an enclosing lexical unit, and
every TAB used to do all of that twice -- once to decide, once to
send."
  (> (length (car (or request-text (pascal1981--completion-request-text))))
     pascal1981-completion-buffer-limit))

;; -------------------------------------------------------------------
;; Ghost-text preview + line reveal
;; -------------------------------------------------------------------

(defvar-local pascal1981--completion-overlay nil
  "Overlay showing the current completion preview, or nil if none.")

(defvar-local pascal1981--completion-text nil
  "Full text of the completion currently being previewed, or nil.
The proxy returns exactly one completion per request; instead of
cycling between several distinct candidates, `M-n'/`M-p' reveal more
or fewer of this single completion's lines -- see
`pascal1981--completion-reveal-lines'.")

(defvar-local pascal1981--completion-reveal-lines 1
  "How many lines of `pascal1981--completion-text' are currently shown.
Starts at 1 for a new preview; stepped by `pascal1981-completion-
reveal-more'/`pascal1981-completion-reveal-fewer' through the
deduplicated Fibonacci-spaced counts from `pascal1981--completion-
fib-steps'.")

(defun pascal1981--completion-text-lines ()
  "Return `pascal1981--completion-text' split into lines, or nil."
  (when pascal1981--completion-text
    (split-string pascal1981--completion-text "\n")))

(defun pascal1981--completion-visible-text ()
  "Return the currently revealed prefix of the completion text."
  (let ((lines (pascal1981--completion-text-lines)))
    (when lines
      (mapconcat #'identity
                 (cl-subseq lines 0 (min pascal1981--completion-reveal-lines
                                         (length lines)))
                 "\n"))))

(defun pascal1981--completion-fib-steps (total)
  "Deduplicated Fibonacci-spaced positive integers up to and including
TOTAL, always ending with TOTAL, e.g. TOTAL=7 -> (1 2 3 5 7). The raw
Fibonacci sequence's repeated leading 1, 1 is collapsed to a single 1,
since two consecutive `M-n' keystrokes revealing the same line count
would be a no-op. Return nil when TOTAL <= 0."
  (when (> total 0)
    (let ((raw nil) (a 1) (b 1))
      (while (<= a total)
        (push a raw)
        (let ((next (+ a b))) (setq a b b next)))
      (setq raw (delete-dups (nreverse raw)))
      (if (= (car (last raw)) total)
          raw
        (append raw (list total))))))

(defun pascal1981--completion-overlay-live-p ()
  "Non-nil when a completion preview is showing at point."
  (and pascal1981--completion-overlay
       (overlay-buffer pascal1981--completion-overlay)
       (= (overlay-start pascal1981--completion-overlay) (point))))

(defun pascal1981--completion-render-overlay ()
  "Refresh the overlay's `after-string' from the currently revealed lines."
  (let* ((total (length (pascal1981--completion-text-lines)))
         (visible (pascal1981--completion-visible-text))
         (suffix (if (> total 1)
                     (format " [%d/%d lines]"
                             (min pascal1981--completion-reveal-lines total)
                             total)
                   "")))
    (overlay-put pascal1981--completion-overlay 'after-string
                 (propertize (concat visible suffix) 'face 'shadow))))

(defun pascal1981--completion-dismiss ()
  "Remove the completion preview overlay and clear its state.
Safe to call when no preview is showing."
  (interactive)
  (when pascal1981--completion-overlay
    (delete-overlay pascal1981--completion-overlay))
  (setq pascal1981--completion-overlay nil
        pascal1981--completion-text nil
        pascal1981--completion-reveal-lines 1))

(defun pascal1981--completion-do-accept ()
  "Materialize the currently revealed portion of the preview at point.
Inserted as a single atomic undo step via `pascal1981--completion-insert'.
Only the lines currently shown are inserted, not the whole completion --
what you see is what you get, the same as accepting a partially-cycled
candidate used to be under the old multi-candidate scheme.

This is called from the completion-preview transient map's on-exit
handler (see `pascal1981--completion-show-ghost'), not run directly as
the command TAB is bound to. `set-transient-map' evaluates its
KEEP-PRED, and therefore calls ON-EXIT when the map is not kept, from
`pre-command-hook' -- which runs BEFORE the triggering command itself
is invoked. A command bound to TAB that tried to do this work in its
own body would see the overlay and preview state already cleared by
a naively unconditional on-exit dismiss; doing the real work from
inside on-exit itself, while the state is still live, avoids that
race entirely."
  (when (pascal1981--completion-overlay-live-p)
    (let ((text (pascal1981--completion-visible-text)))
      (pascal1981--completion-dismiss)
      (when text
        (setq pascal1981--completion-accept-barrier t)
        (pascal1981--completion-insert text)
        ;; Insertion runs `after-change-functions', which deliberately
        ;; clears barriers for ordinary user edits.  Reinstate this one:
        ;; it represents the acceptance command, not a subsequent edit.
        (setq pascal1981--completion-accept-barrier t
              pascal1981--completion-accept-tick (buffer-modified-tick)
              pascal1981--completion-accept-point (point))
        (redisplay)))))

(defun pascal1981--completion-accept ()
  "Bound to TAB in the completion-preview transient map.
Intentionally a no-op: the actual materialization happens in
`pascal1981--completion-do-accept', run from the transient map's
on-exit handler instead of from this command's own body -- see that
function's docstring for why."
  (interactive))

(defvar-local pascal1981--completion-transient-exit nil
  "Function that retires the preview's transient map, or nil if none.
`set-transient-map' returns this; keeping it lets a new preview take
down the previous preview's map instead of stacking on top of it.")

(defun pascal1981--completion-show-ghost (text)
  "Show TEXT (a single completion string) as a line-revealable preview
at point, starting with just its first line shown."
  (pascal1981--completion-dismiss)
  ;; Retire any previous preview's transient map before installing this
  ;; one.  Two maps stacked, and the older one's on-exit handler then ran
  ;; on the next keystroke and dismissed *this* preview -- so a second
  ;; completion arriving while a first was showing would vanish the
  ;; moment the user pressed `M-n'.
  (when (functionp pascal1981--completion-transient-exit)
    (funcall pascal1981--completion-transient-exit)
    (setq pascal1981--completion-transient-exit nil))
  (setq pascal1981--completion-text text
        pascal1981--completion-reveal-lines 1
        pascal1981--completion-overlay (make-overlay (point) (point) nil t nil))
  (pascal1981--completion-render-overlay)
  (setq pascal1981--completion-transient-exit
   (set-transient-map
   (let ((map (make-sparse-keymap)))
     (define-key map (kbd "TAB") #'pascal1981--completion-accept)
     (define-key map (kbd "<tab>") #'pascal1981--completion-accept)
     (define-key map (kbd "M-n") #'pascal1981-completion-reveal-more)
     (define-key map (kbd "M-p") #'pascal1981-completion-reveal-fewer)
     (define-key map (kbd "C-g") #'pascal1981--completion-dismiss)
     map)
   (lambda () (memq this-command '(pascal1981-completion-reveal-more
                                    pascal1981-completion-reveal-fewer)))
   (lambda ()
     (setq pascal1981--completion-transient-exit nil)
     (if (eq this-command #'pascal1981--completion-accept)
         (pascal1981--completion-do-accept)
       (pascal1981--completion-dismiss))))))

(defun pascal1981-completion-reveal-more ()
  "Show more of the current completion preview.
Steps `pascal1981--completion-reveal-lines' forward through the
deduplicated Fibonacci-spaced counts from
`pascal1981--completion-fib-steps', capped at the completion's total
line count."
  (interactive)
  (pascal1981--completion-reveal-step 1))

(defun pascal1981-completion-reveal-fewer ()
  "Show fewer lines of the current completion preview.
Steps `pascal1981--completion-reveal-lines' backward through the same
schedule as `pascal1981-completion-reveal-more', down to a minimum of
one line."
  (interactive)
  (pascal1981--completion-reveal-step -1))

(defun pascal1981--completion-reveal-step (direction)
  "Move `pascal1981--completion-reveal-lines' one Fibonacci step in
DIRECTION (1 for more, -1 for fewer), then redraw."
  (when (pascal1981--completion-overlay-live-p)
    (let* ((total (length (pascal1981--completion-text-lines)))
           (steps (pascal1981--completion-fib-steps total)))
      (when steps
        (let* ((pos (or (cl-position pascal1981--completion-reveal-lines
                                     steps :test #'=)
                        0))
               (new-pos (max 0 (min (1- (length steps)) (+ pos direction)))))
          (setq pascal1981--completion-reveal-lines (nth new-pos steps)))))
    (pascal1981--completion-render-overlay)))

(defun pascal1981--completion-usable-p (text)
  "Non-nil when TEXT is safe to preview and insert into the buffer.

An independent check, not a restatement of the proxy's own
sanitization: this mode speaks HTTP to whatever is listening at
`pascal1981-completion-proxy-url', which need not be the bundled
proxy, so nothing about what arrives can be assumed.  A candidate is
rejected when it

- has no printable content (empty, or only whitespace).  Such a
  candidate used to produce a ghost overlay with an empty
  `after-string', which reads as TAB doing nothing at all;
- exceeds `pascal1981-completion-max-chars'; or
- contains a C0 control character other than newline or tab -- a
  stray carriage return lands in the source as a literal ^M, and an
  ESC begins what the display renders as an escape sequence."
  (and (stringp text)
       (string-match-p "[^ \t\n]" text)
       (<= (length text) pascal1981-completion-max-chars)
       ;; C0 minus tab (9) and newline (10), plus DEL (127).  Note that
       ;; carriage return (13) is inside the rejected range on purpose:
       ;; it is the control character a model is most likely to emit, and
       ;; it lands in the source as a literal ^M.
       (not (string-match-p "[\0-\010\013-\037\177]" text))))

(defun pascal1981--completion-parse-response (response-buffer)
  "Return (STATUS-CODE . CANDIDATES-OR-NIL) parsed from RESPONSE-BUFFER.
CANDIDATES-OR-NIL is a list of usable completion strings, or nil when
the body is not valid JSON with a \"completions\" array holding at
least one string that satisfies `pascal1981--completion-usable-p'.

The body is decoded as UTF-8 before parsing.  `url-retrieve' hands its
callback the raw response bytes, so `json-read' over them yields
unibyte strings: any non-ASCII in a completion -- in a comment, or a
string literal -- would otherwise be inserted into a multibyte buffer
as mojibake rather than as the characters the model actually sent."
  (with-current-buffer response-buffer
    (let ((status-code (url-http-symbol-value-in-buffer
                         'url-http-response-status response-buffer)))
      (goto-char (if (boundp 'url-http-end-of-headers)
                     (or url-http-end-of-headers (point-min))
                   (point-min)))
      (let* ((body-text (buffer-substring-no-properties (point) (point-max)))
             (decoded (decode-coding-string
                       (if (multibyte-string-p body-text)
                           (encode-coding-string body-text 'utf-8)
                         body-text)
                       'utf-8))
             (body (ignore-errors
                     (json-parse-string decoded
                                        :object-type 'alist
                                        :array-type 'list)))
             ;; `ignore-errors' because BODY need not be an alist at all:
             ;; a JSON array parses to a list whose elements are not
             ;; conses, and `alist-get' signals on that rather than
             ;; answering nil.
             (completions (ignore-errors
                            (and (listp body) (alist-get 'completions body))))
             (usable (and (listp completions)
                          (cl-remove-if-not #'pascal1981--completion-usable-p
                                            completions))))
        (cons status-code usable)))))

(defun pascal1981--completion-handle-timeout (source-buffer request-id
                                                              response-buffer)
  "Fire when REQUEST-ID has not answered within the configured timeout.
Reports the timeout to the user (if the request is still current) and
tears down the still-open connection."
  (when (buffer-live-p source-buffer)
    (with-current-buffer source-buffer
      (when (eq pascal1981--completion-pending-id request-id)
        (setq pascal1981--completion-pending-id nil
              pascal1981--completion-timeout-timer nil)
        (message "pascal1981: completion request timed out"))))
  (when (buffer-live-p response-buffer)
    (let ((proc (get-buffer-process response-buffer)))
      (when proc (delete-process proc)))
    (when (buffer-live-p response-buffer)
      (kill-buffer response-buffer))))

(defun pascal1981--completion-callback (status source-buffer request-id
                                                point-at-request
                                                tick-at-request)
  "`url-retrieve' callback for completion REQUEST-ID.
STATUS is the plist url.el passes on completion/error. Show the
completion(s) as a ghost-text preview only if SOURCE-BUFFER still
exists, completion is still enabled there, REQUEST-ID is still the
pending one (a stale response is discarded silently -- it already
lost the race, no message needed), the buffer is unchanged since
TICK-AT-REQUEST, point is still POINT-AT-REQUEST, and the eligibility
rule still holds there."
  (let ((response-buffer (current-buffer)))
    (unwind-protect
        (catch 'pascal1981--completion-done
          (unless (buffer-live-p source-buffer)
            (throw 'pascal1981--completion-done nil))
          (with-current-buffer source-buffer
            (when (timerp pascal1981--completion-timeout-timer)
              (cancel-timer pascal1981--completion-timeout-timer)
              (setq pascal1981--completion-timeout-timer nil))
            (unless (eq pascal1981--completion-pending-id request-id)
              (throw 'pascal1981--completion-done nil))
            (setq pascal1981--completion-pending-id nil)
            (unless pascal1981-completion-enabled
              (throw 'pascal1981--completion-done nil)))
          (when (plist-get status :error)
            (message "pascal1981: completion request failed: %s"
                      (plist-get status :error))
            (throw 'pascal1981--completion-done nil))
          (let* ((parsed (pascal1981--completion-parse-response response-buffer))
                 (status-code (car parsed))
                 (candidates (cdr parsed)))
            ;; A nil status is a failure, not a success: it means url.el
            ;; never recorded a response status for this buffer at all.
            ;; Treating nil as "not an error" let a body that never came
            ;; from a real HTTP response fall through to be parsed.
            (unless (eql status-code 200)
              (message "pascal1981: completion proxy returned HTTP %s"
                        (or status-code "no response"))
              (throw 'pascal1981--completion-done nil))
            (unless candidates
              (message "pascal1981: no usable completion")
              (throw 'pascal1981--completion-done nil))
            (with-current-buffer source-buffer
              (unless (and pascal1981-completion-enabled
                            (= (buffer-modified-tick) tick-at-request)
                            (= (point) point-at-request)
                            (pascal1981--completion-allowed-at-point-p))
                (throw 'pascal1981--completion-done nil))
              (pascal1981--completion-show-ghost (car candidates)))))
      (when (buffer-live-p response-buffer)
        (kill-buffer response-buffer)))))

(defun pascal1981--completion-send (&optional request-text)
  "Send an asynchronous `/complete' request for the current buffer/point.
Captures the source buffer, point, buffer modification tick, and
1-based line/column before sending; `pascal1981--completion-callback'
re-validates all of it before inserting anything, so a response that
arrives after the buffer changed underneath it is discarded rather
than inserted somewhere it no longer belongs.

REQUEST-TEXT is the (TEXT . (LINE . COLUMN)) pair from
`pascal1981--completion-request-text', computed afresh when not
supplied.  Callers that already had to build it in order to decide
whether to call at all -- checking the size limit means building it --
pass it through instead of paying for the token-cache scan and the
slicing a second time.

Does nothing when a request for this buffer is already in flight.
Every TAB used to fire its own request; the bundled proxy forks per
connection and accepts them all, so a held-down TAB piled a queue of
requests onto a backend that serves one at a time, and the whole queue
then timed out.  Only the newest response could ever have been used
anyway -- the rest lose the request-id race below and are discarded
unread -- so the earlier ones were never anything but load."
  (if pascal1981--completion-pending-id
      (message "pascal1981: a completion request is already in flight")
    (pascal1981--completion-send-1 (or request-text
                                       (pascal1981--completion-request-text)))))

(defun pascal1981--completion-log-send (source-buffer request-id tick point line-column)
  "Log completion request diagnostics when `pascal1981-completion-debug-log' is set."
  (when pascal1981-completion-debug-log
    (with-current-buffer (get-buffer-create "*pascal1981-completion-log*")
      (goto-char (point-max))
      (insert (format "SEND time=%.6f request=%d buffer=%S tick=%d point=%d line=%d column=%d\n"
                      (float-time) request-id (buffer-name source-buffer) tick point
                      (car line-column) (cdr line-column))))))

(defun pascal1981--completion-send-1 (request-text)
  "Unconditionally send a `/complete' request for REQUEST-TEXT.
See `pascal1981--completion-send', which is the entry point that
applies the in-flight guard."
  (let* ((source-buffer (current-buffer))
         (request-id (cl-incf pascal1981--completion-request-counter))
         (point-at-request (point))
         (tick-at-request (buffer-modified-tick))
         (buffer-text (car request-text))
         (line-column (cdr request-text))
         (url-request-method "POST")
         (url-request-extra-headers '(("Content-Type" . "application/json")))
         (url-request-data
          (encode-coding-string
           (pascal1981--completion-payload
            pascal1981-completion-goal buffer-text
            (car line-column) (cdr line-column))
           'utf-8)))
    (pascal1981--completion-log-send source-buffer request-id tick-at-request
                                     point-at-request line-column)
    (setq pascal1981--completion-pending-id request-id)
    (letrec ((response-buffer
              ;; `url-retrieve' signals on a URL it cannot parse or whose
              ;; scheme it has no handler for -- an ordinary typo in
              ;; `pascal1981-completion-proxy-url' is enough.  The pending
              ;; id is already set at this point, and no timeout timer is
              ;; armed yet to clear it, so letting the signal escape would
              ;; leave the id set forever and the in-flight guard would
              ;; then refuse every future completion in this buffer.
              (condition-case err
                  (url-retrieve
                   pascal1981-completion-proxy-url
                   #'pascal1981--completion-callback
                   (list source-buffer request-id point-at-request tick-at-request)
                   t)
                (error
                 (setq pascal1981--completion-pending-id nil)
                 (message "pascal1981: completion request failed: %s"
                           (error-message-string err))
                 nil))))
      (when (timerp pascal1981--completion-timeout-timer)
        (cancel-timer pascal1981--completion-timeout-timer))
      (setq pascal1981--completion-timeout-timer
            (run-at-time
             (+ pascal1981-completion-timeout
                pascal1981--completion-timeout-grace)
             nil
             #'pascal1981--completion-handle-timeout
             source-buffer request-id response-buffer)))))

(defun pascal1981-complete-line ()
  "Request an LLM completion at point from the local completion proxy.
Does nothing but report why, via `message', when completion is
disabled, point is mid-line, or what would be sent (the whole buffer,
or a lexical-unit slice of it -- see
`pascal1981-completion-lexical-unit-threshold') exceeds
`pascal1981-completion-buffer-limit'; the buffer is never modified by
this command itself. Later, asynchronously, a successful response is
shown as a ghost-text preview by `pascal1981--completion-callback',
not inserted directly -- accept it with TAB; reveal more or fewer of
its lines with `M-n'/`M-p'."
  (interactive)
  (cond
   ((not pascal1981-completion-enabled)
    (message "pascal1981: completion is disabled"))
   ((not (pascal1981--completion-allowed-at-point-p))
    (message "pascal1981: completion is not offered mid-line"))
   (t
    ;; Built once here and handed to both the size check and the send.
    (let ((request-text (pascal1981--completion-request-text)))
      (if (pascal1981--completion-oversized-p request-text)
          (message "pascal1981: buffer exceeds completion size limit (%d)"
                    pascal1981-completion-buffer-limit)
        (pascal1981--completion-send request-text))))))

(defun pascal1981-indent-or-complete ()
  "Accept a showing completion preview, request one, or indent.
Bound in place of `indent-for-tab-command' (see the
`[remap indent-for-tab-command]' binding in `pascal1981-mode-map',
set up below `pascal1981-mode's definition). If a completion preview
is already showing at point, TAB accepts it (see
`pascal1981--completion-do-accept'). Otherwise it requests a completion
only when `pascal1981-completion-enabled' is non-nil, point is
eligible per `pascal1981--completion-allowed-at-point-p', and what
would be sent does not exceed `pascal1981-completion-buffer-limit'
(see `pascal1981--completion-oversized-p'); in every other case --
completion disabled, mid-line, oversized -- TAB
keeps its ordinary meaning: `pascal1981-indent-line'. That fallback is
always exactly indentation, never a no-op, so disabling or losing the
proxy never costs TAB its normal behavior."
  (interactive)
  (cond
   ((pascal1981--completion-overlay-live-p)
    (pascal1981--completion-do-accept))
   ((and pascal1981--completion-accept-barrier
         (= (buffer-modified-tick) pascal1981--completion-accept-tick)
         (= (point) pascal1981--completion-accept-point))
    (message "pascal1981: completion accepted; edit or move before requesting another"))
   ((and pascal1981-completion-enabled
         (pascal1981--completion-allowed-at-point-p))
    ;; Built once here and handed to both the size check and the send.
    (let ((request-text (pascal1981--completion-request-text)))
      (if (pascal1981--completion-oversized-p request-text)
          (pascal1981-indent-line)
        (pascal1981--completion-send request-text))))
   (t
    (pascal1981-indent-line))))

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

(defun pascal1981--name-token-index (name &optional start)
  "Index of the first IDENTIFIER token with lexeme NAME at or after START.
START defaults to 0.  Return nil when there is no such token."
  (when (and name pascal1981--token-cache)
    (cl-loop for i from (or start 0) below (length pascal1981--token-cache)
             for tok = (aref pascal1981--token-cache i)
             when (and (equal (alist-get 'kind tok) "IDENTIFIER")
                       (equal (alist-get 'lexeme tok) name))
             return i)))

(defun pascal1981--name-pos (name &optional start)
  "Position of the first IDENTIFIER token with lexeme NAME at or after START."
  (let ((i (pascal1981--name-token-index name start)))
    (when i (pascal1981--token-pos (aref pascal1981--token-cache i)))))

(defun pascal1981--decl-end-index (start)
  "Index just past the declaration that covers token index START.
Scan forward for the SEMICOLON that ends the declaration: the first
one outside RECORD, BEGIN, or CASE ... END and outside parentheses.
A parameter list holds its own semicolons, so the paren depth counts.
Return nil when no such SEMICOLON follows START."
  (when pascal1981--token-cache
    (let ((depth 0) (paren 0) (i start)
          (n (length pascal1981--token-cache))
          (found nil))
      (while (and (null found) (< i n))
        (let ((kind (alist-get 'kind (aref pascal1981--token-cache i))))
          (cond
           ((member kind pascal1981--block-openers) (setq depth (1+ depth)))
           ((equal kind "END") (setq depth (max 0 (1- depth))))
           ((equal kind "LPAREN") (setq paren (1+ paren)))
           ((equal kind "RPAREN") (setq paren (max 0 (1- paren))))
           ((and (equal kind "SEMICOLON") (= depth 0) (= paren 0))
            (setq found (1+ i)))))
        (setq i (1+ i)))
      found)))

(defun pascal1981-imenu-index ()
  "Build imenu index from `pascal1981--ast-cache' or by re-parsing.
Names resolve against the token stream from left to right.  A cursor
moves past each declaration, so a name declared late does not resolve
to an earlier record field or parameter that shares the lexeme.  The
AST carries no source spans, so this order is the only scope the mode
has.  A name that a nested body declares can still shadow, because the
index covers the top-level block only."
  (unless pascal1981--ast-cache (pascal1981--refresh-caches))
  (when pascal1981--ast-cache
    (let ((decls (pascal1981--ast-block-decls pascal1981--ast-cache))
          (cursor 0)
          (entries nil))
      (when decls
        (cl-loop for d across decls
                 do (dolist (nm (pascal1981--decl-names d))
                      (when (and nm (stringp nm))
                        ;; Fall back to a full scan so an unexpected order
                        ;; loses the scope hint, never the entry itself.
                        (let ((i (or (pascal1981--name-token-index nm cursor)
                                     (pascal1981--name-token-index nm 0))))
                          (push (cons nm (if i
                                             (pascal1981--token-pos
                                              (aref pascal1981--token-cache i))
                                           (point-min)))
                                entries)
                          (when (and i (>= i cursor))
                            (setq cursor (1+ i))))))
                 ;; Step over the rest of this declaration before the next.
                 do (setq cursor (or (pascal1981--decl-end-index cursor) cursor)))
        (nreverse entries)))))

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
  (add-hook 'after-change-functions #'pascal1981--after-change nil t))

(defun pascal1981--after-change (&rest _)
  "Schedule refreshes and retire the TAB acceptance barrier after edits."
  (setq pascal1981--completion-accept-barrier nil)
  (pascal1981--schedule-refresh))

;; `define-derived-mode' above auto-creates `pascal1981-mode-map'; the TAB
;; remap has to be installed after that map exists.
(define-key pascal1981-mode-map [remap indent-for-tab-command]
            #'pascal1981-indent-or-complete)

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.pas\\'" . pascal1981-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.inc\\'" . pascal1981-mode))

(provide 'pascal1981-mode)
;;; pascal1981-mode.el ends here
