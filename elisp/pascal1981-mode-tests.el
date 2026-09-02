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

(defmacro pascal1981-tests--with-selected-buffer (name &rest body)
  "Run BODY in a new, selected buffer named NAME. Buffer is killed after.
Needed wherever a test drives real key dispatch via `execute-kbd-macro':
a `with-temp-buffer' buffer is never \"selected\", and so does not
reliably stay current through real command dispatch in batch mode."
  (declare (indent 1))
  `(let ((pascal1981-tests--buf (generate-new-buffer ,name)))
     (unwind-protect
         (progn
           (switch-to-buffer pascal1981-tests--buf)
           ,@body)
       (kill-buffer pascal1981-tests--buf))))

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

(defun pascal1981-tests--have-driver ()
  "Non-nil when the driver binary resolves on `exec-path'."
  (executable-find pascal1981-driver-program))

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

(ert-deftest pascal1981-tests-format-buffer-reformats-valid-source ()
  "`pascal1981-format-buffer' rewrites a valid but ugly buffer."
  (skip-unless (pascal1981-tests--have-driver))
  (with-temp-buffer
    (insert "PROGRAM   P;\nBEGIN\nEND        .\n")
    (should (pascal1981-format-buffer))
    (should (string-match-p "\\`PROGRAM P(input, output);" (buffer-string)))))

(ert-deftest pascal1981-tests-format-buffer-leaves-bad-source-untouched ()
  "`pascal1981-format-buffer' returns nil and does not touch an invalid buffer."
  (skip-unless (pascal1981-tests--have-driver))
  (with-temp-buffer
    (let ((text "PROGRAM P; BEGIN"))
      (insert text)
      (should-not (pascal1981-format-buffer))
      (should (equal (buffer-string) text)))))

