#!/bin/sh
# test/run.sh -- the language server against its own client
# (test/lsp_test.cljf) in one process; then `clotran lsp` itself, the
# same requests over its standard input and output; then the JSON codec
# against cheshire (scripts/fuzz-json, when bb is on PATH).
# CLOTRAN is the clotran checkout (default: beside this repository).
here=$(cd "$(dirname "$0")/.." && pwd)
CLOTRAN=${CLOTRAN:-$here/../clotran}
proj=$here/test/fixtures/proj
export LSP_TEST_PROJ="$proj"
export CLOTRAN_PATH="$here/src:$proj/src"
run() { "$CLOTRAN/clotran-bin" "$CLOTRAN/src/clj/clojure/core.clj" "$@" </dev/null 2>&1 | grep -v '^note:\|^user=>'; }

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT

echo "--- in one process, over memory ---"
LSP_TEST= run "$here/test/lsp_test.cljf" | tee "$work/1.txt"
grep -q '^LSP TEST PASSED' "$work/1.txt" || exit 1

echo "--- clotran lsp, over its stdio, in the fixture project ---"
LSP_TEST=write LSP_TEST_FILE="$work/session.bin" run "$here/test/lsp_test.cljf"
( cd "$proj" && CLOTRAN_IDE="$here" "$CLOTRAN/clotran" lsp --verbose < "$work/session.bin" > "$work/out.bin" 2> "$work/err.txt" )
st=$?
if [ $st -ne 0 ]; then echo "clotran lsp exited $st:"; cat "$work/err.txt"; exit 1; fi
LSP_TEST=check LSP_TEST_FILE="$work/out.bin" run "$here/test/lsp_test.cljf" | tee "$work/2.txt"
grep -q '^LSP STDIO TEST PASSED' "$work/2.txt" || { echo "the server said:"; cat "$work/err.txt"; exit 1; }

# the real eglot, headless, when there is an Emacs 29 with clojure-mode:
# EMACS, else the macOS application, else an emacs on PATH
emacs=${EMACS:-}
[ -z "$emacs" ] && [ -x /Applications/Emacs.app/Contents/MacOS/Emacs ] && emacs=/Applications/Emacs.app/Contents/MacOS/Emacs
[ -z "$emacs" ] && emacs=$(command -v emacs 2>/dev/null)
if [ -n "$emacs" ] && "$emacs" --batch --eval "(progn (package-initialize) (require (quote clojure-mode)) (require (quote eglot)))" >/dev/null 2>&1; then
  echo "--- eglot, in a headless Emacs ---"
  CLOTRAN_IDE="$here" CLOTRAN_PROGRAM="$CLOTRAN/clotran" "$emacs" --batch -l "$here/test/eglot-test.el" > "$work/3.txt" 2>&1
  grep '^ok   -\|^FAIL\|TEST' "$work/3.txt"
  grep -q '^EGLOT TEST PASSED' "$work/3.txt" || { cat "$work/3.txt"; exit 1; }
else
  echo "(no Emacs with clojure-mode and eglot: the eglot check is skipped)"
fi

if command -v bb >/dev/null; then
  echo "--- the JSON codec against cheshire ---"
  CLOTRAN="$CLOTRAN" bb "$here/scripts/fuzz-json" 150 || exit 1
else
  echo "(bb not found: the JSON check against cheshire is skipped)"
fi
echo "ALL PASSED"
