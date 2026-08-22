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

(provide 'pascal1981-mode-tests)
;;; pascal1981-mode-tests.el ends here
