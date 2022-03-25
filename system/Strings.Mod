MODULE Strings;


IMPORT SYSTEM;


TYPE
  String* = POINTER TO ARRAY OF CHAR;
  (** In the following, some procedures return a string.
    * This string is allways a newly allocated one.
    * NIL is returned in case of invalid parameters.
    *
    * Other procedurese accept VAR str:String and VAR pos:INTEGER as parameter.
    * This VARs may be changed.
    * (pos := -1) is set in case of invalid parameters.
    *)


(*---------------------------------------------------------------------------*)
PROCEDURE AOCLength*(s: ARRAY OF CHAR): LONGINT;
(** Return length of ARRAY OF CHAR. *)
VAR
  i, max: LONGINT;
BEGIN
  max := LEN(s);
  i := 0;
  WHILE (i < max) & (s[i] # 0X) DO
    INC(i)
  END;
  RETURN i
END AOCLength;

PROCEDURE Max(i,j :LONGINT): LONGINT;
BEGIN
  IF j > i THEN
    i := j
  END;
  RETURN i
END Max;

PROCEDURE Min(i,j :LONGINT): LONGINT;
BEGIN
  IF j < i THEN
    i := j
  END;
  RETURN i
END Min;

PROCEDURE KeepWithin(min, n, max: LONGINT): LONGINT;
(** Return min if max < min. *)
BEGIN
  RETURN Max(min, Min(n, max))
END KeepWithin;


(*---------------------------------------------------------------------------*)
PROCEDURE New*(n: LONGINT;   c: CHAR): String;
(** Return new string of length n, LEN n+1.
  * Filled with char c,
  * Terminated with 0X.
  *)
VAR
  i: LONGINT;
  str: String;
BEGIN
  IF n < 0 THEN
    RETURN NIL
  ELSE
    NEW(str, n + 1);
    i := 0;
    WHILE i < n DO
      str[i] := c;
      INC(i)
    END;
    str[i] := 0X;
    RETURN str
  END
END New;

PROCEDURE Empty*(): String;
(** Return an empty string str: "".
  * Length(str) is 0.
  * LEN(str) is 1.
  *)
BEGIN
  RETURN New(0, 0X);
END Empty;

PROCEDURE Create*(s: ARRAY OF CHAR): String;
(** Create a new String from ARRAY OF CHAR. *)
VAR
  i, len: LONGINT;
  str: String;
BEGIN
  len := AOCLength(s);
  NEW(str, len + 1);
  COPY(s, str^);
  str[len] := 0X;
  RETURN str
END Create;

PROCEDURE Length*(str: String): LONGINT;
(** Return length of str, exclusive terminating 0X. *)
VAR
  i, max: LONGINT;
BEGIN
  max := LEN(str^);
  i := 0;
  WHILE (i < max) & (str[i] # 0X) DO
    INC(i)
  END;
  RETURN i
END Length;


(*---------------------------------------------------------------------------*)
PROCEDURE Sub*(str: String;   pos, len: LONGINT): String;
(** Return substring of str, starting from pos with length len.
  * Return tail of str or empty string, if pos or len are thusly large.
  * Return NIL if str is NIL or pos < 0.
  *)
VAR
  i, start, last, max: LONGINT;
  nstr: String;
BEGIN
  IF  (str = NIL) OR (pos < 0) THEN
    RETURN NIL
  END;
  max := LEN(str^);
  pos := Min(max, pos);
  len := Max(0, len);
  i := 0;
  WHILE (i < pos) & (str[i] # 0X) DO
    INC(i)
  END;
  start := i;
  last := Min(max, start + len);
  WHILE (i < last) & (str[i] # 0X) DO
    INC(i);
  END;
  len := i - start;

  NEW(nstr, len + 1);
  SYSTEM.MOVE(SYSTEM.ADR(str^) + start , SYSTEM.ADR(nstr^), len);
  nstr[len] := 0X;
  RETURN nstr
END Sub;

PROCEDURE Head*(str: String;   len: LONGINT): String;
(** Return head of str with length len.
  * Return the entire str, if len is thusly large.
  * Return NIL if str is NIL.
  *)
VAR
  i: LONGINT;
  nstr: String;
BEGIN
  IF  str = NIL THEN
    RETURN NIL
  END;
  len := KeepWithin(0, len, LEN(str^));
  i := 0;
  WHILE (i < len) & (str^[i] # 0X) DO
    INC(i)
  END;

  NEW(nstr, i + 1);
  COPY(str^, nstr^);
  nstr[i] := 0X;
  RETURN nstr
END Head;

PROCEDURE Tail*(str: String;   len: LONGINT): String;
(** Return last len characters of str.
  * Return the entire str, if len is thusly large.
  * Return NIL if str is NIL.
  *)
VAR
  slen, start: LONGINT;
  nstr: String;
BEGIN
  IF  str = NIL THEN
    RETURN NIL
  END;
  len := KeepWithin(0, len, LEN(str^));
  slen := Length(str);
  IF slen >= len THEN
    start := slen - len
  ELSE
    start := 0;
    len   := slen
  END;

  NEW(nstr, len + 1);
  SYSTEM.MOVE(SYSTEM.ADR(str^) + start , SYSTEM.ADR(nstr^), len);
  nstr[len] := 0X;
  RETURN nstr
END Tail;

PROCEDURE Drop*(str: String;   count: LONGINT): String;
(** Return str without its first count characters.
  * Return the entire str, if count is thusly large.
  * Return NIL if str is NIL.
  *)
VAR
  len: LONGINT;
  res: String;
BEGIN
  IF  str = NIL THEN
    RETURN NIL
  END;
  count := KeepWithin(0, count, LEN(str^));
  len := Length(str);
  IF len < count THEN
    res := Empty()
  ELSE
    res := Tail(str, len - count);
  END;
  RETURN res
END Drop;

PROCEDURE DropTail*(str: String;   count: LONGINT): String;
(** Return str without its last count characters.
  * Return the empty str, if count is thusly large.
  * Return NIL if str is NIL.
  *)
VAR
  len: LONGINT;
  res: String;
BEGIN
  IF  str = NIL THEN
    RETURN NIL
  END;
  count := KeepWithin(0, count, LEN( str^));
  len := Length(str);
  IF len < count THEN
    res := Empty()
  ELSE
    res := Head(str, len - count);
  END;
  RETURN res
END DropTail;


(*---------------------------------------------------------------------------*)
PROCEDURE Append*(r, s: String): String;
(** Return new string str := r ++ s. *)
VAR
  i, rlen, slen: LONGINT;
  str: String;
BEGIN
  IF (r = NIL) OR (s = NIL) THEN
    RETURN NIL
  END;
  rlen := Length(r);
  slen := Length(s);

  NEW(str, slen + rlen + 1);
  SYSTEM.MOVE(SYSTEM.ADR(r^), SYSTEM.ADR(str^), rlen );
  SYSTEM.MOVE(SYSTEM.ADR(s^), SYSTEM.ADR(str^) + rlen, slen );
  str[rlen + slen] := 0X;
  RETURN str
END Append;

PROCEDURE Insert*(r, s: String;   pos: LONGINT): String;
(** Return new string with s inserted in r at pos
  * Return NIL if   (pos < 0) OR (pos > Length( r ))
  *)
VAR
  i, rlen, slen: LONGINT;
  str: String;
BEGIN
  IF (r = NIL) OR (s = NIL) THEN
    RETURN NIL
  END;
  rlen := Length(r);
  IF (pos < 0) OR (pos > rlen) THEN
    str := NIL
  ELSE
    slen := Length(s);

    NEW( str, rlen + slen + 1 );
    SYSTEM.MOVE(SYSTEM.ADR(r^), SYSTEM.ADR(str^), pos );
    SYSTEM.MOVE(SYSTEM.ADR(s^), SYSTEM.ADR(str^) + pos, slen );
    SYSTEM.MOVE(SYSTEM.ADR(r^) + pos, SYSTEM.ADR(str^) + pos + slen, rlen - pos);
    str[rlen + slen] := 0X
  END;
  RETURN str
END Insert;


PROCEDURE Delete*(str: String;  pos, len: LONGINT): String;
(** Return new string with starting from pos len characters deleted.
  * Return NIL if (pos < 0).
  * Return head of str if pos and len are thusly large.
  *)
VAR
  i, slen, nlen, mx: LONGINT;
  seq: String;
BEGIN
  IF pos < 0 THEN
    seq := NIL
  ELSE
    slen := Length(str);
    len := Max(0, len);
    (*  ..........      slen     *)
    (*         .......  del want *)
    (*         ...      del do   *)
    nlen := Max(0,   slen - len + KeepWithin(0, len, pos + len - slen));
    mx := Min(pos, slen);
    NEW(seq, nlen + 1);

    i := 0;
    WHILE i < mx DO
      seq[i] := str[i];
      INC(i)
    END;
    i := i + len;
    WHILE i < slen DO
      seq[i - len] := str[i];
      INC(i)
    END;
    seq[i - len] := 0X;
  END;
  RETURN seq
END Delete;


(*---------------------------------------------------------------------------*)
PROCEDURE IsEqual*(str, seq: String): BOOLEAN;
BEGIN
  (* Is Nil = Nil ? Yes! *)
  IF (str = NIL) & (seq = NIL) THEN
    RETURN TRUE
  ELSIF (str = NIL) OR (seq = NIL) THEN
    RETURN FALSE
  ELSE
    RETURN str^ = seq^
  END
END IsEqual;

PROCEDURE IsEqualHead*(str, seq: String): BOOLEAN;
BEGIN
  (* Is Nil a head sequence of Nil? No! *)
  IF (str = NIL) OR (seq = NIL) THEN
    RETURN FALSE
  ELSE RETURN IsEqual(Head(str, Length(seq)), seq)
  END
END IsEqualHead;

PROCEDURE IsMember*(c: CHAR;   str: String): BOOLEAN;
VAR
  i, max: LONGINT;
  cc: CHAR;
BEGIN
  max := LEN(str^);
  i := 0;
  LOOP
    IF i = max THEN RETURN FALSE END;
    cc := str[i];
    IF cc = c THEN RETURN TRUE END;
    IF cc = 0X THEN RETURN FALSE END;
    INC(i)
  END
END IsMember;

PROCEDURE FindChar*(str: String;   VAR pos: LONGINT;   c: CHAR): BOOLEAN;
(** Return TRUE if starting from pos c was found in str.
  * Return FALSE if c was not found or (pos > Length(str)).
  * In case of (pos < 0) searching starts with pos := 0 .
  * Only when c was found, pos is changed to position of c.
  *)
VAR
  i, max, mx: LONGINT;
BEGIN
  max := LEN(str^);
  mx := KeepWithin(0, pos, max);
  i := 0;
  WHILE (i < mx) & (str[i] # 0X) DO
    INC(i)
  END;

  WHILE (i < max) & (str[i] # c) & (str[i] # 0X) DO
    INC(i);
  END;
  IF (i < max) & (str[i] = c) THEN
    pos := i;
    RETURN TRUE
  ELSE
    RETURN FALSE
  END
END FindChar;

PROCEDURE FindSeq*(str: String;   VAR pos: LONGINT;   seq: String): BOOLEAN;
(** Return TRUE if starting from pos seq was found in str.
  * Return FALSE if seq was not found or (pos > Length(str) - Length(seq)) .
  * In case of (pos < 0) searching starts with pos := 0 .
  * Only when seq was found, pos is changed to position of seq.
  *)
VAR
  i, j, p, max, slen: LONGINT;
  res : BOOLEAN;
BEGIN
  p := Max(0, pos);
  slen := Length(seq);
  max := Length(str) - slen;
  res := FALSE;
  WHILE (p <= max) & ~res DO
    j := 0;
    WHILE (j < slen) & (str[p+j] = seq[j]) DO
      INC(j)
    END;
    IF j = slen THEN
      pos := p;
      res := TRUE
    ELSE
      INC(p)
    END
  END;
  RETURN res
END FindSeq;


(*---------------------------------------------------------------------------*)
PROCEDURE Fill*(VAR str: String;   start, len: LONGINT;   c: CHAR);
(** From start overwrite len characters with c. *)
VAR
  i, last: LONGINT;
BEGIN
  start := Max(0, start);
  last := Min(LEN(str^), start + len);
  i := start;
  WHILE i < last DO
    str[i] := c;
    INC(i)
  END
END Fill;

PROCEDURE Replace*( VAR str: String;   VAR pos: LONGINT;   seq: String);
(** In str, beginning from pos, replace i.e. overwrite with seq,
  * exclusive seq's terminating 0X.
  * (pos := -1) and leave str unchanged, if the to be replaced area
  * is not in (0..LEN(str)) .
  * A 0X in str may be overwritten without being replaced.
  *)
VAR
  i, max, slen: LONGINT;
BEGIN
  max := LEN(str^);
  slen := Length(seq);
  IF (pos < 0) OR (pos + slen - 1 >= max) THEN
    pos := -1
  ELSE
    IF slen > 0 THEN
      SYSTEM.MOVE(SYSTEM.ADR(seq^), SYSTEM.ADR(str^) + pos, slen);
    END
  END
END Replace;

PROCEDURE PushAOC*(VAR str: String;  VAR pos: LONGINT;   s: ARRAY OF CHAR);
(** Starting at pos overwrite str with s.
  * Terminate with 0X.
  * Advance pos to position of new appended 0X.
  * Set (pos := -1) and leave str as is if (pos < 0) or str too small.
  **)
VAR
  max, slen: LONGINT;
BEGIN
  max := LEN(str^);
  slen := AOCLength(s);
  IF (pos < 0) OR (pos + slen >= max) THEN
    pos := -1
  ELSE
    SYSTEM.MOVE(SYSTEM.ADR(s), SYSTEM.ADR(str^) + pos, slen);
    pos := pos + slen;
    str[pos] := 0X;
  END;
END PushAOC;

PROCEDURE Push*(VAR str: String;  VAR pos: LONGINT;   seq: String);
(** Starting at pos overwrite str with seq.
  * Terminate with 0X.
  * Advance pos to position of new appended 0X.
  * Set (pos := -1) and leave str as is if (pos < 0) or str too small.
  **)
BEGIN
  PushAOC( str, pos, seq^);
END Push;

PROCEDURE PushChar*(VAR str: String;  VAR pos: LONGINT;   c: CHAR);
(** If pos leads out of bounds of str leave str as is and (pos := -1) .
  * others:
  *   str[pos]     := c
  *   str[pos + 1] := 0X
  **)
VAR
BEGIN
  IF (pos < 0) OR (pos >= LEN(str^) - 1) THEN
    pos := -1
  ELSE
    str[pos] := c;
    INC(pos);
    str[pos] := 0X;
  END
END PushChar;

PROCEDURE PushInt*(VAR str: String;  VAR pos: LONGINT;   n: LONGINT);
(** Starting at pos overwrite str with ascii representation of n.
  * Terminate with 0X
  * Advance pos to position of new appended 0X.
  * Set (pos := -1) and leave str unchanged if (pos < 0) or str too small.
  *)
CONST
  sa = 32;  (* size of array *)
VAR
  i, j, d: LONGINT;
  neg: BOOLEAN;
  s: ARRAY sa OF CHAR;
  seq: String;
BEGIN
  (* store string at tail of s *)
  i := sa;   (* i points full *)
  DEC(i);
  s[i] := 0X;

  IF n = 0 THEN
    seq := Create("0")
  ELSIF n = MIN(LONGINT) THEN
    seq := Create("-2147483648")
  ELSE

    IF n < 0 THEN
      neg := TRUE;
      n := -n
    ELSE
      neg := FALSE
    END;

    WHILE n > 0 DO
      d := n MOD 10;
      n := n DIV 10;
      DEC( i );
      s[i] := CHR(d + 48);
    END;

    IF neg THEN
      DEC(i);
      s[i] := '-'
    END;

    NEW(seq, sa - i + 1);
    j := 0;
    WHILE j < sa - i DO
      seq[j] := s[i+j];
      INC(j)
    END;
    seq[j] := 0X;

  END;
  Push(str, pos, seq);
END PushInt;

PROCEDURE Quote*(c1: CHAR;   str: String;   c2: CHAR): String;
(** Wrap str in c1 and c2 *)
VAR
  pos: LONGINT;
  res: String;
BEGIN
  res := New(Length(str) + 2, 0X);
  pos := 0;
  PushChar(res, pos, c1);
  Push(res, pos, str);
  PushChar(res, pos, c2);
  RETURN res
END Quote;


(*---------------------------------------------------------------------------*)
PROCEDURE Next*( VAR seq: String;  str: String;   VAR pos: LONGINT;  c: CHAR): BOOLEAN;
(** Set seq to next subsequence of str from pos to delimiting character c
  * or from pos to end of string, exclusive delimiter c.
  * Advance pos to pos of c.
  * Return true, if a sequence is found.
  * Return false and leave seq and pos as is if not, that is pos is at end of string.
  *)
VAR
  max, i: LONGINT;
BEGIN
  max := LEN(str^);
  pos := KeepWithin(0, pos, max);
  i := pos;
  WHILE (i < max) & (str[i] # c) & (str[i] # 0X) DO
    INC(i)
  END;
  IF (i = pos) & ((i = max) OR (str[i] = 0X)) THEN
    RETURN FALSE
  ELSE
    seq := Sub(str,pos ,i - pos);
    pos := i;
    RETURN TRUE
  END
END Next;

PROCEDURE ReadInt*(str: String;   VAR pos, value: LONGINT): BOOLEAN;
(** Read integer from String.
  * Start reading from pos.
  * If successfull:
  *     update pos to the first position behind value.
  *     update value to the read integer value.
  *     return TRUE.
  * else return FALSE.
  *)
VAR
  i, p, max, v: LONGINT;
  cc: CHAR;
  sign: INTEGER;
  sc: BOOLEAN;  (* sign char *)
BEGIN
  max := LEN(str^);
  p := KeepWithin(0, pos, max);
  v := 0;
  sign := 1;
  sc := FALSE;
  i := p;
  IF i < max THEN
    cc := str[i];
    IF cc = "+" THEN
      sc := TRUE;
      INC(i)
    ELSIF cc = "-" THEN
      sc := TRUE;
      sign := -1;
      INC(i)
    END
  END;

  LOOP
    IF i = max THEN
      EXIT
    END;
    cc := str[i];
    IF (cc < "0") OR (cc > "9") OR (cc = 0X) THEN
      EXIT
    END;
    v := v * 10 + ORD(cc) - 48;
    INC(i)
  END;

  IF (~sc & (i = p)) OR (sc & (i - 1 = p)) THEN
    RETURN FALSE
  ELSE
    pos := i;
    value := sign * v;
    RETURN TRUE
  END
END ReadInt;

PROCEDURE ReadChar*(str: String;   VAR pos: LONGINT;   c: CHAR): BOOLEAN;
(** Return true and increment pos if str[pos] = c.
  * Return false and leave pos as is if not.
  *)
VAR
  p, max: LONGINT;
BEGIN
  max := LEN(str^);
  p := Max(0, pos);
  IF (p < max) & (str[p] = c) THEN
    pos := p + 1;
    RETURN TRUE
  ELSE
    RETURN FALSE
  END
END ReadChar;

PROCEDURE ReadWhileChar*(str: String;
                         VAR pos: LONGINT;
                         fn: PROCEDURE(c:CHAR):BOOLEAN
                    ):BOOLEAN;

VAR
  i, p, max: LONGINT;
BEGIN
  max := LEN(str^);
  p := Max(0, pos);
  i := p;
  WHILE (i < max) & fn(str[i]) DO
    INC(i)
  END;
  IF i # p THEN
    pos := i;
    RETURN TRUE
  ELSE
    RETURN FALSE
  END
END ReadWhileChar;

(*---------------------------------------------------------------------------*)
PROCEDURE Maximal*(str: String;   width: LONGINT): String;
(** Return a new copy of str, maximal of length width (discard tail) *)
VAR
  i, len: LONGINT;
  nstr: String;
BEGIN
  IF (str = NIL) OR (width < 0) THEN
    RETURN NIL
  END;
  len := Length(str);
  IF width > len THEN
    width := len
  END;
  NEW(nstr, width + 1);
  COPY(str^, nstr^);
  nstr[width] := 0X;
  RETURN nstr
END Maximal;

PROCEDURE PadLeft*(str: String;   width: LONGINT;   c: CHAR): String;
(** If str is shorter than width pad at left side with c.
  * SEE ALSO: Strings.Indent
  *)
VAR
  i, len, pad: LONGINT;
  seq: String;
BEGIN
  IF str = NIL THEN
    RETURN NIL
  END;
  width := Max(0, width);
  len := Length(str);
  pad := Max(0, width - len);

  NEW(seq, len + pad + 1);
  i := 0;
  WHILE i < pad DO
    seq[i] := c;
    INC(i)
  END;
  i := 0;
  WHILE i < len DO
    seq[i + pad] := str[i];
    INC(i)
  END;
  seq[i + pad] := 0X;
  RETURN seq
END PadLeft;

PROCEDURE PadRight*(str: String;   width: LONGINT;   c: CHAR): String;
(** If str is shorter than width pad at right side with c. *)
VAR
  i, len, pad: LONGINT;
  seq: String;
BEGIN
  IF str = NIL THEN
    RETURN NIL
  END;
  width := Max(0, width);
  len := Length(str);
  pad := Max(0, width - len);

  NEW(seq, len + pad + 1);
  i := 0;
  WHILE i < len DO
    seq[i] := str[i];
    INC(i)
  END;
  WHILE i < len + pad DO
    seq[i] := c;
    INC(i)
  END;
  seq[i] := 0X;
  RETURN seq
END PadRight;

PROCEDURE Trim*(str: String;   c: CHAR): String;
(** Return new copy of str with leading and trailing characters c removed. *)
VAR
  start, stop, i, max: LONGINT;
  seq: String;
BEGIN
  IF str = NIL THEN
    RETURN NIL
  END;
  max := Length(str);
  start := 0;
  stop := max - 1;
  WHILE (start < max) & (str[start] = c)  DO
    INC(start);
  END;
  WHILE (stop >= start) & (str[stop] = c) DO
    DEC(stop)
  END;
  IF start > stop THEN
    NEW(seq, 1);
    seq[0] := 0X
  ELSE
    NEW(seq, stop - start + 2);
    i := start;
    WHILE i <= stop DO
      seq[i-start] := str[i];
      INC(i)
    END;
    seq[i-start] := 0X;
  END;
  RETURN seq
END Trim;

PROCEDURE TrimRight*(str: String;   c: CHAR): String;
(** Return new copy of str with trailing characters c removed. *)
VAR
  i: LONGINT;
BEGIN
  IF str = NIL THEN
    RETURN NIL
  END;
  i := Length(str) - 1;
  WHILE (i >= 0) & (str[i] = c) DO
    DEC(i)
  END;
  RETURN Head(str, i + 1);
END TrimRight;

PROCEDURE TrimRight1*(str: String;   c: CHAR): String;
(** Return new copy of str with trailing characters c removed
  * except for one.
  * If there is no trailing character c append one.
  *)
VAR
  i, j: LONGINT;
  seq: String;
BEGIN
  IF str = NIL THEN
    RETURN NIL
  END;
  i := Length(str) - 1;
  WHILE (i >= 0) & (str[i] = c) DO
    DEC(i)
  END;
  NEW(seq, i + 3);
  j := 0;
  WHILE j <= i DO
    seq[j] := str[j];
    INC(j)
  END;
  seq[j] := c;
  seq[j + 1] := 0X;
  RETURN seq
END TrimRight1;


(*---------------------------------------------------------------------------*)
PROCEDURE Spaces*(len: LONGINT): String;
(** Return a string of len spaces. *)
BEGIN
  RETURN New(Max(0, len), " ")
END Spaces;

PROCEDURE SkipWhitespace*(str: String;   VAR pos: LONGINT);
(** Starting at pos skip whitespace:  \space \tab *)
VAR
  p, max: LONGINT;
  cc: CHAR;
BEGIN
  IF (str = NIL) OR (pos < 0) THEN
    pos := -1;
    RETURN
  END;
  max := LEN(str^);
  p := pos;
  LOOP
    IF p = max THEN
      EXIT
    END;
    cc := str[p];
    IF (cc > " ") OR (cc = 0X) THEN
      EXIT
    END;
    INC(p);
  END;
  pos := p
END SkipWhitespace;


PROCEDURE Indentation*(str: String): LONGINT;
(** Return indentation of str.
  * Currently only spaces are counted.
  * Not tabs.
  *)
VAR
  i, max: LONGINT;
BEGIN
  IF str = NIL THEN
    RETURN -1
  END;
  max := LEN(str^);
  i := 0;
  WHILE (i < max) & (str[i] = " ")  DO
    INC(i);
  END;
  RETURN i
END Indentation;

PROCEDURE Indent*(str: String;   width: LONGINT): String;
(** Return new string with indentation adjusted to width. *)
VAR
  oldi, slen, nlen, i: LONGINT;
  nstr: String;
BEGIN
  IF (str = NIL) OR (width < 0) THEN
    RETURN NIL
  END;
  slen := Length(str);
  oldi := Indentation(str);
  nlen := width + slen - oldi;
  NEW(nstr, nlen + 1);
  i := 0;
  WHILE i < width DO
    nstr[i] := " ";
    INC(i)
  END;
  WHILE i < nlen DO
    nstr[i] := str[i + oldi - width];
    INC(i)
  END;
  nstr[i] := 0X;
  RETURN nstr
END Indent;

PROCEDURE Reverse*(str: String): String;
(** Return new string: the reverse of str. *)
VAR
  i, len: LONGINT;
  seq: String;
BEGIN
  IF str = NIL THEN
    RETURN NIL
  END;
  len := Length(str);
  NEW(seq, len + 1);
  i := 0;
  WHILE i < len DO
    seq[len - i - 1] := str[i];
    INC(i)
  END;
  seq[i] := 0X;
  RETURN seq
END Reverse;


(*---------------------------------------------------------------------------*)
END Strings.   (* (c) sts-q 2022-Mrz *)
