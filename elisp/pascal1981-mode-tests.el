;;; pascal1981-mode-tests.el --- ERT tests for pascal1981-mode -*- lexical-binding: t; -*-

;;; Commentary:
;; Run from the repo root with lexer and parser on PATH:
;;
;;   PATH="$PWD/bin:$PATH" emacs -Q --batch \
;;     -L elisp -l elisp/pascal1981-mode-tests.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(defconst pascal1981-tests--dir
  (file-name-directory (or load-file-name buffer-file-name)))

(add-to-list 'load-path pascal1981-tests--dir)
(require 'pascal1981-mode)

(defconst pascal1981-tests--repo
  (expand-file-name ".." pascal1981-tests--dir))

(defconst pascal1981-tests--kitchen
  (expand-file-name
   "tests/fixtures/parser/should_pass/10_kitchen_sink.pas"
   pascal1981-tests--repo))

(defconst pascal1981-tests--mini
  "PROGRAM P;\nBEGIN\nEND.\n")

(defun pascal1981-tests--have-binaries ()
  "Non-nil when both stage binaries resolve on `exec-path'."
  (and (executable-find pascal1981-lexer-program)
       (executable-find pascal1981-parser-program)))

(defmacro pascal1981-tests--with-pas (text &rest body)
  "Insert TEXT in a temp buffer, enable `pascal1981-mode', then run BODY."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (pascal1981-mode)
     (font-lock-ensure)
     ,@body))

(ert-deftest pascal1981-tests-binaries-on-path ()
  "Lexer and parser must be on PATH for the rest of the suite."
  (should (pascal1981-tests--have-binaries)))

(ert-deftest pascal1981-tests-lex-mini ()
  "A tiny program lexes to PROGRAM ... EOF."
  (skip-unless (pascal1981-tests--have-binaries))
  (let ((res (pascal1981-lex-string pascal1981-tests--mini)))
    (should (eq (car res) 'ok))
    (let* ((toks (cdr res))
           (first (aref toks 0))
           (last (aref toks (1- (length toks)))))
      (should (equal (alist-get 'kind first) "PROGRAM"))
      (should (equal (alist-get 'kind last) "EOF")))))

(ert-deftest pascal1981-tests-parse-mini ()
  "A tiny program parses as ProgramUnit."
  (skip-unless (pascal1981-tests--have-binaries))
  (let ((res (pascal1981-parse-string pascal1981-tests--mini)))
    (should (eq (car res) 'ok))
    (should (equal (alist-get '__node_type__ (cdr res)) "ProgramUnit"))))

(ert-deftest pascal1981-tests-parse-incomplete ()
  "A truncated program returns parser stderr."
  (skip-unless (pascal1981-tests--have-binaries))
  (let ((res (pascal1981-parse-string "PROGRAM P; BEGIN")))
    (should (eq (car res) 'error))
    (should (string-match-p "Parser Error:" (cdr res)))))

(ert-deftest pascal1981-tests-check-buffer ()
  "`pascal1981-check-buffer' is nil on good source, a string on bad."
  (skip-unless (pascal1981-tests--have-binaries))
  (with-temp-buffer
    (insert pascal1981-tests--mini)
    (should (null (pascal1981-check-buffer)))
    (erase-buffer)
    (insert "PROGRAM P; BEGIN")
    (should (stringp (pascal1981-check-buffer)))))

(ert-deftest pascal1981-tests-commands-are-interactive ()
  "Public entry points are M-x commands."
  (should (commandp 'pascal1981-refresh))
  (should (commandp 'pascal1981-check-buffer))
  (should (commandp 'pascal1981-indent-line))
  (should-not (commandp 'pascal1981--refresh-caches)))

(ert-deftest pascal1981-tests-auto-mode ()
  "`.pas' files map to `pascal1981-mode'."
  (should (eq (cdr (assoc "\\.pas\\'" auto-mode-alist)) 'pascal1981-mode))
  (should (eq (cdr (assoc "\\.inc\\'" auto-mode-alist)) 'pascal1981-mode)))

(ert-deftest pascal1981-tests-paren-star-comment-closes ()
  "A (* ... *) comment must not swallow the rest of the buffer."
  (with-temp-buffer
    (insert "(* c *)\nPROGRAM P;\nBEGIN\nEND.\n")
    (set-syntax-table pascal1981-mode-syntax-table)
    (syntax-propertize (point-max))
    (goto-char (point-min))
    (should (null (nth 4 (syntax-ppss (point-min)))))
    (search-forward "*)")
    (should (null (nth 4 (syntax-ppss (point)))))
    (search-forward "PROGRAM")
    (should (null (nth 4 (syntax-ppss (match-beginning 0)))))))

(ert-deftest pascal1981-tests-mode-faces ()
  "First paint colors keywords, types, literals, and comments."
  (skip-unless (pascal1981-tests--have-binaries))
  (pascal1981-tests--with-pas
      "(* c *)\nPROGRAM DEMO;\nVAR I : INTEGER;\nBEGIN\n  I := 10\nEND.\n"
    (let ((case-fold-search nil))
      (goto-char (point-min))
      (search-forward "c *)")
      (goto-char (point-min))
      (search-forward "c")
      (should (eq (get-text-property (match-beginning 0) 'face)
                  'font-lock-comment-face))
      (goto-char (point-min))
      (search-forward "PROGRAM")
      (should (eq (get-text-property (match-beginning 0) 'face)
                  'font-lock-keyword-face))
      (search-forward "DEMO")
      (should (null (get-text-property (match-beginning 0) 'face)))
      (search-forward "INTEGER")
      (should (eq (get-text-property (match-beginning 0) 'face)
                  'font-lock-type-face))
      (search-forward "10")
      (should (eq (get-text-property (match-beginning 0) 'face)
                  'font-lock-constant-face)))))

(ert-deftest pascal1981-tests-indent-nested ()
  "BEGIN opens a block. THEN does not stack when the next line is BEGIN."
  (skip-unless (pascal1981-tests--have-binaries))
  (let ((src "PROGRAM P;\nBEGIN\nIF TRUE THEN\nBEGIN END\nEND.\n"))
    (pascal1981-tests--with-pas src
      (should (= (pascal1981--compute-indent 1) 0))
      (should (= (pascal1981--compute-indent 2) 0))
      (should (= (pascal1981--compute-indent 3) pascal1981-indent-width))
      (should (= (pascal1981--compute-indent 4) pascal1981-indent-width))
      (should (= (pascal1981--compute-indent 5) 0)))))

(ert-deftest pascal1981-tests-indent-var-section ()
  "A name on the line after a lone VAR indents one width, not column 0."
  (skip-unless (pascal1981-tests--have-binaries))
  (pascal1981-tests--with-pas
      "PROGRAM P;\nVAR\nn, d: INTEGER;\nBEGIN\nEND.\n"
    (should (= (pascal1981--compute-indent 2) 0))
    (should (= (pascal1981--compute-indent 3) pascal1981-indent-width))
    (should (= (pascal1981--compute-indent 4) 0))
    (indent-region (point-min) (point-max))
    (goto-char (point-min))
    (forward-line 2)
    (should (= (current-indentation) pascal1981-indent-width))
    (should (string-prefix-p "n, d: INTEGER;"
                             (string-trim-left
                              (buffer-substring-no-properties
                               (line-beginning-position)
                               (line-end-position)))))))

(ert-deftest pascal1981-tests-indent-kitchen ()
  "Kitchen sink `indent-region' matches the fixture layout."
  (skip-unless (and (pascal1981-tests--have-binaries)
                    (file-readable-p pascal1981-tests--kitchen)))
  (let ((want (with-temp-buffer
                (insert-file-contents pascal1981-tests--kitchen)
                (buffer-string))))
    (pascal1981-tests--with-pas want
      (indent-region (point-min) (point-max))
      (should (equal (buffer-string) want)))))

(ert-deftest pascal1981-tests-indent-region ()
  "`indent-region' uses `pascal1981-indent-line' on each line."
  (skip-unless (pascal1981-tests--have-binaries))
  (pascal1981-tests--with-pas
      "PROGRAM P;\nBEGIN\nIF TRUE THEN\nBEGIN\nX := 1\nEND\nEND.\n"
    (should (eq indent-line-function #'pascal1981-indent-line))
    (indent-region (point-min) (point-max))
    (goto-char (point-min))
    (should (= (current-indentation) 0))
    (forward-line 2)                        ; IF TRUE THEN
    (should (= (current-indentation) pascal1981-indent-width))
    (forward-line 1)                        ; BEGIN (does not stack on THEN)
    (should (= (current-indentation) pascal1981-indent-width))
    (forward-line 1)                        ; X := 1
    (should (= (current-indentation) (* 2 pascal1981-indent-width)))
    (forward-line 1)                        ; END
    (should (= (current-indentation) pascal1981-indent-width))))

(ert-deftest pascal1981-tests-imenu-kitchen ()
  "Kitchen sink imenu lists N, I, S, BUMP at identifier positions."
  (skip-unless (and (pascal1981-tests--have-binaries)
                    (file-readable-p pascal1981-tests--kitchen)))
  (pascal1981-tests--with-pas
      (with-temp-buffer
        (insert-file-contents pascal1981-tests--kitchen)
        (buffer-string))
    (let ((idx (pascal1981-imenu-index)))
      (should (equal (mapcar #'car idx) '("N" "I" "S" "BUMP")))
      (dolist (pair idx)
        (let ((name (car pair))
              (pos (cdr pair)))
          (should (numberp pos))
          (should (equal (buffer-substring-no-properties
                          pos (+ pos (length name)))
                         name)))))))

(ert-deftest pascal1981-tests-kitchen-parses ()
  "Kitchen sink fixture lexes and parses through the mode caches."
  (skip-unless (and (pascal1981-tests--have-binaries)
                    (file-readable-p pascal1981-tests--kitchen)))
  (pascal1981-tests--with-pas
      (with-temp-buffer
        (insert-file-contents pascal1981-tests--kitchen)
        (buffer-string))
    (should (> (length pascal1981--token-cache) 0))
    (should (equal (alist-get '__node_type__ pascal1981--ast-cache)
                   "ProgramUnit"))
    (should (null (pascal1981-check-buffer)))))

(ert-deftest pascal1981-tests-comment-start-skip ()
  "`comment-start-skip' matches both comment openers of the dialect."
  (pascal1981-tests--with-pas pascal1981-tests--mini
    (should (string-match-p comment-start-skip "{ brace }"))
    (should (string-match-p comment-start-skip "(* paren star *)"))))

(defconst pascal1981-tests--tabbed
  "PROGRAM P;\nVAR X: INTEGER;\nBEGIN\n\tX := 1;\nEND.\n"
  "Mini program whose assignment line is indented with a TAB.")

(ert-deftest pascal1981-tests-token-bounds-with-tabs ()
  "Token bounds cover the token text on a TAB-indented line.
The lexer counts a TAB as one column.  `move-to-column' counts it as
its display width, which shifted every token after the TAB."
  (skip-unless (pascal1981-tests--have-binaries))
  (pascal1981-tests--with-pas pascal1981-tests--tabbed
    (let ((seen nil))
      (cl-loop for tok across pascal1981--token-cache
               when (and (= (alist-get 'line tok) 4)
                         (> (length (or (alist-get 'lexeme tok) "")) 0))
               do (let ((lex (alist-get 'lexeme tok))
                        (bounds (pascal1981--token-bounds tok)))
                    (push lex seen)
                    (should bounds)
                    (should (equal (buffer-substring-no-properties
                                    (car bounds) (cdr bounds))
                                   lex))))
      ;; All four tokens of the TAB-indented line were checked.
      (should (equal (nreverse seen) '("X" ":=" "1" ";"))))))

(ert-deftest pascal1981-tests-imenu-multi-name-var ()
  "Each name of a multi-name VAR decl is its own imenu entry.
`VAR X, YY: INTEGER;' is one VarDecl whose `names' vector holds both
names.  The index must not join them into one \"X, YY\" entry."
  (skip-unless (pascal1981-tests--have-binaries))
  (pascal1981-tests--with-pas
      "PROGRAM P;\nCONST N = 3;\nVAR X, YY: INTEGER;\n    Z: CHAR;\nBEGIN\n  X := 1;\nEND.\n"
    (let ((idx (pascal1981-imenu-index)))
      (should (equal (mapcar #'car idx) '("N" "X" "YY" "Z")))
      ;; Every entry points at its own identifier.
      (dolist (pair idx)
        (should (equal (buffer-substring-no-properties
                        (cdr pair) (+ (cdr pair) (length (car pair))))
                       (car pair)))))))

(ert-deftest pascal1981-tests-imenu-shadowed-name ()
  "A VAR resolves to its own declaration, not an earlier record field.
The record field X on line 2 precedes the VAR X on line 3.  A scan
from the start of the token stream stops at the field."
  (skip-unless (pascal1981-tests--have-binaries))
  (pascal1981-tests--with-pas
      "PROGRAM P;\nTYPE R = RECORD X: INTEGER END;\nVAR X: INTEGER;\nBEGIN\nEND.\n"
    (let ((idx (pascal1981-imenu-index)))
      (should (equal (mapcar #'car idx) '("R" "X")))
      (should (= (line-number-at-pos (cdr (assoc "R" idx))) 2))
      (should (= (line-number-at-pos (cdr (assoc "X" idx))) 3)))))

(ert-deftest pascal1981-tests-imenu-shadowed-after-proc-params ()
  "A VAR resolves past a procedure parameter of the same name.
The parameter list holds its own semicolons, so the scan for the end
of the PROCEDURE declaration must count parenthesis depth."
  (skip-unless (pascal1981-tests--have-binaries))
  (pascal1981-tests--with-pas
      (concat "PROGRAM P;\n"
              "PROCEDURE B(VAR Q: INTEGER; R: INTEGER);\n"
              "BEGIN\nEND;\n"
              "VAR Q: INTEGER;\n"
              "BEGIN\nEND.\n")
    (let ((idx (pascal1981-imenu-index)))
      (should (member "Q" (mapcar #'car idx)))
      ;; The VAR Q on line 5, not the parameter Q on line 2.
      (should (= (line-number-at-pos (cdr (assoc "Q" idx))) 5)))))

(ert-deftest pascal1981-tests-imenu-positions-are-monotonic ()
  "Imenu positions do not move backwards across the decl list."
  (skip-unless (and (pascal1981-tests--have-binaries)
                    (file-readable-p pascal1981-tests--kitchen)))
  (pascal1981-tests--with-pas
      (with-temp-buffer
        (insert-file-contents pascal1981-tests--kitchen)
        (buffer-string))
    (let ((positions (mapcar #'cdr (pascal1981-imenu-index))))
      (should (equal positions (sort (copy-sequence positions) #'<))))))

;; -------------------------------------------------------------------
;; LLM completion: eligibility predicate
;; -------------------------------------------------------------------

(ert-deftest pascal1981-tests-completion-eligible-at-eol ()
  "Point at end of line, nothing but the newline to the right."
  (with-temp-buffer
    (pascal1981-mode)
    (insert "x := 1")
    (should (pascal1981--completion-allowed-at-point-p))))

(ert-deftest pascal1981-tests-completion-eligible-before-trailing-whitespace ()
  "Point before only spaces/tabs is still eligible."
  (with-temp-buffer
    (pascal1981-mode)
    (insert "x := 1")
    (save-excursion (insert "   \t  "))
    (should (pascal1981--completion-allowed-at-point-p))))

(ert-deftest pascal1981-tests-completion-ineligible-mid-line ()
  "Non-whitespace to the right of point blocks completion eligibility."
  (with-temp-buffer
    (pascal1981-mode)
    (insert "x := ")
    (save-excursion (insert "1"))
    (should-not (pascal1981--completion-allowed-at-point-p))))

;; -------------------------------------------------------------------
;; LLM completion: async client
;; -------------------------------------------------------------------

(defun pascal1981-tests--fake-response-buffer (status-code json-body)
  "Return a new buffer shaped like a `url-retrieve' response buffer.
STATUS-CODE and JSON-BODY (an alist, or nil to omit a body) are set up
the way `pascal1981--completion-parse-response' expects to read them."
  (let ((buf (generate-new-buffer " *pascal1981-test-response*")))
    (with-current-buffer buf
      (insert (format "HTTP/1.1 %d OK\r\n" status-code))
      (insert "Content-Type: application/json\r\n\r\n")
      (setq-local url-http-end-of-headers (point))
      (setq-local url-http-response-status status-code)
      (when json-body
        (insert (json-encode json-body))))
    buf))

(defun pascal1981-tests--completion-respond (source-buffer response-buffer
                                                            request-id
                                                            point-at-request
                                                            tick-at-request
                                                            &optional status)
  "Invoke `pascal1981--completion-callback' as `url-retrieve' would.
Runs it with RESPONSE-BUFFER current, the way url.el actually does --
the callback itself decides which buffer is \"the response\" from
`current-buffer', so tests must not call it from SOURCE-BUFFER."
  (with-current-buffer response-buffer
    (pascal1981--completion-callback
     status source-buffer request-id point-at-request tick-at-request)))

(ert-deftest pascal1981-tests-completion-disabled-sends-no-request ()
  "Disabled completion never calls `url-retrieve'."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled nil)
    (insert "x := ")
    (cl-letf (((symbol-function 'url-retrieve)
               (lambda (&rest _) (error "url-retrieve must not be called"))))
      (pascal1981-complete-line))
    (should (equal (buffer-string) "x := "))))

(ert-deftest pascal1981-tests-completion-mid-line-sends-no-request ()
  "Mid-line point never calls `url-retrieve', even when enabled."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (save-excursion (insert "1"))
    (cl-letf (((symbol-function 'url-retrieve)
               (lambda (&rest _) (error "url-retrieve must not be called"))))
      (pascal1981-complete-line))
    (should (equal (buffer-string) "x := 1"))))

(ert-deftest pascal1981-tests-completion-inserts-at-point ()
  "A well-formed 200 response is inserted exactly at point."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completion . "1;") (model . "test-model")
                            (request_id . "abc")))))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (should (equal (buffer-string) "x := 1;"))))

(ert-deftest pascal1981-tests-completion-preserves-right-hand-text ()
  "Insertion never overwrites trailing whitespace to the right of point.
\(Non-whitespace to the right is covered separately: it fails the
eligibility check before a request would ever be sent.\)"
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (save-excursion (insert "   "))
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completion . "1;")))))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (should (equal (buffer-string) "x := 1;   "))))

(ert-deftest pascal1981-tests-completion-transport-error-unchanged ()
  "A `:error' status leaves the buffer untouched."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (generate-new-buffer " *pascal1981-test-err*")))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond
       source response request-id pt tick
       (list :error '(error connection-refused))))
    (should (equal (buffer-string) "x := "))))

(ert-deftest pascal1981-tests-completion-http-error-unchanged ()
  "A non-200 status leaves the buffer untouched."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer 500 nil)))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (should (equal (buffer-string) "x := "))))

(ert-deftest pascal1981-tests-completion-malformed-json-unchanged ()
  "A body that isn't JSON leaves the buffer untouched."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (generate-new-buffer " *pascal1981-test-bad-json*")))
      (with-current-buffer response
        (insert "HTTP/1.1 200 OK\r\n\r\n")
        (setq-local url-http-end-of-headers (point))
        (setq-local url-http-response-status 200)
        (insert "not json"))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (should (equal (buffer-string) "x := "))))

(ert-deftest pascal1981-tests-completion-empty-completion-unchanged ()
  "An empty \"completion\" field leaves the buffer untouched."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completion . "")))))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (should (equal (buffer-string) "x := "))))

(ert-deftest pascal1981-tests-completion-stale-response-discarded ()
  "A response for a superseded request id is discarded, not inserted."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completion . "1;")))))
      ;; A newer request superseded this one before the response arrived.
      (setq pascal1981--completion-pending-id 2)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (should (equal (buffer-string) "x := "))))

(ert-deftest pascal1981-tests-completion-buffer-changed-since-request-discarded ()
  "A response is discarded if the buffer changed since the request was sent."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completion . "1;")))))
      (setq pascal1981--completion-pending-id request-id)
      ;; The buffer changes after the request was sent, before it answers.
      (insert "y")
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (should (equal (buffer-string) "x := y"))))

;; -------------------------------------------------------------------
;; LLM completion: TAB dispatcher
;; -------------------------------------------------------------------

(ert-deftest pascal1981-tests-indent-or-complete-dispatches-to-completion ()
  "Enabled and eligible: TAB requests completion, not indentation."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let (sent indented)
      (cl-letf (((symbol-function 'pascal1981--completion-send)
                 (lambda () (setq sent t)))
                ((symbol-function 'pascal1981-indent-line)
                 (lambda () (setq indented t))))
        (pascal1981-indent-or-complete))
      (should sent)
      (should-not indented))))

(ert-deftest pascal1981-tests-indent-or-complete-falls-back-mid-line ()
  "Mid-line point falls back to ordinary indentation, never completion."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (save-excursion (insert "1"))
    (let (sent indented)
      (cl-letf (((symbol-function 'pascal1981--completion-send)
                 (lambda () (setq sent t)))
                ((symbol-function 'pascal1981-indent-line)
                 (lambda () (setq indented t))))
        (pascal1981-indent-or-complete))
      (should-not sent)
      (should indented))))

(ert-deftest pascal1981-tests-indent-or-complete-falls-back-when-disabled ()
  "Disabled completion falls back to ordinary indentation."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled nil)
    (insert "x := ")
    (let (sent indented)
      (cl-letf (((symbol-function 'pascal1981--completion-send)
                 (lambda () (setq sent t)))
                ((symbol-function 'pascal1981-indent-line)
                 (lambda () (setq indented t))))
        (pascal1981-indent-or-complete))
      (should-not sent)
      (should indented))))

(ert-deftest pascal1981-tests-indent-or-complete-falls-back-over-buffer-limit ()
  "A buffer past the size limit falls back to indentation, not completion."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t
          pascal1981-completion-buffer-limit 3)
    (insert "x := ")
    (let (sent indented)
      (cl-letf (((symbol-function 'pascal1981--completion-send)
                 (lambda () (setq sent t)))
                ((symbol-function 'pascal1981-indent-line)
                 (lambda () (setq indented t))))
        (pascal1981-indent-or-complete))
      (should-not sent)
      (should indented))))

(ert-deftest pascal1981-tests-tab-remapped-to-dispatcher ()
  "`indent-for-tab-command' is remapped to the dispatcher in the mode map."
  (should (eq (lookup-key pascal1981-mode-map
                          [remap indent-for-tab-command])
              #'pascal1981-indent-or-complete)))

;; -------------------------------------------------------------------
;; LLM completion: end-to-end against a local fake proxy
;; -------------------------------------------------------------------
;;
;; These start a real loopback HTTP server (no live LLM backend) and drive
;; the real `url-retrieve' path, unlike the tests above which call
;; `pascal1981--completion-callback' directly with a synthetic response
;; buffer. This exercises the actual network round trip: real socket I/O,
;; real HTTP parsing by `url-http', real event-loop scheduling.

(defun pascal1981-tests--start-fake-http-server (response)
  "Start a loopback HTTP server that always answers with RESPONSE.
RESPONSE is the raw HTTP response, status line and headers included.
Each connection gets RESPONSE once, on its first complete request head,
then is closed. Return (PROCESS . PORT)."
  (let* ((proc (make-network-process
                :name "pascal1981-fake-proxy" :server t :noquery t
                :host "127.0.0.1" :service t
                :filter
                (lambda (client chunk)
                  (process-put client 'pascal1981-tests--buf
                               (concat (or (process-get client 'pascal1981-tests--buf) "")
                                       chunk))
                  (when (string-match-p "\r\n\r\n"
                                         (process-get client 'pascal1981-tests--buf))
                    (process-send-string client response)
                    (delete-process client)))))
         (port (cadr (process-contact proc))))
    (cons proc port)))

(defun pascal1981-tests--http-json-response (status-code json-body)
  "Build a raw HTTP response with STATUS-CODE and a JSON-encoded body."
  (let ((body (json-encode json-body)))
    (concat (format "HTTP/1.1 %d OK\r\n" status-code)
            "Content-Type: application/json\r\n"
            (format "Content-Length: %d\r\n" (string-bytes body))
            "Connection: close\r\n\r\n"
            body)))

(defmacro pascal1981-tests--with-fake-proxy (response &rest body)
  "Run BODY with `pascal1981-completion-proxy-url' pointed at a fake
server that answers every request with RESPONSE (raw HTTP bytes). The
server is torn down after BODY runs."
  (declare (indent 1))
  `(let* ((server+port (pascal1981-tests--start-fake-http-server ,response))
          (pascal1981-completion-proxy-url
           (format "http://127.0.0.1:%d/complete" (cdr server+port))))
     (unwind-protect
         (progn ,@body)
       (when (process-live-p (car server+port))
         (delete-process (car server+port))))))

(defun pascal1981-tests--wait-until (predicate timeout)
  "Pump the event loop until PREDICATE is non-nil or TIMEOUT seconds pass."
  (let ((deadline (+ (float-time) timeout)))
    (while (and (< (float-time) deadline) (not (funcall predicate)))
      (accept-process-output nil 0.05))))

(ert-deftest pascal1981-tests-end-to-end-fake-proxy-inserts-completion ()
  "A real HTTP round trip against a local fake proxy inserts the completion."
  (pascal1981-tests--with-fake-proxy
      (pascal1981-tests--http-json-response
       200 '((completion . "TO 10 DO") (model . "test-model")
             (request_id . "e2e-1")))
    (with-temp-buffer
      (pascal1981-mode)
      (setq pascal1981-completion-enabled t
            pascal1981-completion-timeout 5)
      (insert "FOR i := 1 ")
      (pascal1981-complete-line)
      (pascal1981-tests--wait-until
       (lambda () (not pascal1981--completion-pending-id)) 5)
      (should (equal (buffer-string) "FOR i := 1 TO 10 DO")))))

(ert-deftest pascal1981-tests-end-to-end-fake-proxy-http-error-unchanged ()
  "A real HTTP round trip returning a non-200 status leaves the buffer alone."
  (pascal1981-tests--with-fake-proxy
      (pascal1981-tests--http-json-response 503 '((error . "backend down")))
    (with-temp-buffer
      (pascal1981-mode)
      (setq pascal1981-completion-enabled t
            pascal1981-completion-timeout 5)
      (insert "FOR i := 1 ")
      (pascal1981-complete-line)
      (pascal1981-tests--wait-until
       (lambda () (not pascal1981--completion-pending-id)) 5)
      (should (equal (buffer-string) "FOR i := 1 ")))))

(ert-deftest pascal1981-tests-end-to-end-connection-refused-unchanged ()
  "A real connection-refused (nothing listening) leaves the buffer alone."
  (with-temp-buffer
    (pascal1981-mode)
    ;; Port 1 is a privileged, essentially always-closed port -- a real
    ;; connection attempt here fails immediately with connection-refused,
    ;; the same failure mode as \"the user hasn't started the proxy yet\".
    (setq pascal1981-completion-enabled t
          pascal1981-completion-timeout 2
          pascal1981-completion-proxy-url "http://127.0.0.1:1/complete")
    (insert "FOR i := 1 ")
    (pascal1981-complete-line)
    (pascal1981-tests--wait-until
     (lambda () (not pascal1981--completion-pending-id)) 6)
    (should (equal (buffer-string) "FOR i := 1 "))))

(provide 'pascal1981-mode-tests)
;;; pascal1981-mode-tests.el ends here
