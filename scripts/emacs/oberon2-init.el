;;; oberon2-init.el --- Load the Oberon-2 major mode  -*- lexical-binding: t -*-
;;
;; Add one line to your ~/.emacs (or ~/.emacs.d/init.el), with the
;; path to this file in this checkout:
;;
;;   (load-file "/path/to/oberon/scripts/emacs/oberon2-init.el")
;;
;; Everything else -- loading oberon2.el and associating it with
;; '.Mod' files -- happens here.
;;
;; The mode's "C-c <letter>" construct-insertion keybindings (begin,
;; case, if, ...) are off by default -- see oberon2.el's
;; 'o2-enable-command-keybindings' for why.  To get them, set that
;; variable to t *before* the (load-file ...) line above, e.g.:
;;
;;
;; To load Oberon-2 mode, add a line similar to the following in your
;; ~/.emacs:
;;
;;   (setq o2-enable-command-keybindings t)
;;   (load-file "/path/to/oberon/scripts/emacs/oberon2-init.el")
;;
;; If you want to enable the Oberon-2 programming templates, set
;; o2-enable-command-keybindings.
;;
;; The mode will take affect for files loaded *after* the mode is
;; loaded.
;;

(load-file (expand-file-name "oberon2.el"
                             (file-name-directory load-file-name)))

(add-to-list 'auto-mode-alist '("\\.Mod\\'" . o2-mode))

(provide 'oberon2-init)
;;; oberon2-init.el ends here
