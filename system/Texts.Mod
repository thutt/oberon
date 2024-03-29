MODULE Texts; (*JG 23.8.94*)
  IMPORT Files, Objects, Display, Fonts, Reals;

  CONST
    (*symbol classes*)

    Inval* = 0;           (*invalid symbol*)
    Name* = 1;        (*name s (length len)*)
    String* = 2;        (*literal string s (length len)*)
    Int* = 3;             (*integer i (decimal or hexadecimal)*)
    Real* = 4;          (*real number x*)
    LongReal* = 5;  (*long real number y*)
    Char* = 6;          (*special character c*)

    TAB = 9X; CR = 0DX;
    OldTextBlockId = 1X; OldTextSpex = 0F0X;

    (* TextBlock = TextBlockId type hlen run {run} 0 tlen {AsciiCode} [font block].
      run = font [name] col voff len. *)

TYPE
    Piece = POINTER TO PieceDesc;

    PieceDesc = RECORD
      f: Files.File;
      off: LONGINT;
      len: LONGINT;
      obj: Objects.Object;
      lib: Objects.Library;
      col: LONGINT;
      voff: SHORTINT;
      prev, next: Piece
    END;

    Text* = POINTER TO TextDesc;

    TextDesc* = RECORD (Objects.ObjDesc)
      len*: LONGINT;
      obs*: Objects.Library;
      trailer: Piece;
      org: LONGINT; (*cache*)
      pce: Piece
    END;

    UpdateMsg* = RECORD (Display.FrameMsg)
      text*: Text;
      beg*, end*, len*: LONGINT
    END;

    Finder* = RECORD
      eot*: BOOLEAN;
      pos*: LONGINT;
      ref: Piece
    END;

    Reader* = RECORD
      ref: Piece;
      org: LONGINT;
      off: LONGINT;
      R: Files.Rider;
      eot*: BOOLEAN;
      lib*: Objects.Library;
      col*: LONGINT;
      voff*: SHORTINT
    END;

    Scanner* = RECORD (Reader)
      nextCh*: CHAR;
      line*: INTEGER;
      class*: INTEGER;
      i*: LONGINT;
      x*: REAL;
      y*: LONGREAL;
      c*: CHAR;
      len*: SHORTINT;
      s*: ARRAY 32 OF CHAR
    END;

    Buffer* = POINTER TO BufDesc;

    BufDesc* = RECORD
      len*: LONGINT;
      header, last: Piece
    END;

    Writer* = RECORD
      R: Files.Rider;
      buf*: Buffer;
      lib*: Objects.Library;
      col*: LONGINT;
      voff*: SHORTINT
    END;

  VAR TextBlockId*, DocBlockId, NoSpex, TextSpex: CHAR;
    Wfile: Files.File; R: Files.Rider; DelBuf: Buffer; H: Objects.Handler;
    UndefColor : Display.COLOR;

  PROCEDURE Min (i, j: LONGINT): LONGINT;
  BEGIN IF i >= j THEN RETURN j ELSE RETURN i END
  END Min;

  PROCEDURE EQ (VAR s, t: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (s[i] # 0X) & (t[i] # 0X) & (s[i] = t[i]) DO INC(i) END;
    RETURN s[i] = t[i]
  END EQ;

  PROCEDURE ReadLong (VAR R: Files.Rider; VAR x: LONGINT);
  VAR c0, c1, c2: CHAR; s1: SHORTINT;
  BEGIN Files.Read(R, c0); Files.Read(R, c1); Files.Read(R, c2); Files.Read(R, s1);
  x := s1; x := ((x * 100H + LONG(ORD(c2))) * 100H + LONG(ORD(c1))) * 100H + LONG(ORD(c0))
  END ReadLong;

  PROCEDURE WriteLong (VAR R: Files.Rider; x: LONGINT);
  BEGIN Files.Write(R, CHR(x)); Files.Write(R, CHR(x DIV 100H));
  Files.Write(R, CHR(x DIV 10000H)); Files.Write(R, CHR(x DIV 1000000H))
  END WriteLong;

  PROCEDURE ReadName (VAR R: Files.Rider; VAR name: ARRAY OF CHAR);
    VAR i: INTEGER; ch: CHAR;
  BEGIN
    i := 0; Files.Read(R, ch);
    WHILE ch # 0X DO
      name[i] := ch; INC(i); Files.Read(R, ch)
    END;
    name[i] := 0X
  END ReadName;

  PROCEDURE ReadDocHeader (VAR R: Files.Rider);
    VAR ch: CHAR; x, y, w, h: INTEGER; name: ARRAY 32 OF CHAR;
  BEGIN Files.Read(R, ch);
    Files.ReadString(R, name);
    Files.ReadInt(R, x); Files.ReadInt(R, y);
    Files.ReadInt(R, w); Files.ReadInt(R, h)
  END ReadDocHeader;

  PROCEDURE WriteName (VAR W: Files.Rider; VAR name: ARRAY OF CHAR);
    VAR i: INTEGER; ch: CHAR;
  BEGIN
    i := 0; ch := name[i];
    WHILE ch # 0X DO
      Files.Write(W, ch); INC(i); ch := name[i]
    END;
    Files.Write(W, 0X)
  END WriteName;

  PROCEDURE Load* (T: Text; f: Files.File; pos: LONGINT; VAR len: LONGINT);
    VAR
      R, S: Files.Rider;
      L: Objects.Library;
      Q, q, p: Piece;
      hlen, tlen, flen, off: LONGINT;
      N, lib: SHORTINT;
      type, ref: CHAR;
      LName: ARRAY 32 OF CHAR;
      Dict: ARRAY 32 OF Objects.Library;
  BEGIN
      NEW(Q); Q.f := Wfile; Q.off := 0; Q.len := 1;
      Q.lib := NIL; Q.col := UndefColor; Q.voff := 0;
      p := Q;
      Files.Set(R, f, pos);
      Files.Read(R, type);
      ReadLong(R, hlen);
      Files.Set(S, f, pos - 1 + hlen - 4);
      ReadLong(S, tlen);
      IF (type = TextSpex) OR (type = OldTextSpex) THEN L := NIL; flen := 0
      ELSE NEW(L); Objects.OpenLibrary(L);
        Objects.LoadLibrary(L, f, pos - 1 + hlen + tlen + 1, flen);
        INC(flen)
      END;
      Dict[0] := L;
      N := 1;
      off := pos - 1 + hlen;
      WHILE Files.Pos(R) < pos - 1 + hlen - 5 DO
        Files.Read(R, lib);
        IF lib = N THEN
          ReadName(R, LName);
          Dict[N] := Objects.ThisLibrary(LName);
          INC(N)
        END;
        NEW(q); q.lib := Dict[lib];
        IF ~(q.lib IS Fonts.Font) THEN
          Files.Set(S, f, off); Files.Read(S, ref); q.lib.GetObj(q.lib, ORD(ref), q.obj)
        END;
        Files.ReadNum(R, q.col);
        Files.Read(R, q.voff);
        ReadLong(R, q.len);
        q.f := f; q.off := off;
        off := off + q.len;
        p.next := q; q.prev := p; p := q
      END;
      p.next := Q; Q.prev := p;
      T.handle := H; T.obs := NIL;
      T.trailer := Q; T.len := tlen;
      T.org := -1; T.pce := T.trailer; (*init cache*)
      len := hlen - 1 + tlen + flen
  END Load;

  PROCEDURE Store* (T: Text; f: Files.File; pos: LONGINT; VAR len: LONGINT);
    VAR
      p, q: Piece;
      R, W: Files.Rider;
      hlen, flen, rlen, m: LONGINT;
      id, i: INTEGER;
      N, n: SHORTINT;
      type, ch: CHAR;
      lib: Objects.Library;
      obj: Objects.Object;
      M: Objects.BindMsg;
      Dict: ARRAY 32 OF Objects.Name;
      objs: ARRAY 256 OF Objects.Object;
  BEGIN
    Files.Set(W, f, pos);
    Files.Write(W, TextBlockId);
    Files.Write(W, type); (*place holder*)
    WriteLong(W, hlen); (*place holder*)
    Dict[0] := "";
    N := 1;
    p := T.trailer.next;
    WHILE p # T.trailer DO
      rlen := p.len; q := p.next;
      IF p.lib IS Fonts.Font THEN
        WHILE (q # T.trailer) & (q.lib = p.lib) & (q.col = p.col) & (q.voff = p.voff) DO
          rlen := rlen + q.len; q := q.next
        END
      END;
      Dict[N] := p.lib.name;
      n := 0;
      WHILE ~EQ(Dict[n], p.lib.name) DO INC(n) END;
      Files.Write(W, n);
      IF n = N THEN WriteName(W, p.lib.name); INC(N) END;
      Files.WriteNum(W, p.col);
      Files.Write(W, p.voff);
      WriteLong(W, rlen);
      p := q
    END;
    Files.Write(W, 0); WriteLong(W, T.len);
    hlen := Files.Pos(W) - pos;
    id := 0; p := T.trailer.next;
    WHILE p # T.trailer DO
      Files.Set(R, p.f, p.off); m := p.len;
      WHILE m # 0 DO Files.Read(R, ch);
        IF p.lib.name[0] = 0X THEN
          p.lib.GetObj(p.lib, ORD(ch), obj);
          objs[id] := obj; i := 0;
          WHILE (objs[i] # obj) DO INC(i) END;
          IF i = id THEN INC(id) END;
          ch := CHR(i)
        END;
        Files.Write(W, ch); DEC(m)
      END;
      p := p.next
    END;
    IF id # 0 THEN type := NoSpex;
      NEW(lib); Objects.OpenLibrary(lib); i := 0;
      REPEAT lib.PutObj(lib, i, objs[i]); INC(i) UNTIL i = id;
      M.lib := lib; i := 0;
      REPEAT objs[i].handle(objs[i], M); INC(i) UNTIL i = id;
      Objects.StoreLibrary(lib, f, pos + hlen + T.len, flen)
    ELSE type := TextSpex; flen := 0 (*no integrated objects*)
    END;
    Files.Set(W, f, pos + 1);
    Files.Write(W, type); (*fixup*)
    WriteLong(W, hlen); (*fixup*)
    len := hlen + T.len + flen
  END Store;

  PROCEDURE GenNew (T: Text);
    VAR Q: Piece;
  BEGIN
    NEW(Q); Q.f := Wfile; Q.off := 0; Q.len := 1;
    Q.lib := NIL; Q.col := UndefColor; Q.voff := 0;
    Q.next := Q; Q.prev := Q;
    T.handle := H; T.obs := NIL;
    T.trailer := Q; T.len := 0;
    T.org := -1; T.pce := T.trailer (*init cache*)
  END GenNew;

  PROCEDURE GenAscii (T: Text; f: Files.File);
    VAR Q, q: Piece; len: LONGINT;
  BEGIN len := Files.Length(f);
    NEW(Q); Q.f := Wfile; Q.off := 0; Q.len := 1;
    Q.lib := NIL; Q.col := UndefColor; Q.voff := 0;
    NEW(q); q.f := f; q.off := 0; q.len := len;
    q.lib := Fonts.Default; q.col := Display.white; q.voff := 0;
    Q.next := q; q.prev := Q; q.next := Q; Q.prev := q;
    T.handle := H; T.obs := NIL;
    T.trailer := Q; T.len := len;
    T.org := -1; T.pce := T.trailer (*init cache*)
  END GenAscii;

  PROCEDURE Open* (T: Text; name: ARRAY OF CHAR);
    VAR f: Files.File; R: Files.Rider; len: LONGINT; ch: CHAR;
  BEGIN f := Files.Old(name);
    IF f # NIL THEN
      Files.Set(R, f, 0); Files.Read(R, ch);
      IF ch = DocBlockId THEN ReadDocHeader(R); Files.Read(R, ch) END;
      IF (ch = TextBlockId) OR (ch = OldTextBlockId) THEN Load(T, f, Files.Pos(R), len)
      ELSE GenAscii(T, f)
      END
    ELSE GenNew(T)
    END
  END Open;

  PROCEDURE New*;
    VAR T: Text;
  BEGIN NEW(T); T.handle := H; GenNew (T); Objects.NewObj := T
  END New;

  PROCEDURE FindPiece (T: Text; pos: LONGINT; VAR org: LONGINT; VAR p: Piece);
    VAR n: INTEGER;
  BEGIN
    IF pos < T.org THEN T.org := -1; T.pce := T.trailer END;
    org := T.org; p := T.pce; (*from cache*)
    n := 0;
    WHILE pos >= org + p.len DO org := org + p.len; p := p.next; INC(n) END;
    IF n > 50 THEN T.org := org; T.pce := p END
  END FindPiece;

  PROCEDURE SplitPiece (p: Piece; off: LONGINT; VAR pr: Piece);
    VAR q: Piece;
  BEGIN
    IF off > 0 THEN NEW(q);
      q.lib := p.lib; q.col := p.col; q.voff := p.voff;
      q.len := p.len - off;
      q.f := p.f; q.off := p.off + off;
      p.len := off;
      q.next := p.next; p.next := q;
      q.prev := p; q.next.prev := q;
      pr := q
    ELSE pr := p
    END
  END SplitPiece;

  PROCEDURE Insert* (T: Text; pos: LONGINT; B: Buffer);
    VAR pl, pr, p, qb, qe: Piece; org: LONGINT; M: UpdateMsg;
  BEGIN
    FindPiece(T, pos, org, p); SplitPiece(p, pos - org, pr);
    IF T.org >= org THEN (*adjust cache*)
      T.org := org - p.prev.len; T.pce := p.prev
    END;
    pl := pr.prev; qb := B.header.next;
    IF (qb # NIL) & (qb.f = pl.f) & (qb.off = pl.off + pl.len) & (pl.lib IS Fonts.Font)
      & (pl.lib = qb.lib) & (pl.col = qb.col) & (pl.voff = qb.voff) THEN
      pl.len := pl.len + qb.len; qb := qb.next
    END;
    IF qb # NIL THEN
      qe := B.last; qb.prev := pl; pl.next := qb; qe.next := pr; pr.prev := qe
    END;
    T.len := T.len + B.len;
    M.text := T; M.F := NIL; M.beg := pos; M.end := pos; M.len := B.len;
    B.last := B.header; B.last.next := NIL; B.len := 0;
    Display.Broadcast(M)
  END Insert;

  PROCEDURE Append* (T: Text; B: Buffer);
  BEGIN Insert(T, T.len, B)
  END Append;

  PROCEDURE Delete* (T: Text; beg, end: LONGINT);
    VAR pb, pe, pbr, per: Piece; orgb, orge: LONGINT; M: UpdateMsg;
  BEGIN
    IF beg < end THEN
      FindPiece(T, beg, orgb, pb); SplitPiece(pb, beg - orgb, pbr);
      FindPiece(T, end, orge, pe); SplitPiece(pe, end - orge, per);
      IF T.org >= orgb THEN (*adjust cache*)
        T.org := orgb - pb.prev.len; T.pce := pb.prev
      END;
      DelBuf.header.next := pbr; DelBuf.last := per.prev;
      DelBuf.last.next := NIL; DelBuf.len := end - beg;
      per.prev := pbr.prev; pbr.prev.next := per;
      T.len := T.len - end + beg;
      M.text := T; M.F := NIL; M.beg := beg; M.end := end; M.len := 0;
      Display.Broadcast(M)
    END
  END Delete;

  PROCEDURE Replace* (T: Text; beg, end: LONGINT; B: Buffer);
    VAR M: UpdateMsg; pb, pe, pbr, per, pl, qb, qe: Piece; orgb, orge: LONGINT;
  BEGIN
    IF beg < end THEN
      FindPiece(T, beg, orgb, pb); SplitPiece(pb, beg - orgb, pbr);
      FindPiece(T, end, orge, pe); SplitPiece(pe, end - orge, per);
      IF T.org >= orgb THEN (*adjust cache*)
        T.org := orgb - pb.prev.len; T.pce := pb.prev
      END;
      DelBuf.header.next := pbr; DelBuf.last := per.prev;
      DelBuf.last.next := NIL; DelBuf.len := end - beg;
      per.prev := pbr.prev; pbr.prev.next := per;
      pl := pbr.prev; qb := B.header.next;
      IF (qb # NIL) & (qb.f = pl.f) & (qb.off = pl.off + pl.len) & (pl.lib IS Fonts.Font)
        & (pl.lib = qb.lib) & (pl.col = qb.col) & (pl.voff = qb.voff) THEN
        pl.len := pl.len + qb.len; qb := qb.next
      END;
      IF qb # NIL THEN
        qe := B.last; qb.prev := pl; pl.next := qb; qe.next := per; per.prev := qe
      END;
      T.len := T.len - end + beg + B.len;
      M.text := T; M.F := NIL; M.beg := beg; M.end := end; M.len := B.len;
      B.last := B.header; B.last.next := NIL; B.len := 0;
      Display.Broadcast(M)
    END
  END Replace;

  PROCEDURE ChangeLooks* (T: Text; beg, end: LONGINT; sel: SET; lib: Objects.Library; col : Display.COLOR; voff: SHORTINT);
    VAR pb, pe, p: Piece; org: LONGINT; M: UpdateMsg;
  BEGIN
    IF beg < end THEN
      FindPiece(T, beg, org, p); SplitPiece(p, beg - org, pb);
      FindPiece(T, end, org, p); SplitPiece(p, end - org, pe);
      p := pb;
      REPEAT
        IF (0 IN sel) & (p.lib IS Fonts.Font) THEN p.lib := lib END;
        IF 1 IN sel THEN p.col := col END;
        IF 2 IN sel THEN p.voff := voff END;
        p := p.next
      UNTIL p = pe;
      M.text := T; M.F := NIL; M.beg := beg; M.end := end; M.len := end - beg;
      Display.Broadcast(M)
    END
  END ChangeLooks;

  PROCEDURE OpenBuf* (B: Buffer);
  BEGIN NEW(B.header); (*null piece*)
    B.last := B.header; B.len := 0
  END OpenBuf;

  PROCEDURE Save* (T: Text; beg, end: LONGINT; B: Buffer);
    VAR p, q, qb, qe: Piece; org: LONGINT;
  BEGIN
    IF beg < end THEN
      FindPiece(T, beg, org, p);
      NEW(qb); qb^ := p^;
      qb.len := qb.len - (beg - org);
      qb.off := qb.off + (beg - org);
      qe := qb;
      WHILE end > org + p.len DO
        org := org + p.len; p := p.next;
        NEW(q); q^ := p^; qe.next := q; q.prev := qe; qe := q
      END;
      qe.next := NIL; qe.len := qe.len - (org + p.len - end);
      B.last.next := qb; qb.prev := B.last; B.last := qe;
      B.len := B.len + (end - beg)
    END
  END Save;

  PROCEDURE Copy* (SB, DB: Buffer);
    VAR Q, q, p: Piece;
  BEGIN
    p := SB.header; Q := DB.last;
    WHILE p # SB.last DO p := p.next;
      NEW(q); q^ := p^; Q.next := q; q.prev := Q; Q := q
    END;
    DB.last := Q; DB.len := DB.len + SB.len
  END Copy;

  PROCEDURE Recall* (VAR B: Buffer); (*deleted text*)
  BEGIN Copy(DelBuf, B)
  END Recall;

  PROCEDURE Handle* (obj: Objects.Object; VAR M: Objects.ObjMsg);
    VAR T: Text; B: Buffer; len: LONGINT; id: INTEGER; ch: CHAR;
  BEGIN
    WITH obj: Text DO
      IF M IS Objects.AttrMsg THEN
        WITH M: Objects.AttrMsg DO
          IF M.name = "Gen" THEN M.s := "Texts.New" END
        END
      ELSIF M IS Objects.CopyMsg THEN
        WITH M: Objects.CopyMsg DO
          NEW(B); OpenBuf(B); Save(obj, 0, obj.len, B);
          NEW(T); T.handle := obj.handle; GenNew(T); Insert(T, 0, B); M.obj := T
        END
      ELSIF M IS Objects.BindMsg THEN
        WITH M: Objects.BindMsg DO
          IF (obj.lib = NIL) OR (obj.lib.name[0] = 0X) & (obj.lib # M.lib) THEN
            M.lib.GenRef(M.lib, id); M.lib.PutObj(M.lib, id, obj)
          END
        END
      ELSIF M IS Objects.FileMsg THEN
        WITH M: Objects.FileMsg DO
          IF M.id = Objects.load THEN Files.Read(M.R, ch);
            IF ch = DocBlockId THEN ReadDocHeader(R); Files.Read(R, ch) END;
            IF (ch = TextBlockId) OR (ch = OldTextBlockId) THEN
              Load(obj, Files.Base(M.R), Files.Pos(M.R), len);
              Files.Set(M.R, Files.Base(M.R), Files.Pos(M.R) + len)
            END
          ELSE (*M.id = Objects.store*)
            Store(obj, Files.Base(M.R), Files.Pos(M.R), len);
            Files.Set(M.R, Files.Base(M.R), Files.Pos(M.R) + len)
          END
        END
      END
    END
  END Handle;

  PROCEDURE OpenFinder* (VAR F: Finder; T: Text; pos: LONGINT);
    VAR p: Piece; org: LONGINT;
  BEGIN
    FindPiece(T, pos, org, p);
    WHILE (p.f # Wfile) & (p.lib IS Fonts.Font) DO
      org := org + p.len; p := p.next
    END;
    F.pos := org; F.ref := p; F.eot := FALSE
  END OpenFinder;

  PROCEDURE FindObj* (VAR F: Finder; VAR obj: Objects.Object);
    VAR p: Piece; org: LONGINT;
  BEGIN
    obj := F.ref.obj;
    IF F.ref.f = Wfile THEN F.eot := TRUE END;
    org := F.pos; p := F.ref;
    REPEAT org := org + p.len; p := p.next
    UNTIL (p.f = Wfile) OR ~(p.lib IS Fonts.Font);
    F.pos := org; F.ref := p
  END FindObj;

  PROCEDURE OpenReader* (VAR R: Reader; T: Text; pos: LONGINT);
    VAR p: Piece; org: LONGINT;
  BEGIN
    FindPiece(T, pos, org, p);
    R.ref := p; R.org := org; R.off := pos - org;
    Files.Set(R.R, R.ref.f, R.ref.off + R.off); R.eot := FALSE
  END OpenReader;

  PROCEDURE Read* (VAR R: Reader; VAR ch: CHAR);
  BEGIN
    Files.Read(R.R, ch);
    R.lib := R.ref.lib; R.col := R.ref.col; R.voff := R.ref.voff;
    INC(R.off);
    IF R.off = R.ref.len THEN
      IF R.ref.f = Wfile THEN R.eot := TRUE END;
      R.org := R.org + R.ref.len; R.ref := R.ref.next; R.off := 0;
      Files.Set(R.R, R.ref.f, R.ref.off)
    END
  END Read;

  PROCEDURE Pos* (VAR R: Reader): LONGINT;
  BEGIN RETURN R.org + R.off
  END Pos;

  PROCEDURE OpenScanner* (VAR S: Scanner; T: Text; pos: LONGINT);
  BEGIN OpenReader(S, T, pos); S.line := 0; Read(S, S.nextCh)
  END OpenScanner;

  (** Scanners --------------- NW --------------- **)

  (*IEEE floating-point formats  (BM 1992.1.1): (-1)^s * 1.m * 2^(e-e0), where

                              s                 e                 e0              m
      REAL             1-bit     8-bit biased      127    1+23-bit explicit
      LONGREAL   1-bit   11-bit biased     1023   1+52-bit explicit*)

  PROCEDURE Scan* (VAR S: Scanner);
    CONST maxD = 32; (* fixed size: maxD <= LEN(S.s)! *)
    VAR ch, term, E: CHAR;
      neg, negE, hex: BOOLEAN;
      i, j, h: SHORTINT;
      e: INTEGER; k, k1, k2, k3: LONGINT;
      y: LONGREAL;
      d: ARRAY maxD OF CHAR;

  BEGIN ch := S.nextCh; i := 0;
    LOOP
      IF ch = CR THEN INC(S.line)
      ELSIF (ch # " ") & (ch # TAB) THEN EXIT
      END ;
      Read(S, ch)
    END;
    IF ("A" <= CAP(ch)) & (CAP(ch) <= "Z") THEN (*name*)
      REPEAT S.s[i] := ch; INC(i); Read(S, ch)
      UNTIL (CAP(ch) > "Z") & (ch # "\")
        OR ("@" > CAP(ch)) & (ch > ":") & (ch # "_")    (* ARD ("A" > CAP(ch)) --> ("@" > CAP(ch)) *)
        OR ("0" > ch) & (ch # ".")
        OR (i = LEN(S.s)-1);
      S.s[i] := 0X; S.len := i; S.nextCh := ch; S.class := Name
    ELSIF ch = 22X THEN (*literal string*)
      Read(S, ch);
      WHILE (ch # 22X) & (ch >= " ") & (i # LEN(S.s)-1) DO
        S.s[i] := ch; INC(i); Read(S, ch)
      END;
      S.s[i] := 0X; S.len := i; Read(S, ch); S.class := String
    ELSE
      IF ch = "-" THEN neg := TRUE; Read(S, ch) ELSE neg := FALSE END ;
      IF ("0" <= ch) & (ch <= "9") THEN (*number*)
        hex := FALSE; j := 0;
        LOOP d[i] := ch; INC(i); Read(S, ch);
          IF ch < "0" THEN EXIT END;
          IF "9" < ch THEN
            IF ("A" <= ch) & (ch <= "F") THEN hex := TRUE; ch := CHR(ORD(ch)-7)
            ELSIF ("a" <= ch) & (ch <= "f") THEN hex := TRUE; ch := CHR(ORD(ch)-27H)
            ELSE EXIT
            END
          END
        END;
        IF ch = "H" THEN (*hex number*)
          Read(S, ch); S.class := Int;
          IF i-j > 8 THEN j := i-8 END ;
          k := ORD(d[j]) - 30H; INC(j);
          IF (i-j = 7) & (k >= 8) THEN DEC(k, 16) END ;
          WHILE j < i DO k := k*10H + (ORD(d[j]) - 30H); INC(j) END ;
          IF neg THEN S.i := -k ELSE S.i := k END
        ELSIF ch = "." THEN (*read real*)
          Read(S, ch); h := i;
          WHILE ("0" <= ch) & (ch <= "9") DO d[i] := ch; INC(i); Read(S, ch) END;
          (*-------- begin floating-point handling BM 1993.3.10 -----------------------------------*)
          WHILE i MOD 8 # 0 DO d[i] := "0"; INC(i) END;
          j := 0; k := 0; k1 := 0; k2 := 0; k3 := 0; (* store digits 0..7, 8..15, 16..23, 24..31 in k, k1, k2, k3 *)
          WHILE j < 8 DO k := k*10 + ORD(d[j]) - ORD("0"); INC(j) END;
          IF 8 < i THEN
            WHILE j < 16 DO k1 := k1*10 + ORD(d[j]) - ORD("0"); INC(j) END
          END;
          IF 16 < i THEN
            WHILE j < 24 DO k2 := k2*10 + ORD(d[j]) - ORD("0"); INC(j) END
          END;
          IF 24 < i THEN
            WHILE j < 32 DO k3 := k3*10 + ORD(d[j]) - ORD("0"); INC(j) END
          END;
          e := 0; E := ch;
          IF (E = "D") OR (E = "E") THEN Read(S, ch);
            IF ch = "-" THEN negE := TRUE; Read(S, ch)
            ELSE negE := FALSE;
              IF ch = "+" THEN Read(S, ch) END
            END;
            WHILE ("0" <= ch) & (ch <= "9") DO e := e*10 + ORD(ch) - ORD("0"); Read(S, ch) END;
            IF negE THEN e := - e END
          END;
          y := k3*Reals.Ten(-32) + k2*Reals.Ten(-24); y := y + k1*Reals.Ten(-16);
          IF ABS(e+h) < 308 THEN y := (y + k*Reals.Ten(-8)) / Reals.Ten(-e-h)
          ELSE y := (y + k*Reals.Ten(-8)) * Reals.Ten(h);
            IF (e <= 308-32) OR (e <= 308) & (y < MAX(LONGREAL) / Reals.Ten(e)) THEN y := y * Reals.Ten(e)
              ELSE y := MAX(LONGREAL)
            END
          END;
          IF E = "D" THEN
            IF y = MAX(LONGREAL) THEN S.class := Inval (* NaN *)
            ELSE S.class := LongReal;
              IF neg THEN S.y := - y ELSE S.y := y END;
              IF Reals.ExpoL(S.y) = 0 THEN S.y := 0 END
            END
          ELSIF MAX(REAL) < y THEN S.class:= Inval (* NaN *)
          ELSE S.class := Real;
            IF neg THEN S.x := SHORT(- y) ELSE S.x := SHORT(y) END;
            IF Reals.Expo(S.x) = 0 THEN S.x := 0 END
          END;
          (*-------- end floating-point handling BM 1993.3.10 -----------------------------------*)
          IF hex THEN S.class := Inval END
        ELSE (*decimal integer*)
          S.class := Int; k := 0;
          WHILE (j # i) & ((k < MAX(LONGINT) DIV 10) OR
            (k = MAX(LONGINT) DIV 10) & ((ORD(d[j]) - 30H) <= MAX(LONGINT) MOD 10)) DO (*JG*)
            k := k*10 + (ORD(d[j]) - 30H); INC(j)
          END;
          IF j # i THEN S.class := Inval
          ELSE
            IF neg THEN S.i := -k ELSE S.i := k END;
            IF hex THEN S.class := Inval ELSE S.class := Int END
          END
        END
      ELSE S.class := Char;
        IF neg THEN S.c := "-" ELSE S.c := ch; Read(S, ch) END
      END
    END;
    S.nextCh := ch
  END Scan;

  PROCEDURE OpenWriter* (VAR W: Writer);
  BEGIN NEW(W.buf); OpenBuf(W.buf); W.lib := Fonts.Default; W.col := Display.white; W.voff := 0; Files.Set(W.R, Files.New(""), 0)
  END OpenWriter;

  PROCEDURE SetFont* (VAR W: Writer; fnt: Objects.Library);
  BEGIN W.lib := fnt
  END SetFont;

  PROCEDURE SetColor* (VAR W: Writer; col: Display.COLOR);
  BEGIN W.col := col
  END SetColor;

  PROCEDURE SetOffset* (VAR W: Writer; voff: SHORTINT);
  BEGIN W.voff := voff
  END SetOffset;

  PROCEDURE Write* (VAR W: Writer; ch: CHAR);
    VAR p, q: Piece;
  BEGIN p := W.buf.last;
    IF ~(W.lib IS Fonts.Font) OR (W.lib # p.lib) OR (W.col # p.col) OR (W.voff # p.voff) THEN
      NEW(q);
      IF ~(W.lib IS Fonts.Font) THEN W.lib.GetObj(W.lib, ORD(ch), q.obj) END;
      q.f := Files.Base(W.R); q.off := Files.Pos(W.R); q.len := 0;
      q.lib := W.lib; q.col := W.col; q.voff:= W.voff;
      q.next := NIL; p.next := q; q.prev := p; p := q;
      W.buf.last := p
    END;
    Files.Write(W.R, ch);
    INC(p.len); INC(W.buf.len)
  END Write;

  PROCEDURE WriteLn* (VAR W: Writer);
  BEGIN Write(W, CR)
  END WriteLn;

  PROCEDURE WriteString* (VAR W: Writer; s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE s[i] >= " " DO Write(W, s[i]); INC(i) END
  END WriteString;

PROCEDURE WriteInt* (VAR W: Writer; x, n: LONGINT);
    VAR i: INTEGER; x0: LONGINT;
      a: ARRAY 10 OF CHAR;
  BEGIN i := 0;
    IF x < 0 THEN
      IF x = MIN(LONGINT) THEN WriteString(W, " -2147483648"); RETURN
      ELSE DEC(n); x0 := -x
      END
    ELSE x0 := x
    END;
    REPEAT
      a[i] := CHR(x0 MOD 10 + 30H); x0 := x0 DIV 10; INC(i)
    UNTIL x0 = 0;
    WHILE n > i DO Write(W, " "); DEC(n) END;
    IF x < 0 THEN Write(W, "-") END;
    REPEAT DEC(i); Write(W, a[i]) UNTIL i = 0
  END WriteInt;

  PROCEDURE WriteSet*(VAR W : Writer; s : SET);
    VAR i, j: INTEGER; notfirst: BOOLEAN;
  BEGIN i := 0; notfirst := FALSE; Write(W, "{");
    WHILE i <= MAX(SET) DO
      IF i IN s THEN
        IF notfirst THEN WriteString(W, ", ")
        ELSE notfirst := TRUE
        END ;
        j := i; WriteInt(W, i, 1); INC(i);
        WHILE (i <= MAX(SET)) & (i IN s) DO INC(i) END ;
        IF i-1 > j THEN
          IF i-2 = j THEN WriteString(W, ", ") ELSE WriteString(W, "..") END ;
          WriteInt(W, i-1, 1)
        END
      END ;
      INC(i)
    END ;
    Write(W, "}")
  END WriteSet;
  
PROCEDURE WriteHex* (VAR W: Writer; x: LONGINT);
    VAR i: INTEGER; y: LONGINT;
      a: ARRAY 10 OF CHAR;
  BEGIN i := 0; Write(W, " ");
    REPEAT y := x MOD 10H;
      IF y < 10 THEN a[i] := CHR(y + 30H) ELSE a[i] := CHR(y + 37H) END;
      x := x DIV 10H; INC(i)
    UNTIL i = 8;
    REPEAT DEC(i); Write(W, a[i]) UNTIL i = 0
  END WriteHex;

PROCEDURE WriteRealHex* (VAR W: Writer; x: REAL);
BEGIN (* BM 1991.12.25 *) WriteHex(W, Reals.Int(x))
END WriteRealHex;

PROCEDURE WriteLongRealHex* (VAR W: Writer; x: LONGREAL);
  VAR h, l: LONGINT; (* BM 1991.12.25 *)
BEGIN Reals.IntL(x, h, l); WriteHex(W, h); WriteHex(W, l)
END WriteLongRealHex;

PROCEDURE WriteReal* (VAR W: Writer; x: REAL; n: LONGINT);
  (* BM 1993.4.22. Do not simplify rounding! *)
  VAR e : INTEGER; h, i: LONGINT; y: LONGREAL; z: REAL; d: ARRAY 8 OF CHAR;
BEGIN
  e:= Reals.Expo(x);
  IF e = 255 THEN
    WHILE n > 8 DO Write(W, " "); DEC(n) END;
    WriteString(W, "     NaN")
  ELSE
    IF n <= 8 THEN n := 1 ELSE DEC(n, 7) END;
    REPEAT Write(W, " "); DEC(n) UNTIL n <= 7; (* 0 <= n <= 7 fraction digits *)
    IF (e # 0) & (x < 0) THEN Write(W, "-"); x := - x ELSE Write(W, " ") END;
    IF e = 0 THEN h := 0 (* no denormals *)
    ELSE e := (e - 127) * 301 DIV 1000; (* ln(2)/ln(10) = 0.301029996 *)
      IF e < 38 THEN z := Reals.Ten(e+1);
        IF x >= z THEN y := LONG(x)/LONG(z); INC(e) ELSE y := x * Reals.Ten(-e) END
      ELSE y := x * Reals.Ten(-38) END;
      IF y >= 10 THEN y := y * Reals.Ten(-1) + 0.5D0 / Reals.Ten(SHORT(n)); INC(e)
      ELSE y := y + 0.5D0 / Reals.Ten(SHORT(n));
        IF y >= 10 THEN y := y * Reals.Ten(-1); INC(e) END
      END;
      y := y * Reals.Ten(7); h := ENTIER(y)
    END;
    i := 7;
    WHILE i >= 0 DO d[i] := CHR(h MOD 10 + ORD("0")); h := h DIV 10; DEC(i) END;
    Write(W, d[0]); Write(W, "."); i := 1; WHILE i <= n DO Write(W, d[i]); INC(i) END;
    IF e < 0 THEN WriteString(W, "E-"); e := - e ELSE WriteString(W, "E+") END;
    Write(W, CHR(e DIV 10 + ORD("0")));
    Write(W, CHR(e MOD 10 + ORD("0")))
  END
END WriteReal;

PROCEDURE WriteRealFix* (VAR W: Writer; x: REAL; n, f, E: LONGINT);
  (* BM 1993.4.22. Do not simplify rounding ! / JG formatting adjusted *)
  VAR e : INTEGER; h, i: LONGINT; r, y: LONGREAL; z: REAL; s: CHAR; d: ARRAY 8 OF CHAR;
BEGIN
  e := Reals.Expo(x);
  IF (e = 255) OR (ABS(E) > 38) THEN
    WHILE n > 8 DO Write(W, " "); DEC(n) END;
    WriteString(W, "     NaN")
  ELSE
    IF E = 0 THEN DEC(n, 2) ELSE DEC(n, 6) END;
    IF f < 0 THEN f := 0 END;
    IF n < f + 2 THEN n := f + 2 END;
    DEC(n, f);
    IF (e # 0) & (x < 0) THEN s:= "-"; x:= - x ELSE s:= " " END;
    IF e = 0 THEN h := 0; DEC(e, SHORT(E-1)) (* no denormals *)
    ELSE
      e := (e - 127) * 301 DIV 1000; (* ln(2)/ln(10) = 0.301029996 *)
      IF e < 38 THEN z := Reals.Ten(e+1);
        IF x >= z THEN y := LONG(x)/LONG(z); INC(e) ELSE y := x * Reals.Ten(-e) END
      ELSE y := x * Reals.Ten(-38) END;
      DEC(e, SHORT(E-1)); i := -(e+f);
      IF i <= 0 THEN r := 5 * Reals.Ten(SHORT(i)) ELSE r := 0 END;
      IF y >= 10 THEN y := y * Reals.Ten(-1) + r; INC(e)
      ELSE y := y + r;
        IF y >= 10 THEN y := y * Reals.Ten(-1); INC(e) END
      END;
      y := y * Reals.Ten(7); h := ENTIER(y)
    END;
    i := 7;
    WHILE i >= 0 DO d[i] := CHR(h MOD 10 + ORD("0")); h := h DIV 10; DEC(i) END;
    IF n <= e THEN n := e + 1 END;
    IF e > 0 THEN WHILE n > e DO Write(W, " "); DEC(n) END;
      Write(W, s); e := 0;
      WHILE n > 0 DO DEC(n);
        IF e < 8 THEN Write(W, d[e]); INC(e) ELSE Write(W, "0") END
      END;
      Write(W, ".")
    ELSE
      WHILE n > 1 DO Write(W, " "); DEC(n) END;
      Write(W, s); Write(W, "0"); Write(W, ".");
      WHILE (0 < f) & (e < 0) DO Write(W, "0"); DEC(f); INC(e) END
    END;
    WHILE f > 0 DO DEC(f);
      IF e < 8 THEN Write(W, d[e]); INC(e) ELSE Write(W, "0") END
    END;
    IF E # 0 THEN
      IF E < 0 THEN WriteString(W, "E-"); E := - E
        ELSE WriteString(W, "E+")
      END;
      Write(W, CHR(E DIV 10 + ORD("0"))); Write(W, CHR(E MOD 10 + ORD("0")))
    END
  END
END WriteRealFix;

PROCEDURE WriteLongReal* (VAR W: Writer; x: LONGREAL; n: LONGINT);
  (* BM 1993.4.22. Do not simplify rounding! *)
  VAR e, h, l, i: LONGINT; z: LONGREAL; d: ARRAY 16 OF CHAR;
BEGIN
  e:= Reals.ExpoL(x);
  IF e = 2047 THEN
    WHILE n > 9 DO Write(W, " "); DEC(n) END;
    WriteString(W, "      NaN")
  ELSE
    IF n <= 9 THEN n:= 1 ELSE DEC(n, 8) END;
    REPEAT Write(W, " "); DEC(n) UNTIL n <= 15; (* 0 <= n <= 15 fraction digits *)
    IF (e # 0) & (x < 0) THEN Write(W, "-"); x:= - x ELSE Write(W, " ") END;
    IF e = 0 THEN h:= 0; l:= 0 (* no denormals *)
    ELSE e:= (e - 1023) * 301029 DIV 1000000; (* ln(2)/ln(10) = 0.301029996 *)
      z:= Reals.TenL(SHORT(e+1));
      IF x >= z THEN x:= x/z; INC(e) ELSE x:= x * Reals.Ten(SHORT(-e)) END;
      IF x >= 10 THEN x:= x * Reals.TenL(-1) + 0.5D0 / Reals.TenL(SHORT(n)); INC(e)
      ELSE x:= x + 0.5D0 / Reals.Ten(SHORT(n));
        IF x >= 10 THEN x:= x * Reals.Ten(-1); INC(e) END
      END;
      x:= x * Reals.Ten(7); h:= ENTIER(x); x:= (x-h) * Reals.Ten(8); l:= ENTIER(x)
    END;
    i:= 15; WHILE i > 7 DO d[i]:= CHR(l MOD 10 + ORD("0")); l:= l DIV 10; DEC(i) END;
    WHILE i >= 0 DO d[i]:= CHR(h MOD 10 + ORD("0")); h:= h DIV 10; DEC(i) END;
    Write(W, d[0]); Write(W, "."); i:= 1; WHILE i <= n DO Write(W, d[i]); INC(i) END;
    IF e < 0 THEN WriteString(W, "D-"); e:= - e ELSE WriteString(W, "D+") END;
    Write(W, CHR(e DIV 100 + ORD("0"))); e:= e MOD 100;
    Write(W, CHR(e DIV 10 + ORD("0"))); Write(W, CHR(e MOD 10 + ORD("0")))
  END
END WriteLongReal;

PROCEDURE WriteLongRealFix* (VAR W: Writer; x: LONGREAL; n, f, D: LONGINT);
  (* BM 1993.4.22. Do not simplify rounding! / JG formatting adjusted *)
  VAR e, h, l, i: LONGINT; r, z: LONGREAL; d: ARRAY 16 OF CHAR; s: CHAR;
BEGIN
  e := Reals.ExpoL(x);
  IF (e = 2047) OR (ABS(D) > 308) THEN
    WHILE n > 9 DO Write(W, " "); DEC(n) END;
    WriteString(W, "      NaN")
  ELSE
    IF D = 0 THEN DEC(n, 2) ELSE DEC(n, 7) END;
    IF n < 2 THEN n := 2 END;
    IF f < 0 THEN f := 0 END;
    IF n < f + 2 THEN n := f + 2 END;
    DEC(n, f);
    IF (e # 0) & (x < 0) THEN s := "-"; x := - x ELSE s := " " END;
    IF e = 0 THEN h := 0; l := 0; DEC(e, D-1) (* no denormals *)
    ELSE
      e := (e - 1023) * 301029 DIV 1000000; (* ln(2)/ln(10) = 0.301029996 *)
      z := Reals.Ten(SHORT(e+1));
      IF x >= z THEN x := x/z; INC(e) ELSE x:= x * Reals.Ten(SHORT(-e)) END;
      DEC(e, D-1); i := -(e+f);
      IF i <= 0 THEN r := 5 * Reals.Ten(SHORT(i)) ELSE r := 0 END;
      IF x >= 10 THEN x := x * Reals.Ten(-1) + r; INC(e)
      ELSE x := x + r;
        IF x >= 10 THEN x := x * Reals.Ten(-1); INC(e) END
      END;
      x := x * Reals.Ten(7); h:= ENTIER(x); x := (x-h) * Reals.Ten(8); l := ENTIER(x)
    END;
    i := 15;
    WHILE i > 7 DO d[i] := CHR(l MOD 10 + ORD("0")); l := l DIV 10; DEC(i) END;
    WHILE i >= 0 DO d[i] := CHR(h MOD 10 + ORD("0")); h := h DIV 10; DEC(i) END;
    IF n <= e THEN n := e + 1 END;
    IF e > 0 THEN WHILE n > e DO Write(W, " "); DEC(n) END;
      Write(W, s); e:= 0;
      WHILE n > 0 DO DEC(n);
        IF e < 16 THEN Write(W, d[e]); INC(e) ELSE Write(W, "0") END
      END;
      Write(W, ".")
    ELSE
      WHILE n > 1 DO Write(W, " "); DEC(n) END;
      Write(W, s); Write(W, "0"); Write(W, ".");
      WHILE (0 < f) & (e < 0) DO Write(W, "0"); DEC(f); INC(e) END
    END;
    WHILE f > 0 DO DEC(f);
      IF e < 16 THEN Write(W, d[e]); INC(e) ELSE Write(W, "0") END
    END;
    IF D # 0 THEN
      IF D < 0 THEN WriteString(W, "D-"); D := - D
        ELSE WriteString(W, "D+")
      END;
      Write(W, CHR(D DIV 100 + ORD("0"))); D := D MOD 100;
      Write(W, CHR(D DIV 10 + ORD("0"))); Write(W, CHR(D MOD 10 + ORD("0")))
    END
  END
END WriteLongRealFix;

  PROCEDURE WriteDate* (VAR W: Writer; t, d: LONGINT);

  PROCEDURE WritePair(ch: CHAR; x: LONGINT);
  BEGIN Write(W, ch);
    Write(W, CHR(x DIV 10 + 30H)); Write(W, CHR(x MOD 10 + 30H))
  END WritePair;

  BEGIN
    WritePair(" ", d MOD 32); WritePair(".", d DIV 32 MOD 16); WritePair(".", d DIV 512 MOD 128);
    WritePair(" ", t DIV 4096 MOD 32); WritePair(":", t DIV 64 MOD 64); WritePair(":", t MOD 64)
  END WriteDate;

BEGIN
  TextBlockId := 0F0X; DocBlockId := 0F7X; NoSpex := 0X; TextSpex := 1X;
  UndefColor := Display.black;
  H := Handle; Wfile := Files.New(""); Files.Set(R, Wfile, 0); Files.Write(R, 0X);
  NEW(DelBuf); OpenBuf(DelBuf)
END Texts.

