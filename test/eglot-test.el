;;; eglot-test.el --- the real eglot against clotran lsp  -*- lexical-binding: t; -*-

;; Run by test/run.sh in a headless Emacs 29 (eglot is built in):
;;   LSP_TEST_PROJ=.../test/fixtures/proj CLOTRAN_PROGRAM=.../clotran emacs --batch -l test/eglot-test.el
;; eglot starts `clotran lsp' in the fixture project, as a user's would,
;; and this asks it what a user asks: a definition (M-.), the hover
;; documentation, and clotran's own form-at-point.

(require 'package)
(package-initialize)
(require 'clojure-mode)
(require 'eglot)
(require 'xref)

(defvar ct-proj (file-name-as-directory (getenv "LSP_TEST_PROJ")))
(defvar ct-program (or (getenv "CLOTRAN_PROGRAM") "clotran"))
(defvar ct-fails 0)
(defun ct-check (label got want)
  (if (equal got want)
      (message "ok   - %s" label)
    (setq ct-fails (1+ ct-fails))
    (message "FAIL - %s\n  got:  %S\n  want: %S" label got want)))

(add-to-list 'auto-mode-alist '("\\.cljf\\'" . clojure-mode))
(setq eglot-sync-connect t
      eglot-connect-timeout 60
      eglot-autoshutdown t)
;; the fixture is the project, not the git repository it sits in: eglot
;; starts the server in the project's directory and manages its buffers
(add-hook 'project-find-functions
          (lambda (dir) (when (string-prefix-p ct-proj (file-name-as-directory (expand-file-name dir)))
                          (cons 'transient ct-proj)))
          -90)

(find-file (expand-file-name "src/app/core.cljf" ct-proj))
(let* ((project (project-current))
       (server (eglot 'clojure-mode project 'eglot-lsp-server (list ct-program "lsp") "clojure")))
  (ct-check "eglot connected to clotran lsp, which names itself"
            (plist-get (eglot--server-info server) :name) "clotran-ide")
  (ct-check "the server declares definitions and hover"
            (list (and (eglot--server-capable :definitionProvider) t)
                  (and (eglot--server-capable :hoverProvider) t))
            '(t t))
  ;; M-. on u/shout
  (goto-char (point-min))
  (search-forward "u/shout")
  (backward-char 2)
  (xref-find-definitions (xref-backend-identifier-at-point 'eglot))
  (ct-check "M-. on u/shout lands on app.util's defn"
            (list (file-name-nondirectory (buffer-file-name)) (line-number-at-pos))
            '("util.cljf" 3))
  (switch-to-buffer (find-buffer-visiting (expand-file-name "src/app/core.cljf" ct-proj)))
  (goto-char (point-min))
  (search-forward "u/shout")
  (backward-char 2)
  (let ((hover (jsonrpc-request server :textDocument/hover (eglot--TextDocumentPositionParams))))
    (ct-check "hover on u/shout carries the docstring"
              (and (string-match-p "Louder\\." (plist-get (plist-get hover :contents) :value)) t)
              t))
  (let ((form (jsonrpc-request server :clotran/formAtPoint (eglot--TextDocumentPositionParams))))
    (ct-check "clotran/formAtPoint answers the defn around point"
              (and (string-prefix-p "(defn greet" (plist-get form :text)) t)
              t))
  (eglot-shutdown server))

(message "%s" (if (zerop ct-fails) "EGLOT TEST PASSED" (format "EGLOT TEST FAILED: %d" ct-fails)))
(kill-emacs (if (zerop ct-fails) 0 1))
;;; eglot-test.el ends here
