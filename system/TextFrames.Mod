MODULE TextFrames; (*JG 16.10.94, color version*)

  IMPORT  Input, Modules, Objects, Display, Viewers, Fonts, Texts, Oberon;

  CONST CR = 0DX;
    replace = Display.replace; paint = Display.paint; invert = Display.invert;
    extend = Display.extend; reduce = Display.reduce;

  TYPE
    Line = POINTER TO LineDesc;

    LineDesc = RECORD
      len: LONGINT;
      wid: INTEGER;
      eot: BOOLEAN;
      next: Line
    END;

    Location* = RECORD
        org*, pos*: LONGINT;
        dx*, x*, y*: INTEGER;
        lin: Line
    END;

    Frame* = POINTER TO FrameDesc;

    FrameDesc* = RECORD (Display.FrameDesc)
        text*: Texts.Text;
        org*: LONGINT;
        col*: Display.COLOR;
        lsp*: INTEGER;
        left*, right*, top*, bot*: INTEGER;
        markH*: INTEGER;
        time*: LONGINT;
        mark*, car*, sel*: INTEGER;
        carloc*: Location;
        selbeg*, selend*: Location;
        trailer: Line
    END;

    (*mark < 0: arrow mark
        mark = 0: no mark
        mark > 0: position mark*)

  VAR
    menuH*, barW*, left*, right*, top*, bot*, lsp*: INTEGER; (*standard sizes*)
    asr, dsr, selH, markW, eolW, boxW: INTEGER;
    par: Oberon.ParList; ch: CHAR;
    W, KW: Texts.Writer; (*keyboard writer*)
    box: Fonts.Char;
    BoxPat: ARRAY 12 OF SET;
    MarkColor, BarColor, MenuBG, TextBG, FullColor : Display.COLOR;

  PROCEDURE Min (i, j: INTEGER): INTEGER;
  BEGIN IF i >= j THEN RETURN j ELSE RETURN i END
  END Min;

  PROCEDURE Max (i, j: LONGINT): LONGINT;
  BEGIN IF i >= j THEN RETURN i ELSE RETURN j END
  END Max;

  (*------------------display support------------------------*)

  PROCEDURE ReplConst (col: Display.COLOR; F: Frame; X, Y, W, H: INTEGER; mode: INTEGER);
  BEGIN
    IF X + W <= F.X + F.W THEN Display.ReplConst(col, X, Y, W, H, SHORT(mode))
    ELSIF X < F.X + F.W THEN Display.ReplConst(col, X, Y, F.X + F.W - X, H, SHORT(mode))
    END
  END ReplConst;

  PROCEDURE UpdateMark (F: Frame);
    VAR oldH: INTEGER;
  BEGIN
    oldH := F.markH; F.markH := SHORT(F.org * F.H DIV (F.text.len + 1));
    IF (F.mark > 0) & (F.left >= barW) & (F.markH # oldH) THEN
      Display.ReplConst(F.col, F.X, F.Y + F.H - 1 - oldH, markW, 1, replace);
      Display.ReplConst(MarkColor, F.X, F.Y + F.H - 1 - F.markH, markW, 1, replace)
    END
  END UpdateMark;

  PROCEDURE Width (VAR R: Texts.Reader; len: LONGINT): INTEGER;
    VAR  pos: LONGINT; ox: INTEGER; obj: Objects.Object;
  BEGIN pos := 0; ox := 0;
    WHILE pos # len DO
      R.lib.GetObj(R.lib, ORD(ch), obj);
      IF ~(obj IS Fonts.Char) THEN obj := box END;
      ox := ox + obj(Fonts.Char).dx; INC(pos); Texts.Read(R, ch)
    END;
    RETURN ox
  END Width;

  PROCEDURE DisplayLine (F: Frame; L: Line; VAR R: Texts.Reader; X, Y: INTEGER; len: LONGINT);
    VAR NX: INTEGER; obj: Objects.Object;
  BEGIN NX := F.X + F.W;
    WHILE (ch # CR) & (R.lib # NIL) DO
      IF R.lib IS Fonts.Font THEN
        R.lib.GetObj(R.lib, ORD(ch), obj);
      ELSE obj := box
      END;
      WITH obj: Fonts.Char DO
        IF X + obj.x + obj.w <= NX THEN
          Display.CopyPattern(R.col, obj.pat, X + obj.x, Y + obj.y, paint)
        END;
        X := X + obj.dx
      END;
      INC(len); Texts.Read(R, ch)
    END;
    L.len := len + 1; L.wid := X + eolW - (F.X + F.left);
    L.eot := R.eot; Texts.Read(R, ch);
  END DisplayLine;

  PROCEDURE Validate (T: Texts.Text; VAR org: LONGINT);
    VAR R: Texts.Reader; pos: LONGINT;
  BEGIN
    IF org > T.len THEN org := T.len
    ELSIF org > 0 THEN Texts.OpenReader(R, T, org - 1); Texts.Read(R, ch);
      IF ch # CR THEN
        pos := Max(org - 100, 0); Texts.OpenReader(R, T, pos);
        REPEAT Texts.Read(R, ch); INC(pos) UNTIL (pos = org) OR (ch = CR);
        org := pos
      END
    ELSE org := 0
    END
  END Validate;

  PROCEDURE Mark* (F: Frame; mark: INTEGER);
  BEGIN
    IF (mark >= 0) & (F.mark < 0) & (F.H >= 16) THEN
      Display.CopyPattern(F.col, Display.downArrow, F.X, F.Y, paint)
    ELSIF (mark <= 0) & (F.mark > 0) & (F.H > 0) & (F.left >= barW) THEN
      Display.ReplConst(F.col, F.X, F.Y + F.H - 1 - F.markH, markW, 1, replace)
    END;
    IF (mark > 0) & (F.H > 0) & (F.left >= barW) & (F.mark <= 0) THEN
      Display.ReplConst(MarkColor, F.X, F.Y + F.H - 1 - F.markH, markW, 1, replace)
    ELSIF (mark < 0) & (F.H >= 16) & (F.mark >= 0) THEN
      Display.CopyPattern(MarkColor, Display.downArrow, F.X, F.Y, paint)
    END;
    F.mark := mark
  END Mark;

  PROCEDURE Restore* (F: Frame);
    VAR R: Texts.Reader; L: Line; curY, botY: INTEGER;
  BEGIN (*F.mark = 0*)
    Display.ReplConst(F.col, F.X, F.Y, F.W, F.H, replace);
    IF F.left >= barW THEN
      Display.ReplConst(BarColor, F.X + barW - 1, F.Y, 1, F.H, replace)
    END;
    Validate(F.text, F.org);
    botY := F.Y + F.bot + dsr;
    Texts.OpenReader(R, F.text, F.org); Texts.Read(R, ch);
    L := F.trailer; curY := F.Y + F.H - F.top - asr;
    WHILE ~L.eot & (curY >= botY) DO
      NEW(L.next); L := L.next;
      DisplayLine(F, L, R, F.X + F.left, curY, 0);
      curY := curY - lsp
    END;
    L.next := F.trailer;
    F.markH := SHORT(F.org * F.H DIV (F.text.len + 1))
  END Restore;

  PROCEDURE Suspend* (F: Frame);
  BEGIN (*F.mark = 0*)
    F.trailer.next := F.trailer
  END Suspend;

  PROCEDURE Extend* (F: Frame; newY: INTEGER);
    VAR R: Texts.Reader; L: Line;
    org: LONGINT; curY, botY: INTEGER;
  BEGIN (*F.mark = 0*)
    Display.ReplConst(F.col, F.X, newY, F.W, F.Y - newY, replace);
    IF F.left >= barW THEN
      Display.ReplConst(BarColor, F.X + barW - 1, newY, 1, F.Y - newY, replace)
    END;
    F.H := F.H + F.Y - newY; F.Y := newY;
    IF F.trailer.next = F.trailer THEN Validate(F.text, F.org) END;
    L := F.trailer; org := F.org; curY := F.Y + F.H - F.top - asr;
    WHILE L.next # F.trailer DO
      L := L.next; org := org + L.len; curY := curY - lsp
    END;
    botY := F.Y + F.bot + dsr;
    Texts.OpenReader(R, F.text, org); Texts.Read(R, ch);
    WHILE ~L.eot & (curY >= botY) DO
      NEW(L.next); L := L.next;
      DisplayLine(F, L, R, F.X + F.left, curY, 0);
      curY := curY - lsp
    END;
    L.next := F.trailer;
    F.markH := SHORT(F.org * F.H DIV (F.text.len + 1));
  END Extend;

  PROCEDURE Reduce* (F: Frame; newY: INTEGER);
    VAR L: Line; curY, botY: INTEGER;
  BEGIN (*F.mark = 0*)
    F.H := F.H + F.Y - newY; F.Y := newY;
    botY := F.Y + F.bot + dsr;
    L := F.trailer; curY := F.Y + F.H - F.top - asr;
    WHILE (L.next # F.trailer) & (curY >= botY) DO
      L := L.next; curY := curY - lsp
    END;
    L.next := F.trailer;
    IF curY + asr > F.Y THEN
      Display.ReplConst(F.col, F.X + F.left, F.Y, F.W - F.left, curY + asr - F.Y, replace)
    END;
    F.markH := SHORT(F.org * F.H DIV (F.text.len + 1));
    Mark(F, 1)
  END Reduce;

  PROCEDURE Show* (F: Frame; pos: LONGINT);
    VAR R: Texts.Reader; L: Line;
      org: LONGINT; curY, botY, Y0: INTEGER;
  BEGIN
    IF F.trailer.next # F.trailer THEN Validate(F.text, pos);
      IF pos < F.org THEN Mark(F, 0);
        Display.ReplConst(F.col, F.X + F.left, F.Y, F.W - F.left, F.H, replace);
        botY := F.Y; F.Y := F.Y + F.H; F.H := 0;
        F.org := pos; F.trailer.next := F.trailer; Extend(F, botY);
        Mark(F, 1)
      ELSIF pos > F.org THEN
        org := F.org; L := F.trailer.next; curY := F.Y + F.H - F.top - asr;
        WHILE (L.next # F.trailer) & (org # pos) DO
          org := org + L.len; L := L.next; curY := curY - lsp;
        END;
        IF org = pos THEN
          F.org := org; F.trailer.next := L; Y0 := curY;
          WHILE L.next # F.trailer DO
            org := org + L.len; L := L.next; curY := curY - lsp
          END;
          Display.CopyBlock
            (F.X + F.left, curY - dsr, F.W - F.left, Y0 + asr - (curY - dsr),
            F.X + F.left, curY - dsr + F.Y + F.H - F.top - asr - Y0, replace);
          curY := curY + F.Y + F.H - F.top - asr - Y0;
          Display.ReplConst(F.col, F.X + F.left, F.Y, F.W - F.left, curY - dsr - F.Y, replace);
          botY := F.Y + F.bot + dsr;
          org := org + L.len; curY := curY - lsp;
          Texts.OpenReader(R, F.text, org); Texts.Read(R, ch);
          WHILE ~L.eot & (curY >= botY) DO
            NEW(L.next); L := L.next;
            DisplayLine(F, L, R, F.X + F.left, curY, 0);
            curY := curY - lsp
          END;
          L.next := F.trailer;
          UpdateMark(F)
        ELSE Mark(F, 0);
          Display.ReplConst(F.col, F.X + F.left, F.Y, F.W - F.left, F.H, replace);
          botY := F.Y; F.Y := F.Y + F.H; F.H := 0;
          F.org := pos; F.trailer.next := F.trailer; Extend(F, botY);
          Mark(F, 1)
        END
      END
    END
  END Show;

  PROCEDURE LocateLine (F: Frame; y: INTEGER; VAR loc: Location);
    VAR L: Line; org: LONGINT; cury: INTEGER;
  BEGIN
    org := F.org; L := F.trailer.next; cury := F.H - F.top - asr;
    WHILE (L.next # F.trailer) & (cury > y + dsr) DO
      org := org + L.len; L := L.next; cury := cury - lsp
    END;
    loc.org := org; loc.lin := L; loc.y := cury
  END LocateLine;

  PROCEDURE LocateString (F: Frame; x, y: INTEGER; VAR loc: Location);
    VAR R: Texts.Reader;
      bpos, pos, lim: LONGINT;
      bx, ex, ox: INTEGER;
      obj: Objects.Object;
  BEGIN
    LocateLine(F, y, loc);
    lim := loc.org + loc.lin.len - 1;
    bpos := loc.org; bx := F.left;
    pos := loc.org; ox := F.left;
    Texts.OpenReader(R, F.text, loc.org); Texts.Read(R, ch);
    LOOP
      LOOP (*scan string*)
        IF (pos = lim) OR (ch <= " ") THEN EXIT END;
        R.lib.GetObj(R.lib, ORD(ch), obj);
        IF ~(obj IS Fonts.Char) THEN obj := box END;
        INC(pos); ox := ox + obj(Fonts.Char).dx; Texts.Read(R, ch)
      END;
      ex := ox;
      LOOP (*scan gap*)
        IF (pos = lim) OR (ch > " ") THEN EXIT END;
        R.lib.GetObj(R.lib, ORD(ch), obj);
        IF ~(obj IS Fonts.Char) THEN obj := box END;
        INC(pos); ox := ox + obj(Fonts.Char).dx; Texts.Read(R, ch)
      END;
      IF (pos = lim) OR (ox > x) THEN EXIT END;
      R.lib.GetObj(R.lib, ORD(ch), obj);
      IF ~(obj IS Fonts.Char) THEN obj := box END;
      bpos := pos; bx := ox;
      INC(pos); ox := ox + obj(Fonts.Char).dx; Texts.Read(R, ch)
    END;
    loc.pos := bpos; loc.dx := ex - bx; loc.x := bx
  END LocateString;

  PROCEDURE LocateChar (F: Frame; x, y: INTEGER; VAR loc: Location);
    VAR R: Texts.Reader;
      pos, lim: LONGINT;
      ox, dx: INTEGER;
      obj: Objects.Object;
  BEGIN
    LocateLine(F, y, loc);
    lim := loc.org + loc.lin.len - 1;
    pos := loc.org; ox := F.left;
    Texts.OpenReader(R, F.text, loc.org); Texts.Read(R, ch);
    LOOP
      IF pos = lim THEN dx := eolW; EXIT END;
      R.lib.GetObj(R.lib, ORD(ch), obj);
      IF ~(obj IS Fonts.Char) THEN obj := box END;
      dx := obj(Fonts.Char).dx;
      IF ox + dx > x THEN EXIT END;
      INC(pos); ox := ox + dx; Texts.Read(R, ch)
    END;
    loc.pos := pos; loc.dx := dx; loc.x := ox
  END LocateChar;

  PROCEDURE LocatePos (F: Frame; pos: LONGINT; VAR loc: Location);
    VAR R: Texts.Reader; L: Line; org: LONGINT; cury: INTEGER;
  BEGIN
    org := F.org; L := F.trailer.next; cury := F.H - F.top - asr;
    WHILE (L.next # F.trailer) & (pos >= org + L.len) DO
      org := org + L.len; L := L.next; cury := cury - lsp
    END;
    IF pos < org THEN pos := org
      ELSIF pos >= org + L.len THEN pos := org + L.len - 1
    END;
    Texts.OpenReader(R, F.text, org); Texts.Read(R, ch);
    loc.org := org; loc.pos := pos; loc.lin := L;
    loc.x := F.left + Width(R, pos - org); loc.y := cury
  END LocatePos;

  PROCEDURE Pos* (F: Frame; X, Y: INTEGER): LONGINT;
    VAR loc: Location;
  BEGIN LocateChar(F, X - F.X, Y - F.Y, loc);
    RETURN loc.pos
  END Pos;

  PROCEDURE FlipCaret (F: Frame);
  BEGIN
    IF F.carloc.x < F.W THEN
      IF (F.carloc.y >= 10) & (F.carloc.x + 12 < F.W) THEN
        Display.CopyPattern(FullColor, Display.hook, F.X + F.carloc.x, F.Y + F.carloc.y - 10, invert)
      END
    END
  END FlipCaret;

  PROCEDURE SetCaret* (F: Frame; pos: LONGINT);
  BEGIN
    IF F.car # 0 THEN FlipCaret(F); F.car := 0 END;
    LocatePos(F, pos, F.carloc);
    IF F.carloc.pos = pos THEN FlipCaret(F); F.car := 1
    ELSE Show(F, pos - 100); LocatePos(F, pos, F.carloc);
      IF F.carloc.pos = pos THEN FlipCaret(F); F.car := 1 END
    END
  END SetCaret;

  PROCEDURE TrackCaret* (F: Frame; X, Y: INTEGER; VAR keysum: SET);
    VAR loc: Location; keys: SET;
  BEGIN
    IF F.trailer.next # F.trailer THEN
      LocateChar(F, X - F.X, Y - F.Y, F.carloc);
      FlipCaret(F);
      keysum := {};
      REPEAT
        Input.Mouse(keys, X, Y);
        keysum := keysum + keys;
        Oberon.DrawCursor(Oberon.Mouse, Oberon.Mouse.marker, X, Y);
        LocateChar(F, X - F.X, Y - F.Y, loc);
        IF loc.pos # F.carloc.pos THEN FlipCaret(F); F.carloc := loc; FlipCaret(F) END
      UNTIL keys = {};
      F.car := 1
    END
  END TrackCaret;

  PROCEDURE RemoveCaret* (F: Frame);
  BEGIN IF F.car # 0 THEN FlipCaret(F); F.car := 0 END
  END RemoveCaret;

  PROCEDURE FlipSelection (F: Frame; VAR beg, end: Location);
    VAR L: Line; Y: INTEGER;
  BEGIN
    L := beg.lin; Y := F.Y + beg.y - 2;
    IF L = end.lin THEN
      ReplConst(FullColor, F, F.X + beg.x, Y, end.x - beg.x, selH, invert)
    ELSE
      ReplConst(FullColor, F, F.X + beg.x, Y, F.left + L.wid - beg.x, selH, invert);
      LOOP
        L := L.next; Y := Y - lsp;
        IF L = end.lin THEN EXIT END;
        ReplConst(FullColor, F, F.X + F.left, Y, L.wid, selH, invert)
      END;
      ReplConst(FullColor, F, F.X + F.left, Y, end.x - F.left, selH, invert)
    END
  END FlipSelection;

  PROCEDURE SetSelection* (F: Frame; beg, end: LONGINT);
  BEGIN
    IF end <= beg THEN end := beg + 1 END;
    IF F.sel # 0 THEN FlipSelection(F, F.selbeg, F.selend) END;
    LocatePos(F, beg, F.selbeg);
    IF F.selbeg.pos # beg THEN Show(F, beg); LocatePos(F, beg, F.selbeg) END;
    LocatePos(F, end, F.selend);
    FlipSelection(F, F.selbeg, F.selend); F.time := Input.Time(); F.sel := 1
  END SetSelection;

  PROCEDURE TrackSelection* (F: Frame; X, Y: INTEGER; VAR keysum: SET);
    VAR loc: Location; keys: SET;
  BEGIN
      IF F.trailer.next # F.trailer THEN
      IF F.sel # 0 THEN FlipSelection(F, F.selbeg, F.selend) END;
      LocateChar(F, X - F.X, Y - F.Y, loc);
      IF (F.sel # 0) & (loc.pos = F.selbeg.pos) & (F.selend.pos = F.selbeg.pos + 1) THEN
        LocateChar(F, F.left, Y - F.Y, F.selbeg)
      ELSE F.selbeg := loc
      END;
      INC(loc.pos); loc.x := loc.x + loc.dx; F.selend := loc;
      FlipSelection(F, F.selbeg, F.selend);
        keysum := {};
      REPEAT
          Input.Mouse(keys, X, Y);
        keysum := keysum + keys;
        Oberon.DrawCursor(Oberon.Mouse, Oberon.Mouse.marker, X, Y);
        LocateChar(F, X - F.X, Y - F.Y, loc);
        IF loc.pos < F.selbeg.pos THEN loc := F.selbeg END;
        INC(loc.pos); loc.x := loc.x + loc.dx;
        IF loc.pos < F.selend.pos THEN FlipSelection(F, loc, F.selend); F.selend := loc
          ELSIF loc.pos > F.selend.pos THEN FlipSelection(F, F.selend, loc); F.selend := loc
        END
      UNTIL keys = {};
        F.time := Input.Time(); F.sel := 1
      END
  END TrackSelection;

  PROCEDURE RemoveSelection* (F: Frame);
  BEGIN IF F.sel # 0 THEN FlipSelection(F, F.selbeg, F.selend); F.sel := 0 END
  END RemoveSelection;

  PROCEDURE TrackLine* (F: Frame; X, Y: INTEGER; VAR org: LONGINT; VAR keysum: SET);
    VAR old, new: Location; keys: SET;
  BEGIN
        IF F.trailer.next # F.trailer THEN
        LocateLine(F, Y - F.Y, old);
        ReplConst(FullColor, F, F.X + F.left, F.Y + old.y - dsr, old.lin.wid, 2, invert);
          keysum := {};
        REPEAT
          Input.Mouse(keys, X, Y);
          keysum := keysum + keys;
            Oberon.DrawCursor(Oberon.Mouse, Oberon.Mouse.marker, X, Y);
          LocateLine(F, Y - F.Y, new);
          IF new.org # old.org THEN
            ReplConst(FullColor, F, F.X + F.left, F.Y + old.y - dsr, old.lin.wid, 2, invert);
            ReplConst(FullColor, F, F.X + F.left, F.Y + new.y - dsr, new.lin.wid, 2, invert);
            old := new
          END
        UNTIL keys = {};
        ReplConst(FullColor, F, F.X + F.left, F.Y + new.y - dsr, new.lin.wid, 2, invert);
        org := new.org
        ELSE org := -1
        END
  END TrackLine;

  PROCEDURE TrackWord* (F: Frame; X, Y: INTEGER; VAR pos: LONGINT; VAR keysum: SET);
    VAR old, new: Location; keys: SET;
  BEGIN
        IF F.trailer.next # F.trailer THEN
        LocateString(F, X - F.X, Y - F.Y, old);
        ReplConst(FullColor, F, F.X + old.x, F.Y + old.y - dsr, old.dx, 2, invert);
          keysum := {};
          REPEAT
          Input.Mouse(keys, X, Y);
        keysum := keysum + keys;
          Oberon.DrawCursor(Oberon.Mouse, Oberon.Mouse.marker, X, Y);
          LocateString(F, X - F.X, Y - F.Y, new);
          IF new.pos # old.pos THEN
            ReplConst(FullColor, F, F.X + old.x, F.Y + old.y - dsr, old.dx, 2, invert);
            ReplConst(FullColor, F, F.X + new.x, F.Y + new.y - dsr, new.dx, 2, invert);
            old := new
          END
        UNTIL keys = {};
        ReplConst(FullColor, F, F.X + new.x, F.Y + new.y - dsr, new.dx, 2, invert);
        pos := new.pos
        ELSE pos := -1
        END
  END TrackWord;

  (*------------------message handling------------------------*)

  PROCEDURE RemoveMarks (F: Frame);
  BEGIN RemoveCaret(F); RemoveSelection(F);
  END RemoveMarks;

  PROCEDURE GetAttr* (F: Frame; VAR s: ARRAY OF CHAR);
    VAR S: Texts.Scanner;
  BEGIN Texts.OpenScanner(S, F.text, 0); Texts.Scan(S); COPY(S.s, s)
  END GetAttr;

  PROCEDURE Call* (F: Frame; pos: LONGINT; new: BOOLEAN);
    VAR S: Texts.Scanner; res: INTEGER;
  BEGIN
    Texts.OpenScanner(S, F.text, pos); Texts.Scan(S);
    IF (S.line = 0) & (S.class = Texts.Name) THEN
      par.vwr := Viewers.This(F.X, F.Y);
      par.frame := F; par.text := F.text; par.pos := pos + S.len;
      Oberon.Call(S.s, par, new, res);
      IF res # Modules.done THEN
        Texts.WriteString(W, "Call error: "); Texts.WriteString(W, S.s);
        IF res = Modules.fileNotFound THEN Texts.WriteString(W, " module not found")
        ELSIF res = Modules.notAnObj THEN Texts.WriteString(W, " not an obj-file")
        ELSIF res = Modules.fpMismatch THEN Texts.WriteString(W, " imports ");
          Texts.WriteString(W, Modules.imported^); Texts.WriteString(W, " with bad key (");
          Texts.WriteString(W, Modules.object^);
          Texts.WriteString(W, ")");
        ELSIF res = Modules.corruptObj THEN Texts.WriteString(W, " corrupted obj file")
        ELSIF res = Modules.cmdNotFound THEN Texts.WriteString(W, " command not found")
        ELSIF res = Modules.modNotFound THEN Texts.WriteString(W, " too many imports")
        ELSIF res = Modules.notEnoughSpace THEN Texts.WriteString(W, " not enough space")
        ELSIF res = Modules.refCntNotZero THEN Texts.WriteString(W, " reference count not zero");
        ELSIF res = Modules.objNotFound THEN Texts.WriteString(W, " object file not found");
        ELSIF res = Modules.cyclicImport THEN Texts.WriteString(W, " cyclic import");
        ELSIF res = Modules.objVersionMismatch THEN Texts.WriteString(W, " version mismatch");
        ELSIF res = Modules.helperModNotFound THEN Texts.WriteString(W, " helper module not found");
        END;
        Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
      END
    END
  END Call;

  PROCEDURE Write* (F: Frame; ch: CHAR; lib: Objects.Library; col : Display.COLOR; voff: SHORTINT);
  BEGIN (*F.car # 0*)
    IF ch = 7FX THEN
      IF F.carloc.pos > F.org THEN
        Texts.Delete(F.text, F.carloc.pos - 1, F.carloc.pos);
        SetCaret(F, F.carloc.pos - 1)
      END
    ELSE
      KW.lib := lib; KW.col := col; KW.voff := voff; Texts.Write(KW, ch);
      Texts.Insert(F.text, F.carloc.pos, KW.buf);
      SetCaret(F, F.carloc.pos + 1)
    END
  END Write;

  PROCEDURE Defocus* (F: Frame);
  BEGIN RemoveCaret(F)
  END Defocus;

  PROCEDURE Neutralize* (F: Frame);
  BEGIN RemoveMarks(F)
  END Neutralize;

  PROCEDURE Modify* (F: Frame; id, dY, Y, H: INTEGER);
  BEGIN
    Mark(F, 0); RemoveMarks(F);
    IF id = extend THEN
      IF dY > 0 THEN
        Display.CopyBlock(F.X, F.Y, F.W, F.H, F.X, F.Y + dY, replace); F.Y := F.Y + dY
      END;
      Extend(F, Y);
    ELSIF id = reduce THEN
      Reduce(F, Y + dY);
      IF dY > 0 THEN Display.CopyBlock(F.X, F.Y, F.W, F.H, F.X, Y, replace); F.Y := Y END;
    END;
    IF F.H > 0 THEN Mark(F, 1) END;
  END Modify;

  PROCEDURE Open* (F: Frame; H: Objects.Handler; T: Texts.Text; org: LONGINT; col : Display.COLOR; left, right, top, bot, lsp: INTEGER);
    VAR L: Line;
  BEGIN NEW(L);
    L.len := 0; L.wid := 0; L.eot := FALSE; L.next := L;
    F.handle := H; F.text := T; F.org := org; F.trailer := L;
    F.left := left; F.right := right; F.top := top; F.bot := bot;
    F.lsp := lsp; F.col := col; F.mark := 0; F.car := 0; F.sel := 0;
  END Open;

  PROCEDURE Copy* (F: Frame; VAR F1: Frame);
  BEGIN NEW(F1);
    Open(F1, F.handle, F.text, F.org, F.col, F.left, F.right, F.top, F.bot, F.lsp)
  END Copy;

  PROCEDURE CopyOver* (F: Frame; text: Texts.Text; beg, end: LONGINT);
    VAR  buf: Texts.Buffer;
  BEGIN
    IF F.car > 0 THEN
      NEW(buf); Texts.OpenBuf(buf);
      Texts.Save(text, beg, end, buf);
      Texts.Insert(F.text, F.carloc.pos, buf);
      SetCaret(F, F.carloc.pos + (end - beg))
    END
  END CopyOver;

  PROCEDURE GetSelection* (F: Frame; VAR M: Oberon.SelectMsg);
  BEGIN
    IF F.sel > 0 THEN
      IF F.time > M.time THEN M.sel := F; M.time := F.time;
        M.text := F.text; M.beg := F.selbeg.pos; M.end := F.selend.pos;
        IF M.end > M.text.len THEN M.end := M.text.len END
      ELSIF (F.text = M.text) & (F.selbeg.pos < M.beg) THEN M.beg := F.selbeg.pos
      END
    END
  END GetSelection;

  PROCEDURE GetCaret* (F: Frame; VAR M: Oberon.CaretMsg);
  BEGIN IF F.car > 0 THEN M.text := F.text; M.pos := F.carloc.pos; M.car := F; M.res := 0 END
  END GetCaret;

  PROCEDURE LineLen (VAR R: Texts.Reader): LONGINT;
    VAR len: LONGINT;
  BEGIN len := 0;
    WHILE (ch # CR) & (R.lib # NIL) DO INC(len); Texts.Read(R, ch) END;
    Texts.Read(R, ch);
    RETURN len + 1
  END LineLen;

  PROCEDURE Update* (F: Frame; beg, end, len: LONGINT);
    VAR R: Texts.Reader; L, LB, LR, LS: Line; done: BOOLEAN;
      org, orgB, orgL, orgS, off, Llen: LONGINT;
      botY, Y, YB, YL, YR, YS, wid, H: INTEGER;
  BEGIN
    IF end < F.org THEN F.org := F.org - (end - beg) + len;
    ELSE
      IF beg < F.org THEN
        F.trailer.next.len := F.trailer.next.len + (F.org - beg);
        F.org := beg
      END;
      botY := F.Y + F.bot + dsr;
      org := F.org; Y := F.Y + F.H - F.top - asr; L := F.trailer.next;
      WHILE (L # F.trailer) & (org + L.len <= beg) DO
        org := org + L.len; Y := Y - lsp; L := L.next
      END;
      IF L # F.trailer THEN done := FALSE;
        RemoveMarks(F); Oberon.RemoveMarks(F.X, F.Y, F.W, F.H);
        orgB := org; YB := Y; LB := L;
        WHILE (L # F.trailer) & (org + L.len <= end) DO
          org := org + L.len; Y := Y - lsp; L := L.next
        END;
        IF L # F.trailer THEN
          org := org + L.len; Y := Y - lsp; L := L.next;
          IF L # F.trailer THEN
            YR := Y; LR := L; org := orgB; Y := YB;
            Texts.OpenReader(R, F.text, org); Texts.Read(R, ch);
            Llen := LineLen(R);
            WHILE (org + Llen <= beg + len) & (botY + lsp <= Y) DO
              org := org + Llen; Y := Y - lsp; Llen := LineLen(R)
            END;
            org := org + Llen; Y := Y - lsp;
            IF botY <= Y THEN (* update with reusing lines *)
              orgL := org; YL := Y; L := LR;
              WHILE (L.next # F.trailer) & (botY + lsp <= Y) DO
                org := org + L.len; Y := Y - lsp; L := L.next
              END;
              orgS := org; YS := Y; LS := L;
              Display.CopyBlock (
                F.X + F.left, YS - dsr + (YR - YL), F.W - F.left, YL + lsp - YS, F.X + F.left, YS - dsr, replace);
              org := orgB; Y := YB; L := LB;
              Texts.OpenReader(R, F.text, org); Texts.Read(R, ch);
              off := beg - org; wid := Width(R, off);
              ReplConst (F.col, F, F.X + F.left + wid, Y - dsr, L.wid - wid, lsp, replace);
              DisplayLine(F, L, R, F.X + F.left + wid, Y, off);
              WHILE org + L.len <= beg + len DO
                org := org + L.len; Y := Y - lsp; NEW(L.next); L := L.next;
                Display.ReplConst(F.col, F.X + F.left, Y - dsr, F.W - F.left, lsp, replace);
                DisplayLine(F, L, R, F.X + F.left, Y, 0)
              END;
              L.next := LR;
              org := orgS; Y := YS; L := LS; org := org + L.len; Y := Y - lsp;
              Texts.OpenReader(R, F.text, org); Texts.Read(R, ch);
              WHILE ~L.eot & (botY <= Y) DO
                NEW(L.next); L := L.next;
                Display.ReplConst(F.col, F.X + F.left, Y - dsr, F.W - F.left, lsp, replace);
                DisplayLine(F, L, R, F.X + F.left, Y, 0);
                org := org + L.len; Y := Y - lsp
              END;
              L.next := F.trailer;
              IF YR < YL THEN H := Min(YL- YR, Y + lsp - dsr - F.Y);
                Display.ReplConst(F.col, F.X + F.left, Y + lsp - dsr - H, F.W - F.left, H, replace)
              END;
              done := TRUE
            END
          END
        END;
        IF ~done THEN (* update without reusing lines *)
          YR := Y; org := orgB; Y := YB; L := LB;
          Texts.OpenReader(R, F.text, org); Texts.Read(R, ch);
          off := beg - org; wid := Width(R, off);
          ReplConst (F.col, F, F.X + F.left + wid, Y - dsr, L.wid - wid, lsp, replace);
          DisplayLine(F, L, R, F.X + F.left + wid, Y, off);
          WHILE ~L.eot & (botY + lsp <= Y) DO
            org := org + L.len; Y := Y - lsp; NEW(L.next); L := L.next;
            Display.ReplConst(F.col, F.X + F.left, Y - dsr, F.W - F.left, lsp, replace);
            DisplayLine(F, L, R, F.X + F.left, Y, 0)
          END;
          org := org + L.len; Y := Y - lsp;
          IF (Y < botY) & (org <= beg + len) & (beg + len < org + 500) THEN (*autoscroll*)
            REPEAT
              Display.CopyBlock
              (F.X + F.left, Y + lsp - dsr, F.W - F.left, F.Y + F.H - F.top - asr - Y - lsp,
                  F.X + F.left, Y + lsp - dsr + lsp,
              replace);
              F.org := F.org + F.trailer.next.len;
              L.next := F.trailer.next; F.trailer.next := F.trailer.next.next;
              L := L.next;
              Display.ReplConst(F.col, F.X + F.left, Y + lsp - dsr, F.W - F.left, lsp, replace);
              DisplayLine(F, L, R, F.X + F.left, Y + lsp, 0);
              org := org + L.len
            UNTIL org > beg + len
          END;
          L.next := F.trailer;
          IF YR < Y THEN
            Display.ReplConst (F.col, F.X + F.left, YR + lsp - dsr, F.W - F.left, Y - YR, replace)
          END
        END
      END
    END;
    UpdateMark(F)
  END Update;

  PROCEDURE Recall (F: Frame);
    VAR buf: Texts.Buffer; pos: LONGINT;
  BEGIN
    IF F.car > 0 THEN
    NEW(buf); Texts.OpenBuf(buf);
      Texts.Recall(buf); pos := F.carloc.pos + buf.len;
    Texts.Insert(F.text, F.carloc.pos, buf);
      SetCaret(F, pos)
    END
  END Recall;

  PROCEDURE Edit* (F: Frame; X, Y: INTEGER; Keys: SET);
    VAR
      M: Oberon.ConsumeMsg;
      R: Texts.Reader;
      text: Texts.Text; buf: Texts.Buffer;
      time, pos, beg, end: LONGINT;
      keysum: SET;
      ch: CHAR;
  BEGIN
    Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, X, Y);
    IF X < F.X + Min(F.left, barW) THEN
      IF (0 IN Keys) OR (1 IN Keys) THEN keysum := Keys;
        REPEAT
          Input.Mouse(Keys, X, Y);
          keysum := keysum + Keys;
          Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, X, Y)
        UNTIL Keys = {};
        IF ~(2 IN keysum) THEN
          RemoveMarks(F); Oberon.RemoveMarks(F.X, F.Y, F.W, F.H);
          IF (0 IN keysum) OR (F.Y + F.H < Y) THEN pos := 0
            ELSE pos := (F.Y + F.H - Y) * (F.text.len) DIV F.H
          END;
          RemoveMarks(F); Oberon.RemoveMarks(F.X, F.Y, F.W, F.H);
          Show(F, pos)
        ELSIF ~(0 IN keysum) THEN
          RemoveMarks(F); Oberon.RemoveMarks(F.X, F.Y, F.W, F.H);
          Show(F, F.text.len)
        END
      ELSIF 2 IN Keys THEN
        TrackLine(F, X, Y, pos, keysum);
        IF (pos >= 0) & ~(0 IN keysum) THEN
          RemoveMarks(F); Oberon.RemoveMarks(F.X, F.Y, F.W, F.H);
          Show(F, pos)
        END
      END
  ELSE
    IF 0 IN Keys THEN
      TrackSelection(F, X, Y, keysum);
      IF F.sel # 0 THEN
        IF (2 IN keysum) & ~(1 IN keysum) THEN (*delete text*)
          Oberon.GetSelection(text, beg, end, time);
          Texts.Delete(text, beg, end);
          Oberon.Defocus; SetCaret(F, beg)
        ELSIF (1 IN keysum) & ~(2 IN keysum) THEN (*copy to focus*)
          Oberon.GetSelection(text, beg, end, time);
          M.F := NIL; M.text := text; M.beg := beg; M.end := end;
          Display.Broadcast(M)
      END
      END
    ELSIF 1 IN Keys THEN
      TrackWord(F, X, Y, pos, keysum);
      IF (pos >= 0) & ~(0 IN keysum) THEN Call(F, pos, 2 IN keysum) END
    ELSIF 2 IN Keys THEN
        Oberon.Defocus; TrackCaret(F, X, Y, keysum);
        IF F.car # 0 THEN
          IF (1 IN keysum) & ~(0 IN keysum) THEN (*copy from selection*)
            Oberon.GetSelection(text, beg, end, time);
             IF time >= 0 THEN
                NEW(buf); Texts.OpenBuf(buf);
                Texts.Save(text, beg, end, buf);
                Texts.Insert(F.text, F.carloc.pos, buf);
                SetCaret(F, F.carloc.pos + (end - beg))
              END
           ELSIF (0 IN keysum) & ~(1 IN keysum) THEN (*copy font*)
              Oberon.GetSelection(text, beg, end, time);
              IF time >= 0 THEN
                Texts.OpenReader(R, F.text, F.carloc.pos); Texts.Read(R, ch);
                Texts.ChangeLooks(text, beg, end, {0, 1, 2}, R.lib, R.col, R.voff)
              END
            END
         END
       END
    END
  END Edit;

  PROCEDURE Handle* (F: Objects.Object; VAR M: Objects.ObjMsg);
    VAR F1: Frame;
  BEGIN
    WITH F: Frame DO
      IF M IS Texts.UpdateMsg THEN
        WITH M: Texts.UpdateMsg DO
          IF F.text = M.text THEN Update(F, M.beg, M.end, M.len) END
        END
      ELSIF M IS Oberon.InputMsg THEN
         WITH M: Oberon.InputMsg DO
          IF M.id = Oberon.track THEN Edit(F, M.X, M.Y, M.keys)
          ELSIF M.id = Oberon.consume THEN
          IF F.car # 0 THEN Write(F, M.ch, M.fnt, M.col, M.voff) END
          END
         END
      ELSIF M IS Oberon.ControlMsg THEN
        WITH M: Oberon.ControlMsg DO
        IF M.id = Oberon.defocus THEN Defocus(F)
        ELSIF M.id = Oberon.neutralize THEN Neutralize(F)
          END
        END
      ELSIF M IS Oberon.CaretMsg THEN
        WITH M: Oberon.CaretMsg DO
          IF M.id = Oberon.get THEN GetCaret(F, M)
          ELSIF (M.car = F) & (M.text = F.text) THEN
            IF M.id = Oberon.set THEN SetCaret(F, M.pos)
              ELSIF M.id = Oberon.reset THEN RemoveCaret(F)
            END
          END
        END
      ELSIF M IS Oberon.SelectMsg THEN
        WITH M: Oberon.SelectMsg DO
          IF M.id = Oberon.get THEN GetSelection(F, M)
          ELSIF (M.sel = F) & (M.text = F.text) THEN
            IF M.id = Oberon.set THEN SetSelection(F, M.beg, M.end)
              ELSIF M.id = Oberon.reset THEN RemoveSelection(F)
            END
          END
        END
      ELSIF M IS Oberon.ConsumeMsg THEN
        WITH M: Oberon.ConsumeMsg DO
          CopyOver(F, M.text, M.beg, M.end)
        END
      ELSIF M IS Oberon.RecallMsg THEN
        WITH M: Oberon.RecallMsg DO Recall(F) END
      ELSIF M IS Display.ModifyMsg THEN
        WITH M: Display.ModifyMsg DO
          IF M.F = F THEN Modify(F, M.id, M.dY, M.Y, M.H) END
        END
      ELSIF M IS Display.LocateMsg THEN
        WITH M: Display.LocateMsg DO
          IF (F.X <= M.X) & (M.X < F.X + F.W) & (F.Y <= M.Y) & (M.Y < F.Y + F.H) THEN
            M.loc := F; M.res := 0
          END
        END
      ELSIF M IS Objects.AttrMsg THEN
        WITH M: Objects.AttrMsg DO GetAttr(F, M.s) END
      ELSIF M IS Objects.CopyMsg THEN
        WITH M: Objects.CopyMsg DO Copy(F, F1); M.obj := F1 END
      ELSIF M IS Objects.LinkMsg THEN
        WITH M: Objects.LinkMsg DO M.obj := F.text; M.res := 0 END
    END
    END;
  END Handle;

  (*creation*)

  PROCEDURE Menu (name, commands: ARRAY OF CHAR): Texts.Text;
    VAR T: Texts.Text;
  BEGIN
    NEW(T); Texts.Open(T, "");
    Texts.WriteString(W, name); Texts.WriteString(W, " | "); Texts.WriteString(W, commands);
    Texts.Append(T, W.buf);
    RETURN T
 END Menu;

  PROCEDURE Text* (name: ARRAY OF CHAR): Texts.Text;
    VAR T: Texts.Text;
  BEGIN NEW(T); Texts.Open(T, name); RETURN T
  END Text;

  PROCEDURE NewMenu* (name, commands: ARRAY OF CHAR): Frame;
    VAR F: Frame;
  BEGIN NEW(F); Open(F, Handle, Menu(name, commands), 0, MenuBG, left DIV 4, 0, 1, 0, lsp); RETURN F
  END NewMenu;

  PROCEDURE NewText* (text: Texts.Text; pos: LONGINT): Frame;
    VAR F: Frame;
  BEGIN NEW(F); Open(F, Handle, text, pos, TextBG, left, right, top, bot, lsp); RETURN F
  END NewText;

BEGIN
  MarkColor := Display.GetHostColor(Display.ColActiveBorder);
  BarColor := Display.GetHostColor(Display.ColMenu);
  MenuBG := Display.GetHostColor(Display.ColMenuBg);
  TextBG := Display.GetHostColor(Display.ColWindowBg);
  FullColor := Display.GetHostColor(Display.ColWindow);

  ASSERT(Fonts.Default # NIL);
  menuH := Fonts.Default.height + 2;
  barW := Fonts.Default.height + 2;
  left := barW + Fonts.Default.height DIV 2;
  right := Fonts.Default.height DIV 2;
  top := Fonts.Default.height DIV 2;
  bot := Fonts.Default.height DIV 2;
  asr := Fonts.Default.maxY;
  dsr := -Fonts.Default.minY;
  lsp := Fonts.Default.height;
  selH := Fonts.Default.height;
  markW := Fonts.Default.height DIV 3 * 2;
  eolW := Fonts.Default.height DIV 2;
  boxW := Fonts.Default.height;
  Texts.OpenWriter(W); Texts.OpenWriter(KW);
  BoxPat[0] := {0..11};
  BoxPat[1] := {0, 11}; BoxPat[2] := {0, 11}; BoxPat[3] := {0, 11}; BoxPat[4] := {0, 11};
  BoxPat[5] := {0, 11}; BoxPat[6] := {0, 11}; BoxPat[7] := {0, 11}; BoxPat[8] := {0, 11};
  BoxPat[9] := {0, 11}; BoxPat[10] := {0, 11}; BoxPat[11] := {0.. 11};
  NEW(box);
  box.dx := 12; box.x := 0; box.y := -3; box.w := 12; box.h := 12;
  box.pat := Display.NewPattern(BoxPat, 12, 12);
  NEW(par)
END TextFrames.
