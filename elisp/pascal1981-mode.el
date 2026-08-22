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
  "Seconds of idle time before refreshing highlighting / indentation."
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

(defcustom pascal1981-completion-goal
  "Complete the Pascal source at point with the smallest correct insertion."
  "Goal text sent to the completion proxy with each request."
  :type 'string :group 'pascal1981)

(defcustom pascal1981-completion-timeout 8
  "Seconds to wait for the completion proxy before giving up."
  :type 'number :group 'pascal1981)

(defcustom pascal1981-completion-buffer-limit 65536
  "Maximum buffer size, in characters, sent to the completion proxy.
Buffers larger than this are not sent; TAB falls back to
indentation instead."
  :type 'integer :group 'pascal1981)

(defun pascal1981-completion-toggle (&optional arg)
  "Toggle `pascal1981-completion-enabled'.
With prefix ARG, enable it if ARG is positive, disable otherwise."
  (interactive "P")
  (setq pascal1981-completion-enabled
        (if arg
            (> (prefix-numeric-value arg) 0)
          (not pascal1981-completion-enabled)))
  (message "pascal1981: LLM completion %s"
           (if pascal1981-completion-enabled "enabled" "disabled")))

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
  "Insert TEXT at point as a single atomic undo step."
  (atomic-change-group
    (insert text)))

(defun pascal1981--completion-parse-response (response-buffer)
  "Return (STATUS-CODE . COMPLETION-OR-NIL) parsed from RESPONSE-BUFFER.
COMPLETION-OR-NIL is nil when the body is not valid JSON with a
string \"completion\" field."
  (with-current-buffer response-buffer
    (let ((status-code (url-http-symbol-value-in-buffer
                         'url-http-response-status response-buffer)))
      (goto-char (if (boundp 'url-http-end-of-headers)
                     (or url-http-end-of-headers (point-min))
                   (point-min)))
      (let ((body (ignore-errors (json-read))))
        (cons status-code
              (and (listp body) (alist-get 'completion body)))))))

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
STATUS is the plist url.el passes on completion/error. Insert the
completion only if SOURCE-BUFFER still exists, completion is still
enabled there, REQUEST-ID is still the pending one (a stale response
is discarded silently -- it already lost the race, no message
needed), the buffer is unchanged since TICK-AT-REQUEST, point is
still POINT-AT-REQUEST, and the eligibility rule still holds there."
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
                 (completion (cdr parsed)))
            (when (and status-code (/= status-code 200))
              (message "pascal1981: completion proxy returned HTTP %s" status-code)
              (throw 'pascal1981--completion-done nil))
            (unless (and (stringp completion) (> (length completion) 0))
              (message "pascal1981: completion response was empty or malformed")
              (throw 'pascal1981--completion-done nil))
            (with-current-buffer source-buffer
              (unless (and pascal1981-completion-enabled
                            (= (buffer-modified-tick) tick-at-request)
                            (= (point) point-at-request)
                            (pascal1981--completion-allowed-at-point-p))
                (throw 'pascal1981--completion-done nil))
              (pascal1981--completion-insert completion))))
      (when (buffer-live-p response-buffer)
        (kill-buffer response-buffer)))))

(defun pascal1981--completion-send ()
  "Send an asynchronous `/complete' request for the current buffer/point.
Captures the source buffer, point, buffer modification tick, and
1-based line/column before sending; `pascal1981--completion-callback'
re-validates all of it before inserting anything, so a response that
arrives after the buffer changed underneath it is discarded rather
than inserted somewhere it no longer belongs."
  (let* ((source-buffer (current-buffer))
         (request-id (cl-incf pascal1981--completion-request-counter))
         (point-at-request (point))
         (tick-at-request (buffer-modified-tick))
         (line-column (pascal1981--completion-line-column))
         (buffer-text (buffer-substring-no-properties (point-min) (point-max)))
         (url-request-method "POST")
         (url-request-extra-headers '(("Content-Type" . "application/json")))
         (url-request-data
          (encode-coding-string
           (pascal1981--completion-payload
            pascal1981-completion-goal buffer-text
            (car line-column) (cdr line-column))
           'utf-8)))
    (setq pascal1981--completion-pending-id request-id)
    (letrec ((response-buffer
              (url-retrieve
               pascal1981-completion-proxy-url
               #'pascal1981--completion-callback
               (list source-buffer request-id point-at-request tick-at-request)
               t)))
      (when (timerp pascal1981--completion-timeout-timer)
        (cancel-timer pascal1981--completion-timeout-timer))
      (setq pascal1981--completion-timeout-timer
            (run-at-time
             pascal1981-completion-timeout nil
             #'pascal1981--completion-handle-timeout
             source-buffer request-id response-buffer)))))

(defun pascal1981-complete-line ()
  "Request an LLM completion at point from the local completion proxy.
Does nothing but report why, via `message', when completion is
disabled, point is mid-line, or the buffer exceeds
`pascal1981-completion-buffer-limit'; the buffer is never modified by
this command itself, only (asynchronously, later) by
`pascal1981--completion-callback' if a real completion comes back."
  (interactive)
  (cond
   ((not pascal1981-completion-enabled)
    (message "pascal1981: completion is disabled"))
   ((not (pascal1981--completion-allowed-at-point-p))
    (message "pascal1981: completion is not offered mid-line"))
   ((> (buffer-size) pascal1981-completion-buffer-limit)
    (message "pascal1981: buffer exceeds completion size limit (%d)"
              pascal1981-completion-buffer-limit))
   (t
    (pascal1981--completion-send))))

(defun pascal1981-indent-or-complete ()
  "Request an LLM completion at point, or indent the current line.
Bound in place of `indent-for-tab-command' (see the
`[remap indent-for-tab-command]' binding in `pascal1981-mode-map',
set up below `pascal1981-mode's definition). Requests a completion
only when `pascal1981-completion-enabled' is non-nil, point is
eligible per `pascal1981--completion-allowed-at-point-p', and the
buffer does not exceed `pascal1981-completion-buffer-limit'; in every
other case -- completion disabled, mid-line, oversized buffer -- TAB
keeps its ordinary meaning: `pascal1981-indent-line'. That fallback is
always exactly indentation, never a no-op, so disabling or losing the
proxy never costs TAB its normal behavior."
  (interactive)
  (if (and pascal1981-completion-enabled
            (pascal1981--completion-allowed-at-point-p)
            (<= (buffer-size) pascal1981-completion-buffer-limit))
      (pascal1981--completion-send)
    (pascal1981-indent-line)))

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

(defconst pascal1981--block-openers '("RECORD" "BEGIN" "CASE")
  "Token kinds that open a block which a matching END closes.")

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
  (add-hook 'after-change-functions (lambda (&rest _) (pascal1981--schedule-refresh)) nil t))

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
