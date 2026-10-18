# clotran-ide

The language server for [clotran](https://github.com/clotran/clotran)
-- Clojure hosted on Fortran -- and, to come, its debug adapter. One
server, every editor's own client: Emacs's eglot, Neovim's built-in
client, VS Code through the clotran extension.

**Status (2026-10-18): the language server serves.** `clotran lsp`
answers, over the process's standard input and output (or `--port N`):

| request | what |
|---|---|
| `textDocument/definition` | into Clojure, and into the Fortran of a package (`mylib.raw/scale` goes to the subroutine) |
| `textDocument/hover` | the signature, arglists and docstring |
| `textDocument/documentSymbol`, `workspace/symbol` | a file's definitions; a search over the project's |
| `textDocument/completion` | names in the file's namespace, what it refers, clojure.core, and `alias/` |
| `textDocument/publishDiagnostics` | what the reader refuses, at its line and column, as you type; for a Fortran file the compiler's `-fsyntax-only` on open and save |
| `textDocument/formatting`, `rangeFormatting`, `onTypeFormatting` | [cljfmt on clotran](https://github.com/clotran/cljfmt): the document, the forms a range touches, or the form being typed in (after a newline or a closing bracket), with the project's `.cljfmt.edn` |
| `clotran/formAtPoint` | the top-level form around a position: `{text range}`, for evaluating at the cursor |
| `clotran/namespace` | the file's namespace |

None of it needs a REPL. Everything comes from clotran's own index
(`clotran index`, clotran.index), read by the reader that loads the
code and never evaluated, so a position here is the one `(meta #'var)`
answers; the editor's unsaved text is read in the file's place.
Positions on the wire are LSP's UTF-16 ones, converted against each
line.

## The pieces

- `clotran.ide.json` -- JSON, RFC 8259, read and written. The oracle
  is cheshire on babashka: `scripts/fuzz-json` round-trips random
  values and checks that whatever cheshire refuses, this refuses.
- `clotran.ide.rpc` -- the `Content-Length` framing over BYTES, on
  three transports: the process's stdio (clotran's
  `clotran-stdin-read-bytes` and `clotran-stdout-write-bytes`), a
  clotran.net connection, and memory, for the tests.
- `clotran.ide.lsp` -- the server: the index, the open documents, the
  requests above, and `main` for `clotran lsp [--port N] [--verbose]`.

## Using it

clotran's launcher starts it: `clotran lsp` in a project's directory,
the server from a checkout beside clotran, `CLOTRAN_IDE=dir`, or the
commit clotran's `tools.edn` pins, fetched into the cache by
clotran-deps on first use. No project's `deps.edn` names it.

Emacs 29 (eglot is built in):

```elisp
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs '(clojure-mode . ("clotran" "lsp"))))
```

Neovim:

```lua
vim.api.nvim_create_autocmd("FileType", {pattern = "clojure", callback = function()
  vim.lsp.start({name = "clotran", cmd = {"clotran", "lsp"}, root_dir = vim.fs.root(0, "deps.edn")})
end})
```

## Tests

`test/run.sh` runs `test/lsp_test.cljf` three ways -- the server in
one process over memory; `clotran lsp` itself, the same requests over
its stdio in the fixture project `test/fixtures/proj`; the answers
checked -- then `test/eglot-test.el`, the real eglot in a headless
Emacs, when there is one, and `scripts/fuzz-json`. Each definition's
position is checked against the Var the loaded fixture file makes.
`CLOTRAN=dir` names the clotran checkout (default: beside this one).
