(* Copyright (c) 2022 Logic Magicians Software *)
MODULE Pathnames;
IMPORT
  Environment;

CONST
  Separator = '/';

CONST (* Fields for Recompose *)
  Directory = 0;
  Basename  = 1;
  Extension = 2;
  All       = { Directory, Basename, Extension };

TYPE
  Element*      = POINTER TO ARRAY OF CHAR;
  Elements      = POINTER TO ARRAY OF Element;
  Pathname*     = POINTER TO PathnameDesc;
  PathnameDesc* = RECORD
    compose    : Element;       (* Cached recomposition of pathname. *)
    fields     : SET;           (* Fields used on last Recompose(). *)

    elements-  : Elements;       (* NIL => no pathname. *)
    basename-  : Element;        (* NIL => no basename. *)
    extension- : Element;        (* NIL => no extension. *)
    absolute-  : BOOLEAN;        (* TRUE  -> first char = Separator.
                                  * FALSE -> first char # Separator. *)
  END;


VAR
  home : Environment.Text;      (* Home directory; for '~' expansion. *)


(* Invalidate:

    This private function invalidates any cached composition of the
    pathname.  It is invoked when the internal data structure is
    changed, rendering any cached value out-of-date.
 *)
PROCEDURE (self : Pathname) Invalidate;
BEGIN
  self.compose := NIL;
END Invalidate;


PROCEDURE (self : Pathname) Recompose(fields : SET) : Element;
  VAR
    l      : LONGINT;
    i      : LONGINT;

  PROCEDURE length(self : Pathname) : LONGINT;
    VAR
      len    : LONGINT;
  BEGIN
    len := 0;
    IF Directory IN self.fields THEN
      IF self.absolute THEN
        INC(len);                     (* Space for leading '/'. *)
      END;

      IF self.elements # NIL THEN
        i := 0;
        WHILE i < LEN(self.elements^) DO
          INC(len, LEN(self.elements[i]^)); (* LEN includes 0X. *)
          INC(i);
        END;
      END;
    END;


    IF (Basename IN self.fields) & (self.basename # NIL) THEN
      INC(len, LEN(self.basename^));
    END;

    IF (Extension IN self.fields) & (self.extension # NIL) THEN
      INC(len, LEN(self.extension^));
    END;

    (*
      The 'len' value now contains an extra byte for every 'element'
      as well as the basename and extension. This is useful because an
      extra byte is needed for the separator, and the final 0X
      terminator.

      If there is a basename and an extension, the number of elements
      will be one byte too many, because there is no separator between
      the basename and the extension.
     *)
    IF ((Basename IN self.fields) & (self.basename # NIL)) &
       ((Extension IN self.fields) & (self.extension # NIL)) THEN
      DEC(len, 1);
    END;
    RETURN len;
  END length;

  PROCEDURE append(separator : BOOLEAN;
                   res       : Element;
                   i         : LONGINT;
                   elem      : Element) : LONGINT;
    VAR
      j : LONGINT;
  BEGIN
    IF separator THEN
      res[i] := Separator;
      INC(i);
    END;
    j := 0;
    WHILE j < LEN(elem^) DO
      res[i] := elem[j];
      INC(i);
      INC(j);
    END;
    RETURN i - 1;
  END append;

  PROCEDURE copy(self : Pathname; res : Element);
    VAR
      i : LONGINT;
      j : LONGINT;
  BEGIN
    i := 0;
    IF Directory IN self.fields THEN
      IF self.absolute THEN
        res[i] := Separator;
        INC(i);
      END;

      IF self.elements # NIL THEN
        j := 0;
        WHILE j < LEN(self.elements^) DO
          i := append(j > 0, res, i, self.elements[j]);
          INC(j);
        END;
      END;
    END;

    IF (Basename IN self.fields) & (self.basename # NIL) THEN
      i := append((Directory IN self.fields) & (self.elements # NIL),
                  res, i, self.basename);
    END;

    IF (Extension IN self.fields) & (self.extension # NIL) THEN
      i := append(FALSE, res, i, self.extension);
    END;
  END copy;

BEGIN
  IF (fields # self.fields) OR (self.compose = NIL) THEN
    self.fields := fields * All;      (* Saved for auto-invalidate. *)
    l := length(self);
    self.compose := NIL;
    IF l > 0 THEN
      NEW(self.compose, l);
      copy(self, self.compose);
    END;
  END;
  RETURN self.compose;
END Recompose;

PROCEDURE (self : Pathname) Pathname*() : Element;
BEGIN
  RETURN self.Recompose(All);
END Pathname;


PROCEDURE (self : Pathname) Dirname*() : Element;
BEGIN
  RETURN self.Recompose({Directory});
END Dirname;


PROCEDURE (self : Pathname) Basename*() : Element;
BEGIN
  RETURN self.basename;
END Basename;


PROCEDURE (self : Pathname) Filename*() : Element;
BEGIN
  RETURN self.Recompose({Basename, Extension});
END Filename;


PROCEDURE (self : Pathname) Extension*() : Element;
BEGIN
  RETURN self.extension;
END Extension;


PROCEDURE (self : Pathname) SetAbsolute*(v : BOOLEAN);
BEGIN
  self.absolute := v;
  self.Invalidate;
END SetAbsolute;

(* SetField

   A private function facilitating replacement the basename or the
   extension of the pathname.
*)
PROCEDURE (self : Pathname) SetField(VAR (* R/O *) value : ARRAY OF CHAR;
                                     VAR field : Element);
  VAR
    l : LONGINT;
BEGIN
  self.Invalidate;
  l := LEN(value);                (* Includes 0X. *)
  IF l >= 2 THEN
    (* At least one non-0X character *)
    NEW(field, l); (* Includes 0X. *)
    COPY(value, field^);
  ELSE
    field := NIL;               (* Field has been removed. *)
  END;
END SetField;


PROCEDURE (self : Pathname) SetExtension*(ext         : ARRAY OF CHAR;
                                          VAR success : BOOLEAN);
BEGIN
  success := (ext[0] = '.') OR (ext[0] = 0X);
  IF success THEN
    self.SetField(ext, self.extension);
  END;
END SetExtension;


PROCEDURE (self : Pathname) SetBasename*(basename    : ARRAY OF CHAR;
                                         VAR success : BOOLEAN);
BEGIN
  success := basename[0] # 0X;
  IF success THEN
    self.SetField(basename, self.basename);
  END;
END SetBasename;


PROCEDURE (self : Pathname) Delete*(beg, end : INTEGER;
                                    VAR success : BOOLEAN);
  VAR
    n : INTEGER;
    i : INTEGER;
    j : INTEGER;
    l : LONGINT;
    p : Elements;

BEGIN
  l := LEN(self.elements^);
  success := (beg >= 0) & (beg < end) & (end <= l);
  IF success THEN
    n := end - beg;               (* Number of new elements. *)
    NEW(p, l - n);
    i := 0;
    WHILE i < beg DO
      p[i] := self.elements[i];
      INC(i);
    END;
    j := end;
    WHILE j < l DO
      p[i] := self.elements[j];
      INC(i);
      INC(j);
    END;
    self.elements := p;
    self.Invalidate;
  END;
END Delete;


PROCEDURE (self : Pathname) Insert*(beg         : INTEGER;
                                    path        : Pathname;
                                    VAR success : BOOLEAN);
  VAR
    ls       : LONGINT;
    lp       : LONGINT;
    i        : INTEGER;
    j        : INTEGER;
    p        : Elements;
    absolute : BOOLEAN;

  PROCEDURE length(s : Pathname; full : BOOLEAN) : LONGINT;
    VAR
      l : LONGINT;
  BEGIN
    l := 0;
    IF s.elements # NIL THEN
      l := LEN(s.elements^);
    END;
    IF full THEN
      IF s.basename # NIL THEN
        INC(l);
      END;
      IF s.extension # NIL THEN
        INC(l);
      END;
    END;
    RETURN l;
  END length;


BEGIN
  ls       := length(self, FALSE); (* self.{basename, extension} not changed. *)
  absolute := path.absolute;
  success  := ((beg = 0) OR (~absolute)) & (beg >= 0) & (beg <= ls);

  IF success THEN
    lp := length(path, TRUE);
    NEW(p, ls + lp);

    (* Copy self.elements, up to 'beg' *)
    i := 0;
    WHILE i < beg DO
      p[i] := self.elements[i];
      INC(i);
    END;

    (* Copy 'path' into 'self'. *)
    IF path.elements # NIL THEN
      j := 0;
      lp := LEN(path.elements^);
      WHILE j < lp DO
        p[i] := path.elements[j];
        INC(i);
        INC(j);
      END;
    END;

    IF path.basename # NIL THEN
      p[i] := path.basename;
      INC(i);
    END;

    IF path.extension # NIL THEN
      p[i] := path.extension;
      INC(i);
    END;


    IF self.elements # NIL THEN
      (* Copy the rest of self.elements *)
      j := beg;
      ls := LEN(self.elements^);
      WHILE j < ls DO
        p[i] := self.elements[j];
        INC(i);
        INC(j);
      END;
    END;

    self.SetAbsolute(absolute OR self.absolute);
    self.elements := p;
    self.Invalidate;
  END;
END Insert;


PROCEDURE (self : Pathname) Decompose(path : ARRAY OF CHAR);
  TYPE
    ElementInfo = POINTER TO ElementData;
    ElementData = RECORD
      beg, end : LONGINT;
      next : ElementInfo;
    END;

  VAR
    i    : LONGINT;
    n    : LONGINT;             (* Number of elements. *)
    cs   : LONGINT;             (* Copy index 'src'. *)
    cd   : LONGINT;             (* Copy index 'dst'. *)
    xbeg : LONGINT;             (* Index of '.' in last element. *)
    head : ElementInfo;
    elem : ElementInfo;
    ebeg, eend : LONGINT;       (* Element indices [ebeg, eend) *)
    len : LONGINT;
    found : BOOLEAN;

  PROCEDURE copy(VAR src : ARRAY OF CHAR;
                 beg     : LONGINT;
                 end     : LONGINT;
                 dst     : Element);
    VAR
      i : LONGINT;
      l : LONGINT;
  BEGIN
    i := 0;
    l := end - beg; (* [beg, end) *)
    WHILE i <= l DO
      dst[i] := src[beg];
      INC(i);
      INC(beg);
    END;
    dst[l] := 0X;
  END copy;


BEGIN
  (* The input path, src,  is processed from the end to the beginning
   * so that the elements can be allocated in order easily.
   *)
  IF LEN(path) > 1  THEN (* LEN includes 0X; empty string is length of 1. *)
    self.SetAbsolute(path[0] = Separator);

    len := 0;
    WHILE path[len] # 0X DO
      INC(len);
    END;
    i := len - 1; (* inv: path[len] = 0X & i >= 0 *)
    n := 0;

    
    (* Create list of records that describe [beg, end) of pathname elements. *)
    LOOP
      WHILE (i >= 0) & (path[i] = Separator) DO
        DEC(i);                 (* Skip 1 or more separators. *)
      END;

      (* Gather an element *)
      eend := i + 1;
      REPEAT
        DEC(i);
      UNTIL (i < 0) OR (path[i] = Separator);

      IF i < 0 THEN
        ebeg := 0;              (* At beginning of pathname *)
      ELSE
        ebeg := i + 1;
      END;
      IF ebeg < eend THEN
        NEW(elem);
        INC(n);
        elem.beg  := ebeg;
        elem.end  := eend;
        elem.next := head;
        head      := elem;
      END;
      IF i <= 0 THEN
        EXIT;
      END;
    END;

    IF n > 0 THEN (* Note: A pathname of just '/' has 0 elements. *)
      NEW(self.elements, n - 1);

      (* Store pathname portion. *)
      i := 0;
      elem := head;
      WHILE i < n - 1 DO
        NEW(self.elements[i], elem.end - elem.beg + 1);
        copy(path, elem.beg, elem.end, self.elements[i]);
        elem := elem.next;
        INC(i);
      END;

      (* Store basename & extension. *)
      ASSERT(elem.next = NIL);

      (* The extension is from the last '.' to the end of element.
       * The basename is from the beginning of the element to
       * before the last '.'.  If no '.' is present, the baseename is the
       * whole element
       *)
      i := elem.end;
      LOOP
        IF i < elem.beg THEN
          (* No '.' found
           * basename  := [elem.beg, elem.end)
           * extension := NIL
           *)
          NEW(self.basename, elem.end - elem.beg + 1);
          copy(path, elem.beg, elem.end, self.basename);
          EXIT;
        ELSIF path[i] = '.' THEN
          (* basename  := [elem.beg..i)
           * extension := [elem.beg + i, elem.end)
           *)
          IF i = elem.beg THEN (* dotfile with no extension? *)
            NEW(self.basename, elem.end - elem.beg + 1);
            copy(path, elem.beg, elem.end, self.basename);
          ELSE
            ASSERT(i > elem.beg);
            NEW(self.basename, i - elem.beg + 1);
            copy(path, elem.beg, i, self.basename);
            NEW(self.extension, elem.end - i + 1);
            copy(path, i, elem.end, self.extension);
          END;
          EXIT;
        END;
        DEC(i);
      END;
    END;
  ELSE
    self.elements  := NIL;
    self.basename  := NIL;
    self.extension := NIL;
    self.compose   := NIL;
    self.SetAbsolute(FALSE);
  END;
END Decompose;

PROCEDURE Create*(path : ARRAY OF CHAR) : Pathname;
  VAR
    pathname : Pathname;
    p : POINTER TO ARRAY OF CHAR;
    i, j : LONGINT;
    expandHome : BOOLEAN;
BEGIN
  pathname := NIL;
  IF path[0] # 0X THEN
    NEW(pathname);
    
    expandHome := (home # NIL) & (LEN(path) >= 1) & (path[0] = '~');
    IF expandHome THEN
      (* Tilde expansion. *)
      NEW(p, (LEN(path) - 1 (* Remove ~ *)) + LEN(home^));
      i := 0;
      WHILE i < LEN(home^) - 1 DO (* Do not copy 0X. *)
        p[i] := home[i];
        INC(i);
      END;
      j := 1;                     (* Remove '~' *)
      WHILE j < LEN(path) DO
        p[i] := path[j];
        INC(i);
        INC(j);
      END;
      pathname.Decompose(p^);
    ELSE
      pathname.Decompose(path);
    END;
  END;
  RETURN pathname;
END Create;

BEGIN
  home := Environment.Lookup("HOME");
END Pathnames.
