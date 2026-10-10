;;; oberon2.el --- Oberon-2 editing support package  -*- lexical-binding: t -*-

;; This file is a cloned and modified version of GNU Emacs's
;; modula2.el major mode, adapted for editing Oberon-2 code.

;; Original attribution for Modula-2 follows:

;; Author: Michael Schmidt <michael@pbinfo.UUCP>
;;	Tom Perrine <Perrin@LOGICON.ARPA>
;; Maintainer: emacs-devel@gnu.org
;; Keywords: languages

;; This file is part of GNU Emacs.

;; The authors distributed this without a copyright notice
;; back in 1988, so it is in the public domain.  The original included
;; the following credit:

;; Author Mick Jordan
;; amended Peter Robinson

;;; Commentary:

;; A major mode for editing Oberon-2 code.  It provides convenient abbrevs
;; for Oberon-2 keywords, knows about the standard layout rules, and supports
;; a native compile command.

;;; Code:

(require 'smie)

(defgroup oberon2 nil
  "Major mode for editing Oberon-2 code."
  :link '(custom-group-link :tag "Font Lock Faces group" font-lock-faces)
  :prefix "o2-"
  :group 'languages)

;;; Added by Tom Perrine (TEP)
(defvar o2-mode-syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?\\ "\\" table)
    (modify-syntax-entry ?/ ". 12" table)
    (modify-syntax-entry ?\n ">" table)
    (modify-syntax-entry ?\( "()1" table)
    (modify-syntax-entry ?\) ")(4" table)
    (modify-syntax-entry ?* ". 23nb" table)
    (modify-syntax-entry ?+ "." table)
    (modify-syntax-entry ?- "." table)
    (modify-syntax-entry ?= "." table)
    (modify-syntax-entry ?% "." table)
    (modify-syntax-entry ?< "." table)
    (modify-syntax-entry ?> "." table)
    (modify-syntax-entry ?\' "\"" table)
    table)
  "Syntax table in use in Oberon-2 buffers.")

(defcustom o2-end-comment-column 75
  "Column for aligning the end of a comment, in Oberon-2."
  :type 'integer)

(defconst o2-comment-text-column-limit 79
  "Hard upper bound on where comment text may extend to, regardless of
`o2-end-comment-column' -- not user-customizable, unlike that
variable, since this is a fixed rule rather than a style preference.")

(defcustom o2-enable-command-keybindings nil
  "Whether `o2-mode-map' gets the mode's construct-insertion
keybindings (begin, case, if, and so on; see `o2-mode's docstring).
Most of them are plain \"C-c <letter>\" bindings, which Emacs\\='s own
coding conventions reserve for user customization, not major modes,
so they are opt-in here rather than on by default.

This is consulted once, while oberon2.el is being loaded, to decide
whether to populate the keymap at all -- set it, e.g. with
\"(setq o2-enable-command-keybindings t)\", *before* loading this
file.  Changing it afterward has no effect on an already-built
`o2-mode-map'."
  :type 'boolean)

(defvar-keymap o2-mode-map
  :doc "Keymap used in Oberon-2 mode.")

;; Unconditional, unlike the construct-insertion bindings below: this
;; is core comment-editing behavior (continuing a comment when RET is
;; pressed inside one), not an optional shortcut.
(keymap-set o2-mode-map "RET" #'o2-comment-newline)

(when o2-enable-command-keybindings
  ;; FIXME: Many of those bindings are contrary to coding conventions.
  (keymap-set o2-mode-map "C-c b"   #'o2-begin)
  (keymap-set o2-mode-map "C-c c"   #'o2-case)
  (keymap-set o2-mode-map "C-c e"   #'o2-else)
  (keymap-set o2-mode-map "C-c f"   #'o2-for)
  (keymap-set o2-mode-map "C-c h"   #'o2-header)
  (keymap-set o2-mode-map "C-c i"   #'o2-if)
  (keymap-set o2-mode-map "C-c l"   #'o2-loop)
  (keymap-set o2-mode-map "C-c o"   #'o2-or)
  (keymap-set o2-mode-map "C-c p"   #'o2-procedure)
  (keymap-set o2-mode-map "C-c C-w" #'o2-with)
  (keymap-set o2-mode-map "C-c r"   #'o2-record)
  (keymap-set o2-mode-map "C-c t"   #'o2-type)
  (keymap-set o2-mode-map "C-c u"   #'o2-until)
  (keymap-set o2-mode-map "C-c v"   #'o2-var)
  (keymap-set o2-mode-map "C-c w"   #'o2-while)
  (keymap-set o2-mode-map "C-c y"   #'o2-import)
  (keymap-set o2-mode-map "C-c {"   #'o2-begin-comment)
  (keymap-set o2-mode-map "C-c }"   #'o2-end-comment)
  (keymap-set o2-mode-map "C-c C-z" #'suspend-emacs))

(defcustom o2-indent 5
  "Indentation in Oberon-2 mode."
  :type 'integer
  :safe (lambda (v) (or (null v) (integerp v))))

(defconst o2-smie-grammar
  ;; Official grammar: "Syntax" section,
  ;; https://en.wikipedia.org/wiki/Oberon-2#Syntax.  As with the
  ;; original Modula-2 grammar this is based on, this SMIE grammar
  ;; does not try to be a complete parser -- only enough structure is
  ;; modeled to get sensible indentation.  Known gaps, kept from the
  ;; original or specific to Oberon-2, are marked FIXME below.
  ;;
  ;; A Receiver ("(" [VAR] ident ":" ident ")", for a type-bound
  ;; procedure) and the optional "(" Qualident ")" base type on
  ;; RECORD need no grammar rule of their own: both are balanced
  ;; parens handled transparently by Emacs's syntax-table paren
  ;; matching, the same way a procedure's FormalPars already is.
  (smie-prec2->grammar
   (smie-merge-prec2s
    (smie-bnf->prec2
     '((range) (id) (epsilon)
       (fields (fields ";" fields) (ids ":" type))
       (proctype (id ":" type))
       (type ("RECORD" fields "END")
             ("POINTER" "TO" type)
             ;; The PROCEDURE type is indistinguishable from the beginning
             ;; of a PROCEDURE definition, so we need a "PROCEDURE-type" to
             ;; prevent SMIE from trying to find the matching END.
             ("PROCEDURE-type" proctype)
             ;; OF's right hand side should bind tighter than ; for array
             ;; types, but should bind less tight than | which itself binds
             ;; less tight than ;.  So we use two distinct OFs.
             ("SET" "OF-type" id)
             ("ARRAY" range "OF-type" type))
       (args ("(" fargs ")"))
       ;; VAR has lower precedence than ";" in formal args, but not
       ;; in declarations.  So we use "VAR-arg" for the formal arg case.
       (farg (ids ":" type) ("VAR-arg" farg))
       (fargs (fargs ";" fargs) (farg))
       ;; Handling of PROCEDURE in decls is problematic: we'd want
       ;; TYPE/CONST/VAR/PROCEDURE's parent to be any previous
       ;; CONST/TYPE/VAR/PROCEDURE, but we also want PROCEDURE to be an opener
       ;; (so that its END has PROCEDURE as its parent).  So instead, we treat
       ;; the last ";" in those blocks as a separator (we call it ";-block").
       ;; FIXME: This means that "TYPE \n VAR" is not indented properly
       ;; because there's no ";-block" between the two.
       (decls (decls ";-block" decls)
              ("TYPE" typedecls) ("CONST" constdecls) ("VAR" vardecls)
              ("PROCEDURE" decls "BEGIN" insts "END")
              ;; A forward declaration ('PROCEDURE "^" ...') has no
              ;; body at all; its "^" is refined to "^-fwd" by
              ;; o2-smie-forward/backward-token (distinct from a
              ;; designator's postfix "^") precisely so it is *not*
              ;; treated as an ordinary "PROCEDURE" left hunting
              ;; forever for a "BEGIN" that will never come -- that
              ;; would mis-nest everything for the rest of the buffer,
              ;; not just the forward declaration itself.
              ("PROCEDURE" "^-fwd")
              )
       (typedecls (typedecls ";" typedecls) (id "=" type))
       (ids (ids "," ids))
       (vardecls (vardecls ";" vardecls) (ids ":" type))
       (constdecls (constdecls ";" constdecls) (id "=" exp))
       (exp (id "-anchor-" id) ("(" exp ")"))
       (caselabel (caselabel ".." caselabel) (caselabel "," caselabel))
       ;; : for types binds tighter than ;, but the : for case labels
       ;; (and, sharing the same token for simplicity, WITH's type
       ;; guards) binds less tight, so two distinct :'s are needed.
       (cases (cases "|" cases) (caselabel ":-case" insts))
       (guards (guards "|" guards) (id ":-case" id "DO-guard" insts))
       (forspec (id ":=" exp "TO" exp))
       (insts (insts ";" insts)
              (id ":=" exp)
              ("CASE" exp "OF" cases "END")
              ("CASE" exp "OF" cases "ELSE" insts "END")
              ("LOOP" insts "END")
              ("WITH" guards "END")
              ("WITH" guards "ELSE" insts "END")
              ("REPEAT" insts "UNTIL" exp)
              ("WHILE" exp "DO" insts "END")
              ("FOR" forspec "DO" insts "END")
              ("IF" exp "THEN" insts "END")
              ("IF" exp "THEN" insts "ELSE" insts "END")
              ("IF" exp "THEN" insts
               "ELSIF" exp "THEN" insts "ELSE" insts "END")
              ("IF" exp "THEN" insts
               "ELSIF" exp "THEN" insts
               "ELSIF" exp "THEN" insts "ELSE" insts "END"))
       ;; EXIT and RETURN [exp] are deliberately left unmodeled, same
       ;; as the original Modula-2 grammar this is based on left them
       ;; -- RETURN's operand is optional, and giving it two
       ;; alternative productions (with and without exp) makes SMIE
       ;; unable to decide whether RETURN is a leaf or an opener.
       ;; Leaving both as plain, un-recognized tokens is harmless:
       ;; they end up as inert filler within a statement sequence,
       ;; the same way an unmodeled procedure-call statement already
       ;; is.
       ;; The outermost 'MODULE ident ";" [ImportList] DeclSeq [BEGIN
       ;; StatementSeq] END ident "."'.  Like a PROCEDURE's formal
       ;; parameters, the ident and the optional ImportList in between
       ;; "MODULE" and decls need no rule of their own -- neither
       ;; introduces anything the indentation engine must track.
       ;;
       ;; FIXME: a module with no executable body at all (the
       ;; bracketed "BEGIN StatementSeq" is entirely absent, not just
       ;; empty) is not recognized -- only one shape is offered here,
       ;; same as PROCEDURE's.  Offering a second, bodyless
       ;; alternative made SMIE unable to tell, upon seeing "BEGIN",
       ;; whether it continues the current MODULE or starts something
       ;; new, and it silently resolved that by *not* indenting the
       ;; module's statement sequence at all.
       (module ("MODULE" decls "BEGIN" insts "END"))
       ;; This category is not used anywhere, but it adds some constraints that
       ;; try to reduce the harm when an OF-type is not properly recognized.
       (error-OF ("ARRAY" range "OF" type) ("SET" "OF" id)))
     '((assoc ";")) '((assoc ";-block")) '((assoc "|"))
     ;; For case labels.
     '((assoc ",") (assoc ".."))
     )
    (smie-precs->prec2
     '((nonassoc "-anchor-" "=")
       (nonassoc "<" "<=" ">=" ">" "#" "IN" "IS")
       (assoc "OR" "+" "-")
       (assoc "MOD" "DIV" "*" "/" "&")
       (nonassoc "~")
       (left "." "^")
       ))
    )))

(defun o2-smie-refine-colon ()
  (let ((res nil))
    (while (not res)
      (let ((tok (smie-default-backward-token)))
        (cond
         ((zerop (length tok))
          (let ((forward-sexp-function nil))
            (condition-case nil
                (let ((p (point)))
                  (forward-sexp -1)
                  (when (= p (point))
                    (setq res ":")))
              (scan-error (setq res ":")))))
         ;; "WITH" anchors a type guard's colon (Guard = Qualident ":"
         ;; Qualident); reusing ":-case" for it, same as a CASE label,
         ;; is a deliberate simplification -- see the "guards" comment
         ;; in o2-smie-grammar.
         ((member tok '("|" "OF" ".." "WITH")) (setq res ":-case"))
         ((member tok '(":" "END" ";" "BEGIN" "VAR" "RECORD" "PROCEDURE"))
          (setq res ":")))))
    res))

(defun o2-smie-refine-of ()
  (let ((tok (smie-default-backward-token)))
    (when (zerop (length tok))
      (let ((forward-sexp-function nil))
        (condition-case nil
            (backward-sexp 1)
          (scan-error nil))
        (setq tok (smie-default-backward-token))))
    (if (member tok '("ARRAY" "SET"))
        "OF-type" "OF")))

(defun o2-smie-refine-semi ()
  (forward-comment (point-max))
  (if (looking-at (regexp-opt '("PROCEDURE" "TYPE" "VAR" "CONST" "BEGIN")))
      ";-block" ";"))

;; A WITH guard's "DO" (Statement = ... | WITH Guard DO StatementSeq
;; {"|" Guard DO StatementSeq} [ELSE StatementSeq] END | ...) opens a
;; block closed by the *outer* END, past any number of "|"-separated
;; guards -- unlike WHILE/FOR's "DO", which is always closed by the
;; very next END.  Conflating the two gives SMIE an unresolvable
;; conflict (reported at grammar-definition time), so guard-DOs are
;; refined to a distinct "DO-guard" token, the same way ":-case" is
;; split out from a plain declaration ":".
(defun o2-smie-refine-do ()
  (let ((res nil))
    (while (not res)
      (let ((tok (smie-default-backward-token)))
        (cond
         ((zerop (length tok))
          (let ((forward-sexp-function nil))
            (condition-case nil
                (let ((p (point)))
                  (forward-sexp -1)
                  (when (= p (point))
                    (setq res "DO")))
              (scan-error (setq res "DO")))))
         ((member tok '("WITH" "|")) (setq res "DO-guard"))
         ((member tok '("WHILE" "FOR" "END" ";" "BEGIN" "THEN"
                        "LOOP" "REPEAT" "DO" "DO-guard"))
          (setq res "DO")))))
    res))

;; The "|" separating CASE labels or WITH guards is aligned with the
;; column of the enclosing CASE/WITH itself, by walking backward past
;; whatever it precedes (tracking nesting via END, so a WITH or CASE
;; nested *inside* a case label's or guard's own statement sequence
;; doesn't get mistaken for the enclosing one).  A bounded, defensive
;; fallback to column 0 covers an unmatched/in-progress buffer (e.g.
;; the user is still typing) rather than erroring or looping.
(defun o2-smie-with-or-case-column ()
  (save-excursion
    (let ((depth 0) (col nil) (n 0))
      (while (and (not col) (< n 500) (not (bobp)))
        (setq n (1+ n))
        (let ((tok (smie-default-backward-token)))
          (cond
           ((zerop (length tok))
            (condition-case nil (backward-char 1) (error (setq col 0))))
           ((equal tok "END") (setq depth (1+ depth)))
           ((member tok '("WITH" "CASE" "IF" "WHILE" "LOOP"))
            (if (zerop depth)
                (setq col (current-column))
              (setq depth (1- depth)))))))
      (or col 0))))

;; A forward declaration's "^" ('PROCEDURE "^" [Receiver] IdentDef
;; [FormalPars].') is refined to "^-fwd", distinct from the ordinary
;; postfix "^" of a designator (e.g. 'p.name^'), so a forward
;; declaration can be recognized as the bodyless form it is -- see
;; the "decls" comment in o2-smie-grammar.
(defun o2-smie-refine-caret ()
  (if (equal (smie-default-backward-token) "PROCEDURE") "^-fwd" "^"))

;; FIXME: "^." are two tokens, not one -- smie-default-forward-token
;; merges adjacent punctuation-syntax characters, so e.g. 'p^.field'
;; tokenizes as "p" "^." "field" rather than "p" "^" "." "field",
;; which the precedence table (declaring "^" and "." separately)
;; doesn't recognize.  Confirmed real and still present (not just
;; inherited from Modula-2/3), but low priority: tested harmless for
;; realistic code, since block-level indentation doesn't depend on
;; "^"/"."'s individual precedence, and idiomatic Oberon-2 puts "^"
;; as the final, often-implicit element of a designator chain (e.g.
;; 'p.name^'), so the "^" immediately-followed-by-"." shape this
;; would actually affect is uncommon in practice.
(defun o2-smie-forward-token ()
  (pcase (smie-default-forward-token)
    ("VAR" (if (zerop (car (syntax-ppss))) "VAR" "VAR-arg"))
    (";" (save-excursion (o2-smie-refine-semi)))
    ("OF" (save-excursion (forward-char -2) (o2-smie-refine-of)))
    (":" (save-excursion (forward-char -1) (o2-smie-refine-colon)))
    ("DO" (save-excursion (forward-char -2) (o2-smie-refine-do)))
    ("^" (save-excursion (forward-char -1) (o2-smie-refine-caret)))
    ;; (`"END" (if (and (looking-at "[ \t\n]*\\(\\(?:\\sw\\|\\s_\\)+\\)")
    ;;                  (not (assoc (match-string 1) o2-smie-grammar)))
    ;;             "END-proc" "END"))
    (token token)))

(defun o2-smie-backward-token ()
  (pcase (smie-default-backward-token)
    ("VAR" (if (zerop (car (syntax-ppss))) "VAR" "VAR-arg"))
    (";" (save-excursion (forward-char 1) (o2-smie-refine-semi)))
    ("OF" (save-excursion (o2-smie-refine-of)))
    (":" (save-excursion (o2-smie-refine-colon)))
    ("DO" (save-excursion (o2-smie-refine-do)))
    ("^" (save-excursion (o2-smie-refine-caret)))
    ;; (`"END" (if (and (looking-at "\\sw+[ \t\n]+\\(\\(?:\\sw\\|\\s_\\)+\\)")
    ;;                  (not (assoc (match-string 1) o2-smie-grammar)))
    ;;             "END-proc" "END"))
    (token token)))

(defun o2-smie-rules (kind token)
  ;; FIXME: Apparently, the usual indentation convention is something like:
  ;;
  ;;    TYPE t1 = bar;
  ;;    VAR x : INTEGER;
  ;;    PROCEDURE f ();
  ;;    TYPE t2 = foo;
  ;;      PROCEDURE g ();
  ;;      BEGIN blabla END;
  ;;    VAR y : type;
  ;;    BEGIN blibli END
  ;;
  ;; This is inconsistent with the actual structure of the code in 2 ways:
  ;; - The inner VAR/TYPE are indented just like the outer VAR/TYPE.
  ;; - The inner PROCEDURE is not aligned with its VAR/TYPE siblings.
  (pcase (cons kind token)
    ('(:elem . basic) o2-indent)
    ('(:after . ":=") (or o2-indent smie-indent-basic))
    (`(:after . ,(or "CONST" "VAR" "TYPE"))
     (or o2-indent smie-indent-basic))
    ;; Without this, only the *first* WITH guard's body gets
    ;; 'o2-indent' columns of indentation; every later ("|"-preceded)
    ;; guard's body falls through to SMIE's generic default offset
    ;; instead, two columns rather than 'o2-indent'.  A bare number
    ;; here is an *offset* added on top of whatever default already
    ;; applies (not a replacement for it; same lesson as the "|" rule
    ;; above needing '(column . N)' for an absolute result), so this
    ;; computes the absolute column directly: the enclosing WITH's or
    ;; CASE's own column (every guard line is now aligned to it, first
    ;; or "|"-prefixed) plus one indent step.
    ('(:after . "DO-guard")
     (cons 'column (+ (o2-smie-with-or-case-column)
                      (or o2-indent smie-indent-basic))))
    ;; (`(:before . ,(or `"VAR" `"TYPE" `"CONST"))
    ;;  (if (smie-rule-parent-p "PROCEDURE") 0))
    ('(:after . ";-block")
     (if (smie-rule-parent-p "PROCEDURE")
         (smie-rule-parent (or o2-indent smie-indent-basic))))
    ('(:before . "|") (cons 'column (o2-smie-with-or-case-column)))
    ))

;;;###autoload
(defalias 'oberon-2-mode 'o2-mode)
;;;###autoload
(define-derived-mode o2-mode prog-mode "Oberon-2"
  "This is a mode intended to support program development in Oberon-2.
All control constructs of Oberon-2 can be reached by typing C-c
followed by the first character of the construct.
\\<o2-mode-map>
  \\[o2-begin] begin         \\[o2-case] case
  \\[o2-else] else          \\[o2-for] for
  \\[o2-header] header        \\[o2-if] if
  \\[o2-loop] loop          \\[o2-or] or
  \\[o2-procedure] procedure     Control-c Control-w with
  \\[o2-record] record        \\[o2-type] type
  \\[o2-until] until
  \\[o2-var] var           \\[o2-while] while
  \\[o2-import] import
  \\[o2-begin-comment] begin-comment \\[o2-end-comment] end-comment
  \\[suspend-emacs] suspend Emacs

   `o2-indent' controls the number of spaces for each indentation."
  (setq-local paragraph-start (concat "$\\|" page-delimiter))
  (setq-local paragraph-separate paragraph-start)
  (setq-local paragraph-ignore-fill-prefix t)
  (setq-local comment-start "(* ")
  (setq-local comment-end " *)")
  (setq-local comment-start-skip "\\(?:(\\*+\\|//+\\) *")
  (setq-local parse-sexp-ignore-comments t)
  (setq-local fill-paragraph-function #'o2-fill-paragraph)
  (setq-local font-lock-defaults
	'((o2-font-lock-keywords
	   o2-font-lock-keywords-1 o2-font-lock-keywords-2)
	  nil nil ((?_ . "w") (?. . "w") (?< . ". 1") (?> . ". 4")) nil
	  ))
  (smie-setup o2-smie-grammar #'o2-smie-rules
              :forward-token #'o2-smie-forward-token
              :backward-token #'o2-smie-backward-token))

;; Keyword/type/builtin lists below are taken directly from the
;; Oberon-2 language report (language-report/oberon2.htm):
;;   reserved words  -- Appendix B (syntax) and Section 3 (vocabulary)
;;   basic types     -- Section 6.1
;;   predeclared procedures and constants -- Section 10.3
(defconst o2-font-lock-keywords-1
  '(
    ;;
    ;; Module and procedure definitions, including a type-bound
    ;; procedure's optional receiver clause, e.g. 'PROCEDURE (t: Tree)
    ;; Insert*' -- Receiver = "(" [VAR] ident ":" ident ")".
    ("\\<\\(MODULE\\|PROCEDURE\\)\\>[ \t]*\
\\(?:([ \t]*\\(?:VAR[ \t]+\\)?\\sw+[ \t]*:[ \t]*\\sw+[ \t]*)[ \t]*\\)?\
\\(\\sw+\\)?"
     (1 'font-lock-keyword-face) (2 'font-lock-function-name-face nil t))
    ;;
    ;; Import directives.  'IMPORT a, b := c;' -- each imported name
    ;; (and its optional local alias) is fontified as a reference.
    ("\\<\\(IMPORT\\)\\>"
     (1 'font-lock-keyword-face)
     (font-lock-match-c-style-declaration-item-and-skip-to-next
      nil (goto-char (match-end 0))
      (1 'font-lock-constant-face)))
    )
  "Subdued level highlighting for Oberon-2 modes.")

(defconst o2-font-lock-keywords-2
  (append o2-font-lock-keywords-1
   (eval-when-compile
     (let ((o2-types
	    (regexp-opt
	     '("BOOLEAN" "CHAR" "SHORTINT" "INTEGER" "LONGINT" "REAL"
	       "LONGREAL" "SET")))
	   (o2-keywords
	    (regexp-opt
	     '("ARRAY" "BEGIN" "BY" "CASE" "CONST" "DIV" "DO" "ELSE"
	       "ELSIF" "EXIT" "FOR" "IF" "IN" "IS" "LOOP" "MOD" "OF"
	       "OR" "POINTER" "RECORD" "REPEAT" "RETURN" "THEN" "TO"
	       "TYPE" "UNTIL" "VAR" "WHILE" "WITH")))
	   (o2-builtins
	    (regexp-opt
	     '("ABS" "ASH" "CAP" "CHR" "ENTIER" "LEN" "LONG" "MAX" "MIN"
	       "ODD" "ORD" "SHORT" "SIZE" "ASSERT" "COPY" "DEC" "EXCL"
	       "HALT" "INC" "INCL" "NEW")))
	   )
       `(
	 ;;
	 ;; Keywords except those fontified elsewhere (MODULE,
	 ;; PROCEDURE and IMPORT above; END, NIL below).
	 ,(concat "\\<\\(" o2-keywords "\\)\\>")
	 ;;
	 ;; Builtins (predeclared procedures).
	 (,(concat "\\<\\(" o2-builtins "\\)\\>")
	  (0 'font-lock-builtin-face))
	 ;;
	 ;; Type names (predeclared basic types).
	 (,(concat "\\<\\(" o2-types "\\)\\>")
	  (0 'font-lock-type-face))
	 ;;
	 ;; END closes MODULE, PROCEDURE, and every structured
	 ;; statement/type; it is always a plain keyword in Oberon-2
	 ;; (there is no exception-handling construct that follows it
	 ;; with a name, unlike Modula-3's END/EXCEPTION/RAISES).
	 ("\\<END\\>" (0 'font-lock-keyword-face))
	 ;;
	 ;; Fontify constants as references.
	 ("\\<\\(FALSE\\|NIL\\|TRUE\\)\\>"
	  (0 'font-lock-constant-face))
	))))
  "Gaudy level highlighting for Oberon-2 modes.")

(defvar o2-font-lock-keywords o2-font-lock-keywords-1
  "Default expressions to highlight in Oberon-2 modes.")

(define-skeleton o2-begin
  "Insert a BEGIN keyword and indent for the next line."
  nil
  \n "BEGIN" > \n)

(define-skeleton o2-case
  "Build skeleton CASE statement, prompting for the <expression>."
  "Case-Expression: "
  \n "CASE " str " OF" > \n _ \n "END (* " str " *);" > \n)

(define-skeleton o2-else
  "Insert ELSE keyword and indent for next line."
  nil
  \n "ELSE" > \n)

(define-skeleton o2-for
  "Build skeleton FOR loop statement, prompting for the loop parameters."
  "Loop Initializer: "
  ;; FIXME: this seems to be lacking a "<var> :=".
  \n "FOR " str " TO "
  (setq v1 (read-string "Limit: "))
  (let ((by (read-string "Step: ")))
    (if (not (string-equal by ""))
        (concat " BY " by)))
  " DO" > \n _ \n "END (* for " str " to " v1 " *);" > \n)

(define-skeleton o2-header
  "Insert a comment block containing the module title, author, etc."
  "Title: "
  "(*\n    Title: \t" str
  "\n    Created: \t" (current-time-string)
  "\n    Author: \t"  (user-full-name) " <" user-mail-address ">\n"
  "*)" > \n)

(define-skeleton o2-if
  "Insert skeleton IF statement, prompting for <boolean-expression>."
  "<boolean-expression>: "
  \n "IF " str " THEN" > \n _ \n "END (* if " str " *);" > \n)

(define-skeleton o2-loop
  "Build skeleton LOOP (with END)."
  nil
  \n "LOOP" > \n _ \n "END (* loop *);" > \n)

(define-skeleton o2-or
  "No doc."
  nil
  \n "|" > \n)

(define-skeleton o2-procedure
  "No doc."
  "Name: "
  \n "PROCEDURE " str " (" (read-string "Arguments: ") ")"
  (let ((args (read-string "Result Type: ")))
    (if (not (equal args "")) (concat " : " args)))
  ";" > \n "BEGIN" > \n _ \n "END " str ";" > \n)

(define-skeleton o2-with
  "Build skeleton WITH statement, prompting for the <variable> and its
guard <type> (Guard = Qualident \":\" Qualident)."
  "Variable: "
  \n "WITH " str ": "
  (setq v1 (read-string "Type: "))
  " DO" > \n _ \n "END (* with " str ": " v1 " *);" > \n)

(define-skeleton o2-record
  "No doc."
  nil
  \n "RECORD" > \n _ \n "END (* record *);" > \n)

(define-skeleton o2-type
  "No doc."
  nil
  \n "TYPE" > \n ";" > \n)

(define-skeleton o2-until
  "No doc."
  "<boolean-expression>: "
  \n "REPEAT" > \n _ \n "UNTIL " str ";" > \n)

(define-skeleton o2-var
  "No doc."
  nil
  \n "VAR" > \n ";" > \n)

(define-skeleton o2-while
  "No doc."
  "<boolean-expression>: "
  \n "WHILE " str " DO" > \n _ \n "END (* while " str " *);" > \n)

(define-skeleton o2-import
  "No doc."
  "Module: "
  \n "FROM " str " IMPORT " > _ \n)

(defun o2-begin-comment ()
  (interactive)
  (if (not (bolp))
      (indent-to comment-column 0))
  (insert "(*  "))

(defun o2-end-comment ()
  (interactive)
  (if (not (bolp))
      (indent-to o2-end-comment-column))
  (insert "*)"))

(defun o2-comment-newline ()
  "Insert a newline.  If point is in -- or, per the same rule
`o2-fill-paragraph' uses, at the start of -- an Oberon-2 comment,
continue it on the new line: insert \"*\" aligned under the column of
the comment's own opening \"*\", followed by a space, leaving point
just after that space.  Otherwise this is a plain `newline'."
  (interactive "*")
  (let* ((state (syntax-ppss))
         (beg (or (nth 8 state)      ; non-nil => already past '(*'.
                  (save-excursion
                    (beginning-of-line)
                    (skip-chars-forward " \t")
                    (and (looking-at comment-start-skip) (point)))))
         (lead (and beg
                   (let ((col (save-excursion (goto-char beg)
                                              (1+ (current-column)))))
                     (if indent-tabs-mode
                         (concat (make-string (/ col tab-width) ?\t)
                                (make-string (% col tab-width) ?\s))
                       (make-string col ?\s))))))
    (newline)
    (when lead
      (insert lead "* "))))

(defun o2-fill-paragraph (&optional justify)
  "Fill just the Oberon-2 comment paragraph at point, inserting/
maintaining a \"*\" at the start of each continuation line, aligned
under the opening \"*\" of the comment's \"(*\".  A blank -- or
\"*\"-only -- line always separates and stops the refill at a
paragraph boundary: a comment with several such paragraphs (e.g. a
hand-formatted block of example code set off by blank lines from the
surrounding prose) refills only the one paragraph at point, leaving
every other paragraph in the comment untouched.  A paragraph indented
past the normal \"* \" alignment keeps that extra indentation on every
line of its own refill -- narrower by exactly that much, but never
past the limits below -- so that hand-formatted block keeps its shape
instead of being reflowed like surrounding prose.

Wraps at `o2-end-comment-column' (the same column
`\\[o2-end-comment]' aligns a closing \"*)\" to), not the buffer's
generic `fill-column' -- but never past `o2-comment-text-column-limit',
regardless of how `o2-end-comment-column' is customized.

Always returns non-nil (claiming to have \"handled\" the fill, doing
nothing) when point is not in or at the start of a comment:
Oberon-2 code is not prose, there is no sensible notion of \"fill\"
for a declaration or statement, and letting the generic,
comment-unaware fallback filler run instead is actively dangerous
here -- with no blank line separating a comment from adjacent code (a
common style), it merges them into one \"paragraph\" and reformats
both together."
  (interactive "P")
  (let* ((state (syntax-ppss))
         (beg (or (nth 8 state)      ; non-nil => already past '(*'.
                  ;; Point may instead be *before* the comment it's
                  ;; logically \"on\" -- e.g. at beginning-of-line,
                  ;; before '(*', which 'syntax-ppss' at point alone
                  ;; does not count as \"inside\" the comment.  Check
                  ;; whether the first non-blank text on this line
                  ;; starts one.
                  (save-excursion
                    (beginning-of-line)
                    (skip-chars-forward " \t")
                    (and (looking-at comment-start-skip) (point))))))
    (if (not beg)
        t                             ; outside a comment: no-op.
      (let* ((end (save-excursion
                    (goto-char beg)
                    (forward-comment 1)  ; past its matching close, nesting-aware.
                    (point)))
             ;; Where to look for the paragraph at point: 'point'
             ;; itself unless that is actually before 'beg' (e.g. at
             ;; beginning-of-line, before a trailing comment's '(*'),
             ;; in which case it is still logically on the comment's
             ;; own first paragraph -- or sitting on a blank/"*"-only
             ;; separator line itself, in which case it is snapped
             ;; forward to the paragraph following it (a backward or
             ;; forward search for that same separator, from a point
             ;; inside its own match, finds nothing, since neither
             ;; search's match can end/start AT point -- and with
             ;; neither boundary found, the whole comment would
             ;; otherwise be mistaken for one single paragraph).  A
             ;; marker, since the separator normalization just below
             ;; can shift text before it.
             (here (copy-marker
                    (let ((h (max beg (min (point) (1- end)))))
                      (save-excursion
                        (goto-char h)
                        (while (and (< (point) end)
                                   (save-excursion
                                     (beginning-of-line)
                                     (looking-at "[ \t]*\\(?:\\*[ \t]*\\)?$")))
                          (forward-line 1))
                        (min (point) (1- end))))))
             ;; Column of the comment's own '*' -- computed here, on
             ;; the unnarrowed buffer: narrowing to the comment below
             ;; clips away any indentation before 'beg', which would
             ;; make 'current-column' there undercount it.
             (col (save-excursion (goto-char beg) (1+ (current-column))))
             (lead (if indent-tabs-mode
                       (concat (make-string (/ col tab-width) ?\t)
                              (make-string (% col tab-width) ?\s))
                     (make-string col ?\s)))
             ;; The column a paragraph's text normally starts at,
             ;; right after its aligned "* " -- whether that "*" is
             ;; the comment's own opening one (first paragraph) or a
             ;; continuation one (any later paragraph): both land in
             ;; the same column by construction of 'lead'/'col' above.
             ;; Whatever this paragraph's own first line starts past
             ;; this column, on its own, is its deliberate extra
             ;; indent, kept for every line of its own refill.
             (base-text-col (+ col 2))
             ;; Comments wrap at 'o2-end-comment-column', not the
             ;; buffer's generic 'fill-column' -- but never past
             ;; 'o2-comment-text-column-limit', regardless of how
             ;; 'o2-end-comment-column' is customized.  This is the
             ;; target width before this paragraph's own extra indent
             ;; (above) narrows it further.
             (target (min (or o2-end-comment-column fill-column)
                          o2-comment-text-column-limit))
             ;; A blank line, or one containing only "*" (a common way
             ;; to write a blank separator line inside a comment where
             ;; every line otherwise starts with "*"), separates two
             ;; paragraphs.
             (sep-re "\n[ \t]*\\(?:\\*[ \t]*\\)?\n"))
        (save-excursion
          (save-restriction
            ;; Narrow to just this comment first, so the paragraph
            ;; search just below can never wander into surrounding
            ;; code looking for a separator that isn't there.
            (narrow-to-region beg end)
            ;; Normalize the (at most two) separators immediately
            ;; bounding this paragraph to "*"-only -- even though only
            ;; this one paragraph's own text is refilled below, a
            ;; blank separator line is never left without a "*" once
            ;; a comment it is part of has been touched at all.  Only
            ;; these two, found relative to 'here': any other
            ;; separator elsewhere in the comment is untouched, same
            ;; as every other paragraph.
            (save-excursion
              (goto-char here)
              (when (re-search-backward sep-re nil t)
                (replace-match (concat "\n" lead "*" "\n"))))
            (save-excursion
              (goto-char here)
              (when (re-search-forward sep-re nil t)
                (replace-match (concat "\n" lead "*" "\n"))))
            (let* ((pstart (save-excursion
                             (goto-char here)
                             (if (re-search-backward sep-re nil t)
                                 (match-end 0)
                               (point-min))))
                   (pend (save-excursion
                           (goto-char here)
                           (if (re-search-forward sep-re nil t)
                               (match-beginning 0)
                             (point-max))))
                   (first (= pstart (point-min)))
                   (last (= pend (point-max))))
              ;; Narrow again, down to just this one paragraph (the
              ;; blank/"*"-only lines bounding it on either side, if
              ;; any, are deliberately left outside this and so are
              ;; never touched below): this is the only part of the
              ;; whole comment this call ever modifies.
              (save-restriction
                (narrow-to-region pstart pend)
                ;; Temporarily remove the closing "*)" (and any blank
                ;; line/space it sat alone on) before touching
                ;; anything else -- but only when this paragraph is
                ;; the comment's last, i.e. actually abuts it -- so it
                ;; is never mistaken for a fill prefix by the filling
                ;; below; re-appended fresh afterward, directly after
                ;; the last word.  A non-plain closer (e.g. \"**)\")
                ;; is left alone entirely -- rather than risk
                ;; mishandling it, the filling below just runs across
                ;; it as ordinary trailing text.
                (let (plain-closer close-at-bol)
                  (when last
                    (goto-char (point-max))
                    (backward-char 2)
                    (setq plain-closer (looking-at "\\*)"))
                    (when plain-closer
                      (setq close-at-bol
                           (save-excursion (skip-chars-backward " \t") (bolp)))
                      (skip-chars-backward " \t\n")
                      (delete-region (point) (point-max))))
                  ;; The real text preceding 'beg' on its own line
                  ;; (plain indentation, or code before a trailing
                  ;; comment) is outside this narrowing, so it is
                  ;; invisible to the filling below, which only
                  ;; measures from this accessible point-min -- but
                  ;; only the comment's first paragraph is adjacent to
                  ;; it.  Stand-in padding of the same width takes its
                  ;; place here so that paragraph's first line's true
                  ;; column is still accounted for, without ever
                  ;; letting fill touch the real text.  Fill
                  ;; algorithms leave a paragraph's own first line's
                  ;; existing leading whitespace untouched (the same
                  ;; guarantee relied on below to keep the \"(* \"
                  ;; opener, and any hand-indentation after it,
                  ;; intact), so this padding survives filling
                  ;; unchanged and is stripped back out once done.
                  (when first
                    (goto-char (point-min))
                    (insert (make-string (1- col) ?\s)))
                  ;; This paragraph's own first line's existing
                  ;; indentation, if deeper than 'base-text-col', is
                  ;; its deliberate extra indent, kept for every line
                  ;; of its refill by narrowing the target width by
                  ;; exactly that much.  When this is the comment's
                  ;; own first paragraph, its first line's \"(* \" (and
                  ;; any hand-indentation after it) is left as-is --
                  ;; 'fill-region' leaves a paragraph's own first
                  ;; line's indentation untouched -- otherwise it is
                  ;; rewritten to our own aligned, \"*\"-prefixed form
                  ;; first, since it may have no \"*\" at all yet.
                  ;;
                  ;; 'fill-region' is used, not 'fill-paragraph': the
                  ;; buffer is already narrowed to exactly the text to
                  ;; fill, so no paragraph-boundary-finding is needed
                  ;; -- and calling 'fill-paragraph' recursively from
                  ;; here runs into its own dispatch logic (reached
                  ;; with 'fill-paragraph-handle-comment' bound to nil
                  ;; to avoid infinite recursion), which does its own
                  ;; boundary search that, empirically, miscomputes
                  ;; the first line's budget against 'fill-column'
                  ;; when it has pre-existing indentation different
                  ;; from 'fill-prefix'.
                  (let (extra)
                    (goto-char (point-min))
                    (skip-chars-forward " \t")
                    (cond (first
                           (forward-char 2)        ; past "(*".
                           (skip-chars-forward " \t"))
                          ((looking-at "\\*")
                           (forward-char 1)
                           (skip-chars-forward " \t")))
                    (setq extra (max 0 (- (current-column) base-text-col)))
                    (unless first
                      (delete-region (point-min) (point))
                      (goto-char (point-min))
                      (insert lead "*" " " (make-string extra ?\s)))
                    (let ((fill-prefix (concat lead "*" " "
                                               (make-string extra ?\s)))
                          (fill-column (max 1 (- target extra))))
                      (goto-char (point-min))
                      (fill-region (point-min) (point-max) justify)))
                  ;; Remove the stand-in padding inserted above, now
                  ;; that filling is done with it.
                  (when first
                    (goto-char (point-min))
                    (delete-char (1- col)))
                  (goto-char (point-max))
                  (when plain-closer
                    (if close-at-bol
                        (insert "\n" lead "*)")
                      (insert " *)")))))))
        t)))))

(provide 'oberon2)

;;; oberon2.el ends here