(ert-deftest pascal1981-tests-commands-are-interactive ()
  "Public entry points are M-x commands."
  (should (commandp 'pascal1981-refresh))
  (should (commandp 'pascal1981-check-buffer))
  (should (commandp 'pascal1981-indent-line))
  (should (commandp 'pascal1981-format-buffer))
  (should-not (commandp 'pascal1981--refresh-caches))
  (should-not (commandp 'pascal1981--format-string)))

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

(ert-deftest pascal1981-tests-mode-faces-vector ()
  "VECTOR in type position paints as a type."
  (skip-unless (pascal1981-tests--have-binaries))
  (pascal1981-tests--with-pas
      (concat "PROGRAM DEMO;\nTYPE V = VECTOR [4] OF INTEGER;\n"
              "VAR A : V;\nBEGIN\nEND.\n")
    (let ((case-fold-search nil))
      (goto-char (point-min))
      (search-forward "VECTOR")
      (should (eq (get-text-property (match-beginning 0) 'face)
                  'font-lock-type-face)))))

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
;; LLM completion: toggle command
;; -------------------------------------------------------------------

(ert-deftest pascal1981-tests-toggle-flips-enabled ()
  "`pascal1981-completion-toggle' is a plain toggle -- it no longer takes a
candidate-count prefix argument, since the proxy no longer supports
requesting more than one candidate per request."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled nil)
    (pascal1981-completion-toggle)
    (should pascal1981-completion-enabled)
    (pascal1981-completion-toggle)
    (should-not pascal1981-completion-enabled)))

(ert-deftest pascal1981-tests-real-m-x-toggle-flips-enabled ()
  "A real `M-x pascal1981-completion-toggle' keypress sequence, not a
direct function call, flips `pascal1981-completion-enabled'."
  (pascal1981-tests--with-selected-buffer "pascal1981-tests-real-toggle"
    (pascal1981-mode)
    (setq pascal1981-completion-enabled nil)
    (execute-kbd-macro (kbd "M-x pascal1981-completion-toggle RET"))
    (should pascal1981-completion-enabled)))

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
;; LLM completion: lexical-unit slicing
;; -------------------------------------------------------------------

(ert-deftest pascal1981-tests-proc-span-end-covers-whole-body ()
  "A procedure with params and a real body: the span ends after its own
closing `END;', not just after its header `;'."
  (skip-unless (pascal1981-tests--have-binaries))
  (pascal1981-tests--with-pas
      (concat "PROGRAM P;\n"
              "PROCEDURE BUMP(VAR X: INTEGER);\n"
              "BEGIN\n"
              "  X := X + 1\n"
              "END;\n"
              "BEGIN\n"
              "END.\n")
    (let* ((proc-index (cl-position-if
                        (lambda (tok) (equal (alist-get 'kind tok) "PROCEDURE"))
                        pascal1981--token-cache))
           (end-index (pascal1981--completion-proc-span-end proc-index))
           (end-tok (aref pascal1981--token-cache end-index)))
      ;; The token just past the span is BUMP's own BEGIN's matching
      ;; END's semicolon -- i.e. the outer program's own "BEGIN" on
      ;; line 6, not anything inside BUMP itself.
      (should (= (alist-get 'line end-tok) 6)))))

(ert-deftest pascal1981-tests-proc-span-end-extern-has-no-body ()
  "An EXTERN declaration's span ends right after its own trailing `;',
with no BEGIN/END involved at all."
  (skip-unless (pascal1981-tests--have-binaries))
  (pascal1981-tests--with-pas
      (concat "PROGRAM P;\n"
              "FUNCTION Alloc(size: INTEGER): INTEGER; EXTERN;\n"
              "BEGIN\n"
              "END.\n")
    (let* ((proc-index (cl-position-if
                        (lambda (tok) (equal (alist-get 'kind tok) "FUNCTION"))
                        pascal1981--token-cache))
           (end-index (pascal1981--completion-proc-span-end proc-index))
           (end-tok (aref pascal1981--token-cache end-index)))
      (should (= (alist-get 'line end-tok) 3)))))

(ert-deftest pascal1981-tests-proc-span-end-skips-nested-procedure ()
  "A procedure containing a nested procedure declaration in its own
decls section: the nested procedure's own BEGIN...END must not be
mistaken for the outer one's -- this is the case a naive single-pass
depth scan gets wrong (the nested BEGIN...END returns depth to 0
before the outer procedure's own body has even started)."
  (skip-unless (pascal1981-tests--have-binaries))
  (pascal1981-tests--with-pas
      (concat "PROGRAM P;\n"
              "PROCEDURE Outer;\n"
              "PROCEDURE Inner;\n"
              "BEGIN\n"
              "END;\n"
              "BEGIN\n"
              "  Inner\n"
              "END;\n"
              "BEGIN\n"
              "END.\n")
    (let* ((outer-index (cl-position-if
                         (lambda (tok) (equal (alist-get 'kind tok) "PROCEDURE"))
                         pascal1981--token-cache))
           (end-index (pascal1981--completion-proc-span-end outer-index))
           (end-tok (aref pascal1981--token-cache end-index)))
      ;; Must run past Inner's own "END;" (line 5) all the way to
      ;; Outer's own "END;" -- the token just past the span is the
      ;; PROGRAM's own top-level BEGIN, on line 9.
      (should (= (alist-get 'line end-tok) 9)))))

(ert-deftest pascal1981-tests-enclosing-unit-span-finds-innermost ()
  "Point inside a nested procedure resolves to the nested one's span,
not the outer one's."
  (skip-unless (pascal1981-tests--have-binaries))
  (pascal1981-tests--with-pas
      (concat "PROGRAM P;\n"
              "PROCEDURE Outer;\n"
              "PROCEDURE Inner;\n"
              "BEGIN\n"
              "  Q := 1\n"
              "END;\n"
              "BEGIN\n"
              "  Inner\n"
              "END;\n"
              "BEGIN\n"
              "END.\n")
    (goto-char (point-min))
    (search-forward "Q := 1")
    (let ((span (pascal1981--completion-enclosing-unit-span (point))))
      (should span)
      (should (= (line-number-at-pos (car span)) 3)))))

(ert-deftest pascal1981-tests-enclosing-unit-span-nil-at-top-level ()
  "Point in the top-level main block (not inside any procedure) has no
enclosing unit."
  (skip-unless (pascal1981-tests--have-binaries))
  (pascal1981-tests--with-pas
      (concat "PROGRAM P;\n"
              "PROCEDURE Foo;\n"
              "BEGIN\n"
              "END;\n"
              "BEGIN\n"
              "  Foo\n"
              "END.\n")
    (goto-char (point-min))
    (search-forward "Foo\n")
    (should-not (pascal1981--completion-enclosing-unit-span (point)))))

(ert-deftest pascal1981-tests-toplevel-decls-end-before-first-procedure ()
  "The top-level declarations span stops right at the first PROCEDURE."
  (skip-unless (pascal1981-tests--have-binaries))
  (pascal1981-tests--with-pas
      (concat "PROGRAM P;\n"
              "CONST N = 1;\n"
              "VAR X: INTEGER;\n"
              "PROCEDURE Foo;\n"
              "BEGIN\n"
              "END;\n"
              "BEGIN\n"
              "END.\n")
    (let ((end (pascal1981--completion-toplevel-decls-end)))
      (should (equal (buffer-substring-no-properties (point-min) end)
                     "PROGRAM P;\nCONST N = 1;\nVAR X: INTEGER;\n")))))

(ert-deftest pascal1981-tests-build-slice-adjusts-line-column ()
  "The slice combines top-level decls with the unit's own text, and the
returned LINE/COLUMN point into the combined text, not the original
buffer."
  (skip-unless (pascal1981-tests--have-binaries))
  (pascal1981-tests--with-pas
      (concat "PROGRAM P;\n"
              "VAR N: INTEGER;\n"
              "PROCEDURE Foo;\n"
              "BEGIN\n"
              "  N := 1\n"
              "END;\n"
              "BEGIN\n"
              "END.\n")
    (goto-char (point-min))
    (search-forward "N := 1")
    (let* ((span (pascal1981--completion-enclosing-unit-span (point)))
           (result (pascal1981--completion-build-slice
                    (car span) (cdr span) (point)))
           (text (car result))
           (line-column (cdr result)))
      (should (string-prefix-p "PROGRAM P;\nVAR N: INTEGER;\n" text))
      (should (string-match-p "PROCEDURE Foo;" text))
      ;; decls-text is 2 complete lines (PROGRAM + VAR), so within the
      ;; slice: line 3 is "PROCEDURE Foo;", line 4 is "BEGIN", and
      ;; "N := 1" (where point stops, right after the "1") is line 5.
      (should (= (car line-column) 5))
      (should (= (cdr line-column) 9)))))

(ert-deftest pascal1981-tests-request-text-unchanged-under-threshold ()
  "A buffer under `pascal1981-completion-lexical-unit-threshold' still
sends the whole buffer verbatim, unchanged from before this feature."
  (skip-unless (pascal1981-tests--have-binaries))
  (pascal1981-tests--with-pas "PROGRAM P;\nBEGIN\nEND.\n"
    (let* ((pascal1981-completion-lexical-unit-threshold 4000)
           (result (pascal1981--completion-request-text)))
      (should (equal (car result) (buffer-string))))))

(ert-deftest pascal1981-tests-request-text-slices-above-threshold ()
  "Above the threshold, with point inside a procedure, the request text
is a slice, not the whole (padded, larger) buffer."
  (skip-unless (pascal1981-tests--have-binaries))
  (pascal1981-tests--with-pas
      (concat "PROGRAM P;\n"
              "VAR N: INTEGER;\n"
              "PROCEDURE Foo;\n"
              "BEGIN\n"
              "  N := 1\n"
              "END;\n"
              "BEGIN\n"
              "END.\n"
              ;; Padding as a comment so the buffer exceeds a tiny
              ;; threshold without changing the token stream that
              ;; matters for slicing.
              "{ " (make-string 50 ?x) " }\n")
    (goto-char (point-min))
    (search-forward "N := 1")
    (let* ((pascal1981-completion-lexical-unit-threshold 50)
           (result (pascal1981--completion-request-text)))
      (should (< (length (car result)) (buffer-size)))
      (should (string-match-p "PROCEDURE Foo;" (car result))))))

(ert-deftest pascal1981-tests-request-text-falls-back-at-top-level ()
  "Above the threshold, with point at the top level (no enclosing
unit), the whole buffer is still sent."
  (skip-unless (pascal1981-tests--have-binaries))
  (pascal1981-tests--with-pas
      (concat "PROGRAM P;\n"
              "PROCEDURE Foo;\n"
              "BEGIN\n"
              "END;\n"
              "BEGIN\n"
              "  Foo\n"
              "END.\n"
              "{ " (make-string 50 ?x) " }\n")
    (goto-char (point-min))
    (search-forward "Foo\n")
    (let* ((pascal1981-completion-lexical-unit-threshold 50)
           (result (pascal1981--completion-request-text)))
      (should (equal (car result) (buffer-string))))))

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

(ert-deftest pascal1981-tests-completion-send-logging ()
  "An outgoing completion request logs its captured request state when enabled."
  (let ((log-buffer-name "*pascal1981-completion-log*")
        (response-buffer (generate-new-buffer " *pascal1981-test-response*")))
    (unwind-protect
        (with-temp-buffer
          (pascal1981-mode)
          (insert "x := ")
          (let ((pascal1981-completion-debug-log t)
                (source-name (buffer-name))
                (tick (buffer-modified-tick))
                (pt (point)))
            (cl-letf (((symbol-function 'url-retrieve)
                       (lambda (&rest _) response-buffer)))
              (pascal1981--completion-send-1
               (cons (buffer-string) (cons 1 pt))))
            (let ((log (with-current-buffer (get-buffer log-buffer-name)
                         (buffer-string))))
              (should (string-match-p "^SEND time=[0-9.]+ request=1 " log))
              (should (string-match-p (regexp-quote (format "buffer=%S" source-name)) log))
              (should (string-match-p (format "tick=%d point=%d" tick pt) log))
              (should (string-match-p (format "line=1 column=%d" pt) log)))
            (cancel-timer pascal1981--completion-timeout-timer)))
      (when (get-buffer log-buffer-name)
        (kill-buffer log-buffer-name))
      (when (buffer-live-p response-buffer)
        (kill-buffer response-buffer)))))

(ert-deftest pascal1981-tests-completion-send-logging-mocked-round-trip ()
  "A mocked completion response leaves one timestamped send record."
  (let ((log-buffer-name "*pascal1981-completion-log*")
        (response-buffer (pascal1981-tests--fake-response-buffer
                          200 '((completions . ["1;"])))))
    (unwind-protect
        (with-temp-buffer
          (pascal1981-mode)
          (setq pascal1981-completion-enabled t)
          (insert "x := ")
          (let ((pascal1981-completion-debug-log t)
                (started (float-time)))
            (cl-letf (((symbol-function 'url-retrieve)
                       (lambda (_url callback callback-args &rest _)
                         (with-current-buffer response-buffer
                           (apply callback nil callback-args))
                         response-buffer)))
              (pascal1981--completion-send-1
               (cons (buffer-string) (cons 1 (point)))))
            (let ((finished (float-time))
                  (log (with-current-buffer (get-buffer log-buffer-name)
                         (buffer-string))))
              (should (pascal1981--completion-overlay-live-p))
              (should (string-match "^SEND time=\\([0-9.]+\\) " log))
              (let ((sent-at (string-to-number (match-string 1 log))))
                ;; The log keeps microsecond precision, so allow rounding
                ;; at the lower bound.
                (should (<= started (+ sent-at 0.000001)))
                (should (<= sent-at finished))))
          (cancel-timer pascal1981--completion-timeout-timer)))
      (when (get-buffer log-buffer-name)
        (kill-buffer log-buffer-name))
      (when (buffer-live-p response-buffer)
        (kill-buffer response-buffer)))))

(ert-deftest pascal1981-tests-completion-send-logging-disabled ()
  "Disabled request logging does not create a diagnostic buffer."
  (let ((log-buffer-name "*pascal1981-completion-log*")
        (response-buffer (generate-new-buffer " *pascal1981-test-response*")))
    (unwind-protect
        (with-temp-buffer
          (pascal1981-mode)
          (insert "x := ")
          (when (get-buffer log-buffer-name)
            (kill-buffer log-buffer-name))
          (cl-letf (((symbol-function 'url-retrieve)
                     (lambda (&rest _) response-buffer)))
            (pascal1981--completion-send-1
             (cons (buffer-string) (cons 1 (point)))))
          (should-not (get-buffer log-buffer-name))
          (cancel-timer pascal1981--completion-timeout-timer))
      (when (get-buffer log-buffer-name)
        (kill-buffer log-buffer-name))
      (when (buffer-live-p response-buffer)
        (kill-buffer response-buffer)))))

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

(ert-deftest pascal1981-tests-completion-shows-ghost-at-point ()
  "A well-formed 200 response shows a ghost-text preview, not an insert."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completions . ["1;"]) (model . "test-model")
                            (request_id . "abc")))))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (should (equal (buffer-string) "x := "))
    (should (pascal1981--completion-overlay-live-p))
    (should (equal (overlay-get pascal1981--completion-overlay 'after-string)
                   "1;"))))

(ert-deftest pascal1981-tests-completion-single-candidate-no-index-suffix ()
  "A single candidate shows no \"[i/N]\" suffix."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completions . ["1;"])))))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (should-not (string-match-p "\\["
                                (overlay-get pascal1981--completion-overlay
                                             'after-string)))))

(ert-deftest pascal1981-tests-completion-multi-line-shows-only-first-line-by-default ()
  "A multi-line completion shows only its first line by default, with a
\"[1/N lines]\" suffix -- `M-n' reveals more (see the reveal tests below),
it is not shown all at once the way it used to be."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completions . ["BEGIN\ntotal := 1;\nEND;"])))))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (should (equal (overlay-get pascal1981--completion-overlay 'after-string)
                   "BEGIN [1/3 lines]"))))

(ert-deftest pascal1981-tests-completion-overlay-renders-embedded-newlines-once-revealed ()
  "Once more lines are revealed, embedded newlines survive into the
overlay's after-string verbatim -- Emacs renders an overlay after-string
with embedded newlines as extra visual lines with no further work needed."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completions . ["BEGIN\ntotal := 1;\nEND;"])))))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    ;; fib-steps(3) == (1 2 3): one M-n reveals 2 lines, another reveals 3.
    (pascal1981-completion-reveal-more)
    (pascal1981-completion-reveal-more)
    (should (equal (overlay-get pascal1981--completion-overlay 'after-string)
                   "BEGIN\ntotal := 1;\nEND; [3/3 lines]"))))

(ert-deftest pascal1981-tests-completion-accept-materializes-into-buffer ()
  "TAB, dispatched while a preview is showing, inserts the shown candidate."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completions . ["1;"])))))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (pascal1981-indent-or-complete)
    (should (equal (buffer-string) "x := 1;"))
    (should-not pascal1981--completion-overlay)))

(ert-deftest pascal1981-tests-completion-fib-steps ()
  "`pascal1981--completion-fib-steps' produces deduplicated Fibonacci-spaced
counts, always ending at TOTAL."
  (should (equal (pascal1981--completion-fib-steps 1) '(1)))
  (should (equal (pascal1981--completion-fib-steps 2) '(1 2)))
  (should (equal (pascal1981--completion-fib-steps 3) '(1 2 3)))
  (should (equal (pascal1981--completion-fib-steps 5) '(1 2 3 5)))
  (should (equal (pascal1981--completion-fib-steps 6) '(1 2 3 5 6)))
  (should (equal (pascal1981--completion-fib-steps 7) '(1 2 3 5 7)))
  (should-not (pascal1981--completion-fib-steps 0)))

(ert-deftest pascal1981-tests-completion-reveal-more-steps-through-fibonacci ()
  "`M-n' steps the revealed line count forward through the Fibonacci
schedule, and stays at the total once it is reached -- it does not wrap."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completions . ["a\nb\nc\nd\ne"])))))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    ;; fib-steps(5) == (1 2 3 5): 1 -> 2 -> 3 -> 5 -> 5 (clamped, no wrap).
    (should (equal (overlay-get pascal1981--completion-overlay 'after-string)
                   "a [1/5 lines]"))
    (pascal1981-completion-reveal-more)
    (should (equal (overlay-get pascal1981--completion-overlay 'after-string)
                   "a\nb [2/5 lines]"))
    (pascal1981-completion-reveal-more)
    (should (equal (overlay-get pascal1981--completion-overlay 'after-string)
                   "a\nb\nc [3/5 lines]"))
    (pascal1981-completion-reveal-more)
    (should (equal (overlay-get pascal1981--completion-overlay 'after-string)
                   "a\nb\nc\nd\ne [5/5 lines]"))
    (pascal1981-completion-reveal-more)
    (should (equal (overlay-get pascal1981--completion-overlay 'after-string)
                   "a\nb\nc\nd\ne [5/5 lines]"))))

(ert-deftest pascal1981-tests-completion-reveal-fewer-steps-back-down ()
  "`M-p' steps the revealed line count back down, stopping at 1 line
rather than wrapping to the total."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completions . ["a\nb\nc"])))))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (pascal1981-completion-reveal-more)
    (pascal1981-completion-reveal-more)
    (should (equal (overlay-get pascal1981--completion-overlay 'after-string)
                   "a\nb\nc [3/3 lines]"))
    (pascal1981-completion-reveal-fewer)
    (should (equal (overlay-get pascal1981--completion-overlay 'after-string)
                   "a\nb [2/3 lines]"))
    (pascal1981-completion-reveal-fewer)
    (should (equal (overlay-get pascal1981--completion-overlay 'after-string)
                   "a [1/3 lines]"))
    (pascal1981-completion-reveal-fewer)
    (should (equal (overlay-get pascal1981--completion-overlay 'after-string)
                   "a [1/3 lines]"))))

(ert-deftest pascal1981-tests-completion-accept-inserts-only-revealed-lines ()
  "TAB inserts only the lines currently revealed, not the whole completion
-- what you see is what you get."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completions . ["1;\n2;\n3;"])))))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (pascal1981-completion-reveal-more)
    (pascal1981-indent-or-complete)
    (should (equal (buffer-string) "x := 1;\n2;"))
    (should-not pascal1981--completion-overlay)))

(ert-deftest pascal1981-tests-completion-not-live-after-point-moves ()
  "The preview stops being \"live\" once point moves away from it."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completions . ["1;"])))))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (should (pascal1981--completion-overlay-live-p))
    (goto-char (point-min))
    (should-not (pascal1981--completion-overlay-live-p))))

(ert-deftest pascal1981-tests-completion-dismiss-clears-overlay-and-state ()
  "`pascal1981--completion-dismiss' tears the preview down completely."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completions . ["1;"])))))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (pascal1981--completion-dismiss)
    (should-not pascal1981--completion-overlay)
    (should-not pascal1981--completion-text)
    (should (equal (buffer-string) "x := "))))

(ert-deftest pascal1981-tests-completion-preserves-right-hand-text ()
  "A preview still shows when whitespace (not just EOL) follows point.
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
                      200 '((completions . ["1;"])))))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (should (equal (buffer-string) "x :=    "))
    (should (pascal1981--completion-overlay-live-p))))

(ert-deftest pascal1981-tests-completion-transport-error-no-preview ()
  "A `:error' status shows no preview and leaves the buffer untouched."
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
    (should (equal (buffer-string) "x := "))
    (should-not pascal1981--completion-overlay)))

(ert-deftest pascal1981-tests-completion-http-error-no-preview ()
  "A non-200 status shows no preview and leaves the buffer untouched."
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
    (should (equal (buffer-string) "x := "))
    (should-not pascal1981--completion-overlay)))

(ert-deftest pascal1981-tests-completion-malformed-json-no-preview ()
  "A body that isn't JSON shows no preview and leaves the buffer untouched."
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
    (should (equal (buffer-string) "x := "))
    (should-not pascal1981--completion-overlay)))

(ert-deftest pascal1981-tests-completion-empty-completions-list-no-preview ()
  "An empty \"completions\" list shows no preview and leaves the buffer alone."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completions . [])))))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (should (equal (buffer-string) "x := "))
    (should-not pascal1981--completion-overlay)))

(ert-deftest pascal1981-tests-completion-stale-response-discarded ()
  "A response for a superseded request id is discarded, no preview shown."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completions . ["1;"])))))
      ;; A newer request superseded this one before the response arrived.
      (setq pascal1981--completion-pending-id 2)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (should (equal (buffer-string) "x := "))
    (should-not pascal1981--completion-overlay)))

(ert-deftest pascal1981-tests-completion-buffer-changed-since-request-discarded ()
  "A response is discarded, no preview shown, if the buffer changed since
the request was sent."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completions . ["1;"])))))
      (setq pascal1981--completion-pending-id request-id)
      ;; The buffer changes after the request was sent, before it answers.
      (insert "y")
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (should (equal (buffer-string) "x := y"))
    (should-not pascal1981--completion-overlay)))

;; -------------------------------------------------------------------
;; LLM completion: TAB dispatcher
;; -------------------------------------------------------------------

(ert-deftest pascal1981-tests-multiline-accept-schedules-not-blocks-refresh ()
  "Accepting multiline text schedules refresh instead of running it in TAB."
  (with-temp-buffer
    (pascal1981-mode)
    (let (scheduled)
      (cl-letf (((symbol-function 'pascal1981--schedule-refresh)
                 (lambda () (setq scheduled t)))
                ((symbol-function 'pascal1981--refresh-caches)
                 (lambda () (error "refresh ran synchronously"))))
        (pascal1981--completion-show-ghost "alpha\nbeta")
        (pascal1981-completion-reveal-more)
        (pascal1981--completion-do-accept))
      (should scheduled)
      (should (equal (buffer-string) "alpha\nbeta"))
      (should pascal1981--completion-accept-barrier))))

(ert-deftest pascal1981-tests-acceptance-barrier-blocks-second-tab-request ()
  "A second TAB at accepted text cannot immediately request completion."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (let (sent)
      (cl-letf (((symbol-function 'pascal1981--schedule-refresh) #'ignore)
                ((symbol-function 'pascal1981--completion-send)
                 (lambda (&rest _) (setq sent t))))
        (pascal1981--completion-show-ghost "1;")
        (pascal1981--completion-do-accept)
        (pascal1981-indent-or-complete)
        (should-not sent)
        (insert " ")
        (pascal1981-indent-or-complete))
      (should sent))))

(ert-deftest pascal1981-tests-double-tab-after-acceptance-sends-no-second-request ()
  "A mocked completion followed by two TAB dispatches makes one LLM call."
  (let ((log-buffer-name "*pascal1981-completion-log*")
        (response-buffer (pascal1981-tests--fake-response-buffer
                          200 '((completions . ["1;"])))))
    (unwind-protect
        (with-temp-buffer
          (pascal1981-mode)
          (setq pascal1981-completion-enabled t)
          (insert "x := ")
          (let ((pascal1981-completion-debug-log t)
                (request-count 0))
            (cl-letf (((symbol-function 'pascal1981--schedule-refresh) #'ignore)
                      ((symbol-function 'url-retrieve)
                       (lambda (_url callback callback-args &rest _)
                         (setq request-count (1+ request-count))
                         (with-current-buffer response-buffer
                           (apply callback nil callback-args))
                         response-buffer)))
              (pascal1981-complete-line)
              (should (pascal1981--completion-overlay-live-p))
              (pascal1981-indent-or-complete)
              (pascal1981-indent-or-complete))
            (should (= request-count 1))
            (with-current-buffer (get-buffer log-buffer-name)
              (should (= (how-many "^SEND" (point-min) (point-max)) 1)))
            (should (equal (buffer-string) "x := 1;"))
            (cancel-timer pascal1981--completion-timeout-timer)))
      (when (get-buffer log-buffer-name)
        (kill-buffer log-buffer-name))
      (when (buffer-live-p response-buffer)
        (kill-buffer response-buffer)))))

(ert-deftest pascal1981-tests-indent-or-complete-dispatches-to-completion ()
  "Enabled and eligible, no preview showing: TAB requests, doesn't indent."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let (sent indented)
      (cl-letf (((symbol-function 'pascal1981--completion-send)
                 (lambda (&rest _) (setq sent t)))
                ((symbol-function 'pascal1981-indent-line)
                 (lambda () (setq indented t))))
        (pascal1981-indent-or-complete))
      (should sent)
      (should-not indented))))

(ert-deftest pascal1981-tests-indent-or-complete-accepts-live-preview ()
  "A preview already showing at point: TAB accepts it, doesn't re-request."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (let* ((source (current-buffer))
           (request-id 1)
           (tick (buffer-modified-tick))
           (pt (point))
           (response (pascal1981-tests--fake-response-buffer
                      200 '((completions . ["1;"])))))
      (setq pascal1981--completion-pending-id request-id)
      (pascal1981-tests--completion-respond source response request-id pt tick))
    (let (sent)
      (cl-letf (((symbol-function 'pascal1981--completion-send)
                 (lambda (&rest _) (setq sent t))))
        (pascal1981-indent-or-complete))
      (should-not sent)
      (should (equal (buffer-string) "x := 1;")))))

(ert-deftest pascal1981-tests-indent-or-complete-falls-back-mid-line ()
  "Mid-line point falls back to ordinary indentation, never completion."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (save-excursion (insert "1"))
    (let (sent indented)
      (cl-letf (((symbol-function 'pascal1981--completion-send)
                 (lambda (&rest _) (setq sent t)))
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
                 (lambda (&rest _) (setq sent t)))
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
                 (lambda (&rest _) (setq sent t)))
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
;; LLM completion: real key dispatch through the command loop
;; -------------------------------------------------------------------
;;
;; Every test above calls elisp functions (`pascal1981-indent-or-complete',
;; `pascal1981-completion-reveal-more', etc.) directly -- which never
;; exercises `set-transient-map's own machinery. `set-transient-map'
;; evaluates its KEEP-PRED (and, when that says "don't keep", calls
;; ON-EXIT) from `pre-command-hook', which runs BEFORE the command bound
;; to the triggering key is actually invoked. A bug where TAB's bound
;; command reads state that a blanket on-exit dismissal already cleared
;; is invisible to direct function calls -- it only shows up when TAB is
;; actually pressed. These tests drive real key sequences through
;; `execute-kbd-macro' against a genuinely selected buffer (not a
;; `with-temp-buffer', which is never "selected" and so does not reliably
;; stay current through real command dispatch in batch mode) to catch
;; exactly that class of bug.

(ert-deftest pascal1981-tests-real-tab-accepts-live-preview ()
  "A real TAB keypress, not a direct function call, materializes the
completion currently shown by a live preview."
  (pascal1981-tests--with-selected-buffer "pascal1981-tests-real-tab"
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (pascal1981--completion-show-ghost "1;")
    (execute-kbd-macro (kbd "TAB"))
    (should (equal (buffer-string) "x := 1;"))
    (should-not pascal1981--completion-overlay)))

(ert-deftest pascal1981-tests-real-tab-releases-map-after-accept ()
  "After a real TAB accepts a preview, a later TAB is not still captured
by a leftover transient map -- it dispatches normally again."
  (pascal1981-tests--with-selected-buffer "pascal1981-tests-real-tab-release"
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (pascal1981--completion-show-ghost "1;")
    (execute-kbd-macro (kbd "TAB"))
    (setq pascal1981-completion-enabled nil)
    (insert "\n  y")
    (cl-letf (((symbol-function 'pascal1981-indent-line)
               (lambda () (insert "<INDENTED>"))))
      (execute-kbd-macro (kbd "TAB")))
    (should (equal (buffer-string) "x := 1;\n  y<INDENTED>"))))

(ert-deftest pascal1981-tests-real-m-n-reveals-and-real-tab-accepts-shown-lines ()
  "Real M-n keypresses reveal more lines of the preview; a real TAB after
that materializes whatever is currently shown, not the whole completion."
  (pascal1981-tests--with-selected-buffer "pascal1981-tests-real-reveal"
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (pascal1981--completion-show-ghost "1;\n2;\n3;")
    (execute-kbd-macro (kbd "M-n"))
    (execute-kbd-macro (kbd "M-n"))
    (execute-kbd-macro (kbd "TAB"))
    (should (equal (buffer-string) "x := 1;\n2;\n3;"))))

(ert-deftest pascal1981-tests-real-c-g-dismisses-without-inserting ()
  "A real C-g dismisses the preview and inserts nothing."
  (pascal1981-tests--with-selected-buffer "pascal1981-tests-real-c-g"
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (pascal1981--completion-show-ghost "1;")
    (execute-kbd-macro (kbd "C-g"))
    (should (equal (buffer-string) "x := "))
    (should-not pascal1981--completion-overlay)))

(ert-deftest pascal1981-tests-real-typing-dismisses-preview ()
  "Typing a real character dismisses the preview; the ghost text is
never inserted, only the typed character is."
  (pascal1981-tests--with-selected-buffer "pascal1981-tests-real-typing"
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "x := ")
    (pascal1981--completion-show-ghost "1;")
    (execute-kbd-macro (kbd "9"))
    (should (equal (buffer-string) "x := 9"))
    (should-not pascal1981--completion-overlay)))

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

(ert-deftest pascal1981-tests-end-to-end-fake-proxy-shows-and-accepts-completion ()
  "A real HTTP round trip against a local fake proxy shows a preview; a
real TAB keypress (not a direct function call) materializes it into
the buffer."
  (pascal1981-tests--with-fake-proxy
      (pascal1981-tests--http-json-response
       200 '((completions . ["TO 10 DO"]) (model . "test-model")
             (request_id . "e2e-1")))
    (pascal1981-tests--with-selected-buffer "pascal1981-tests-e2e-accept"
      (pascal1981-mode)
      (setq pascal1981-completion-enabled t
            pascal1981-completion-timeout 5)
      (insert "FOR i := 1 ")
      (pascal1981-complete-line)
      (pascal1981-tests--wait-until
       (lambda () (not pascal1981--completion-pending-id)) 5)
      (should (equal (buffer-string) "FOR i := 1 "))
      (should (pascal1981--completion-overlay-live-p))
      (execute-kbd-macro (kbd "TAB"))
      (should (equal (buffer-string) "FOR i := 1 TO 10 DO")))))

(ert-deftest pascal1981-tests-end-to-end-multiline-accept-reindents ()
  "Accepting a multi-line candidate, after revealing all of its lines,
reindents the inserted lines via the asynchronous lexer/token cache,
instead of leaving the model's raw, unindented text. (Only its first line is
shown by default; `M-n' reveals the rest first -- see the reveal
tests above for that behavior in isolation.)"
  (pascal1981-tests--with-fake-proxy
      (pascal1981-tests--http-json-response
       200 '((completions . ["BEGIN\ntotal := total + i;\nEND;"])
             (model . "test-model") (request_id . "e2e-multiline")))
    (pascal1981-tests--with-selected-buffer "pascal1981-tests-e2e-multiline"
      (pascal1981-mode)
      (setq pascal1981-completion-enabled t
            pascal1981-completion-timeout 5)
      (insert "PROGRAM Demo;\nBEGIN\n  ")
      (pascal1981-complete-line)
      (pascal1981-tests--wait-until
       (lambda () (not pascal1981--completion-pending-id)) 5)
      (should (pascal1981--completion-overlay-live-p))
      (execute-kbd-macro (kbd "M-n M-n TAB"))
      (pascal1981-tests--wait-until
       (lambda () (equal (buffer-string)
                          "PROGRAM Demo;\nBEGIN\n  BEGIN\n    total := total + i;\n  END;"))
       5)
      (should (equal (buffer-string)
                     "PROGRAM Demo;\nBEGIN\n  BEGIN\n    total := total + i;\n  END;")))))

(ert-deftest pascal1981-tests-end-to-end-lexical-unit-slice-still-completes ()
  "A buffer whose whole text exceeds `pascal1981-completion-buffer-limit'
still gets a completion, as long as the lexical-unit slice around
point (which excludes an unrelated, much larger procedure elsewhere in
the file) fits -- exercised through the real send path, not just the
`pascal1981--completion-request-text' helper in isolation. Without
slicing, this request would be refused before ever reaching the proxy."
  (pascal1981-tests--with-fake-proxy
      (pascal1981-tests--http-json-response
       200 '((completions . ["x := 1;"])
             (model . "test-model") (request_id . "e2e-slice")))
    (pascal1981-tests--with-selected-buffer "pascal1981-tests-e2e-slice"
      (pascal1981-mode)
      (setq pascal1981-completion-enabled t
            pascal1981-completion-timeout 5
            pascal1981-completion-lexical-unit-threshold 50
            pascal1981-completion-buffer-limit 300)
      (insert "PROGRAM P;\nVAR N: INTEGER;\nPROCEDURE Foo;\nBEGIN\n  N := 1")
      (let ((point-in-foo (point)))
        (insert (concat "\nEND;\nPROCEDURE Bar;\nBEGIN\n"
                        (apply #'concat
                               (make-list 60 "  N := N + 1;\n"))
                        "END;\nBEGIN\nEND.\n"))
        (goto-char point-in-foo))
      ;; pascal1981-mode was enabled on an empty buffer above; real
      ;; edits only refresh the token cache via an idle timer, which
      ;; this test does not wait for -- force it synchronously so
      ;; slicing has a token cache to work from, the same as it would
      ;; have after the idle delay in real use.
      (pascal1981--refresh-caches)
      ;; Point is right after "N := 1", nothing but whitespace to EOL --
      ;; eligible per `pascal1981--completion-allowed-at-point-p'.
      ;; Whole buffer is well over 300 chars; the slice around point
      ;; (declarations + Foo only, excluding Bar's padding) is not.
      (should (> (buffer-size) pascal1981-completion-buffer-limit))
      (pascal1981-complete-line)
      (pascal1981-tests--wait-until
       (lambda () (not pascal1981--completion-pending-id)) 5)
      (should (pascal1981--completion-overlay-live-p)))))

(ert-deftest pascal1981-tests-end-to-end-fake-proxy-http-error-no-preview ()
  "A real HTTP round trip returning a non-200 status shows no preview and
leaves the buffer alone."
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
      (should (equal (buffer-string) "FOR i := 1 "))
      (should-not pascal1981--completion-overlay))))

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

;; -------------------------------------------------------------------
;; LLM completion: junk-response corpus
;; -------------------------------------------------------------------
;;
;; What a low-parameter LLM, or a proxy speaking for one, actually sends
;; when things go wrong. The proxy sanitizes its own output, but this mode
;; speaks HTTP to whatever is listening at `pascal1981-completion-proxy-
;; url' -- which need not be the bundled proxy -- so the client is checked
;; here against the raw article rather than against the proxy's promises.
;;
;; The invariant asserted is the same for every case: no preview appears,
;; the buffer is untouched, no error is signaled, and the request is
;; retired rather than left pending forever.

(defconst pascal1981-tests--junk-responses
  `(("empty completion string" . ((completions . [""])))
    ("whitespace-only completion" . ((completions . ["   \t  "])))
    ("newline-only completion" . ((completions . ["\n\n"])))
    ("empty completions array" . ((completions . [])))
    ("null inside completions" . ((completions . [:null])))
    ("completions is a string" . ((completions . "x := 1;")))
    ("completions is an object" . ((completions . ((text . "x := 1;")))))
    ("completions holds a number" . ((completions . [42])))
    ("missing completions key" . ((model . "test-model")))
    ("carriage return" . ((completions . ["x := 1;\r\ny := 2;"])))
    ("escape sequence" . ((completions . ["\e[31mx := 1;\e[0m"])))
    ("control characters" . ((completions . ["x :=\001\002 1;"])))
    ("oversized completion"
     . ((completions . [,(make-string 20000 ?A)]))))
  "Alist of LABEL -> JSON body that must never produce a preview.")

(defun pascal1981-tests--junk-round-trip (response)
  "Drive one real HTTP round trip against RESPONSE (raw HTTP bytes).
Return the resulting buffer text; asserts no preview is showing."
  (pascal1981-tests--with-fake-proxy response
    (with-temp-buffer
      (pascal1981-mode)
      (setq pascal1981-completion-enabled t
            pascal1981-completion-timeout 3)
      (insert "FOR i := 1 ")
      (pascal1981-complete-line)
      (pascal1981-tests--wait-until
       (lambda () (not pascal1981--completion-pending-id)) 6)
      (should-not pascal1981--completion-pending-id)
      (should-not (pascal1981--completion-overlay-live-p))
      (buffer-string))))

(ert-deftest pascal1981-tests-junk-completions-never-preview ()
  "Every entry in `pascal1981-tests--junk-responses' is rejected: no
preview, no buffer change, no error."
  (dolist (case pascal1981-tests--junk-responses)
    (let ((label (car case)))
      (should (equal (cons label
                           (pascal1981-tests--junk-round-trip
                            (pascal1981-tests--http-json-response
                             200 (cdr case))))
                     (cons label "FOR i := 1 "))))))

(ert-deftest pascal1981-tests-junk-http-statuses-never-preview ()
  "A non-200 status is rejected even when its body looks well-formed."
  (dolist (status '(400 404 500 502 503))
    (should (equal (pascal1981-tests--junk-round-trip
                    (pascal1981-tests--http-json-response
                     status '((completions . ["x := 1;"]))))
                   "FOR i := 1 "))))

(ert-deftest pascal1981-tests-junk-non-json-body-never-previews ()
  "A body that is not JSON at all is rejected rather than signaling."
  (dolist (body '("not json at all"
                  "<html><body>502 Bad Gateway</body></html>"
                  ""
                  "{\"completions\": [\"x := 1;\""))
    (should (equal (pascal1981-tests--junk-round-trip
                    (concat "HTTP/1.1 200 OK\r\n"
                            "Content-Type: application/json\r\n"
                            (format "Content-Length: %d\r\n"
                                    (string-bytes body))
                            "Connection: close\r\n\r\n"
                            body))
                   "FOR i := 1 "))))

(ert-deftest pascal1981-tests-usable-completion-predicate ()
  "`pascal1981--completion-usable-p' accepts real source and rejects the
empty, the oversized, and the control-character-bearing."
  (should (pascal1981--completion-usable-p "TO 10 DO"))
  (should (pascal1981--completion-usable-p "BEGIN\n  x := 1;\nEND;"))
  (should (pascal1981--completion-usable-p "\tx := 1;"))
  (should-not (pascal1981--completion-usable-p ""))
  (should-not (pascal1981--completion-usable-p "   \n\t "))
  (should-not (pascal1981--completion-usable-p "x := 1;\r"))
  (should-not (pascal1981--completion-usable-p "x :=\e[0m 1;"))
  (should-not (pascal1981--completion-usable-p 42))
  (let ((pascal1981-completion-max-chars 16))
    (should-not (pascal1981--completion-usable-p (make-string 17 ?A)))
    (should (pascal1981--completion-usable-p (make-string 16 ?A)))))

(ert-deftest pascal1981-tests-multibyte-completion-round-trips ()
  "Non-ASCII in a completion survives the round trip as characters, not
as the raw UTF-8 bytes `json-read' would have handed back undecoded."
  (pascal1981-tests--with-fake-proxy
      (pascal1981-tests--http-json-response
       200 '((completions . ["WRITELN('café')"])))
    (pascal1981-tests--with-selected-buffer "pascal1981-tests-multibyte"
      (pascal1981-mode)
      (setq pascal1981-completion-enabled t
            pascal1981-completion-timeout 5)
      (insert "  ")
      (pascal1981-complete-line)
      (pascal1981-tests--wait-until
       (lambda () (not pascal1981--completion-pending-id)) 6)
      (should (pascal1981--completion-overlay-live-p))
      (execute-kbd-macro (kbd "TAB"))
      (should (equal (buffer-string) "  WRITELN('café')")))))

(ert-deftest pascal1981-tests-in-flight-request-blocks-a-second ()
  "A second TAB while a request is in flight does not fire another one.
Every TAB used to send its own; the forking proxy accepted them all and
piled them onto a backend that serves one request at a time."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "FOR i := 1 ")
    (let ((sends 0))
      (cl-letf (((symbol-function 'url-retrieve)
                 (lambda (&rest _) (cl-incf sends) nil)))
        (pascal1981-complete-line)
        (pascal1981-complete-line)
        (pascal1981-complete-line))
      (should (= sends 1))
      (should pascal1981--completion-pending-id))))

(ert-deftest pascal1981-tests-failed-send-does-not-wedge-the-in-flight-guard ()
  "A `url-retrieve' that signals clears the pending id.
Otherwise the in-flight guard would refuse every later completion in
this buffer -- a typo in `pascal1981-completion-proxy-url' would
disable completion until the buffer was killed."
  (with-temp-buffer
    (pascal1981-mode)
    (setq pascal1981-completion-enabled t)
    (insert "FOR i := 1 ")
    (cl-letf (((symbol-function 'url-retrieve)
               (lambda (&rest _) (error "no handler for this scheme"))))
      (pascal1981-complete-line))
    (should-not pascal1981--completion-pending-id)
    ;; And a later request is still allowed through.
    (let ((sends 0))
      (cl-letf (((symbol-function 'url-retrieve)
                 (lambda (&rest _) (cl-incf sends) nil)))
        (pascal1981-complete-line))
      (should (= sends 1)))))

(ert-deftest pascal1981-tests-multiline-accept-preserves-indent-without-lexer ()
  "Accepting a multi-line completion when the lexer is unavailable leaves
the surrounding indentation alone.

`pascal1981--compute-indent' answers 0 for every line when the token
cache is nil, so an unguarded reindent pass does not leave indentation
as-is -- it flattens it to column 0. A nil cache is the expected case
here, not a remote one: the inserted text came from an LLM, and a
partial statement is exactly what makes the lexer fail."
  (with-temp-buffer
    (pascal1981-mode)
    (let ((pascal1981-lexer-program "pascal1981-no-such-lexer-binary")
          (pascal1981-parser-program "pascal1981-no-such-parser-binary"))
      (insert "PROGRAM P;\nBEGIN\n    ")
      (pascal1981--completion-insert "x := 1;\n    y := 2;")
      (should (equal (buffer-string)
                     "PROGRAM P;\nBEGIN\n    x := 1;\n    y := 2;")))))

(provide 'pascal1981-mode-tests)
;;; pascal1981-mode-tests.el ends here
