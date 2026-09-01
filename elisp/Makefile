# Makefile for pascal1981-mode, the Emacs major mode.
#
# Standalone on purpose: the top-level `make test` does not call this,
# because the mode needs Emacs and the compiler itself does not.
#
#   make -C elisp test
#
# The tests need the stage binaries `lexer` and `parser`, plus the
# driver (`pascal1981`), on PATH.  Most of them carry `skip-unless`, so
# a run without those binaries reports success while it exercises
# almost nothing.  The test target fails instead, and names the
# missing binary.

EMACS   ?= emacs
ROOT    := $(abspath $(dir $(abspath $(lastword $(MAKEFILE_LIST))))..)
BIN_DIR := $(ROOT)/bin
STAGES  := lexer parser pascal1981
TESTS   := pascal1981-mode-tests.el

.PHONY: all test check-binaries compile clean

all: test

# Run the ERT suite with the stage binaries on PATH.
test: check-binaries
	PATH="$(BIN_DIR):$$PATH" $(EMACS) -Q --batch -L . \
	  -l $(TESTS) \
	  -f ert-run-tests-batch-and-exit

# A skipped test is not a passing test.  Fail before Emacs starts.
check-binaries:
	@for stage in $(STAGES); do \
	  if [ ! -x "$(BIN_DIR)/$$stage" ]; then \
	    echo "elisp/Makefile: missing $(BIN_DIR)/$$stage" >&2; \
	    echo "Build the stages first: make -C $(ROOT) bootstrap" >&2; \
	    exit 1; \
	  fi; \
	done

# Byte-compile to surface warnings.  Not part of `test`.
compile:
	$(EMACS) -Q --batch -L . -f batch-byte-compile pascal1981-mode.el

clean:
	rm -f *.elc
