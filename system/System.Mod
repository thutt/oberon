MODULE System; (*JG 7.4.95 / NW 26.11.91 / DOS ARD 4. 2. 93*)

  IMPORT SYSTEM, Kernel, Modules, FileDir, Files, Input, Display,
    Viewers, MenuViewers, Oberon, Objects, Texts, TextFrames, Fonts;

  CONST
    StandardMenu = "System.Close System.Copy System.Grow Edit.Search Edit.Store";
    ModulesMenu = "System.Close System.Copy System.Grow System.Free Edit.Store";
    LogMenu = "System.Close System.Grow Edit.Locate Edit.Store";

  VAR W: Texts.Writer;
    pos: INTEGER;
    trapped: SHORTINT;
    diroption: CHAR;
    pat: ARRAY 32 OF CHAR;
    Dummy: Modules.Module;
    OriginalBC: Display.MsgProc;

  PROCEDURE NullBC(VAR M: Display.FrameMsg);
  END NullBC;

  PROCEDURE Max (i, j: LONGINT): LONGINT;
  BEGIN IF i >= j THEN RETURN i ELSE RETURN j END
  END Max;

  (* ------------- Toolbox for system control ---------------*)

  PROCEDURE SetUser*;
  VAR R: Texts.Reader; i, j: INTEGER; ch: CHAR;
      user: ARRAY 8 OF CHAR; password: ARRAY 16 OF CHAR;
  BEGIN i := 0; j := 0;
    Texts.OpenReader(R, Oberon.Par.text, Oberon.Par.pos);
    REPEAT Texts.Read(R, ch) UNTIL ch # " ";
    IF (ch = 0DX) OR (ch = "/") THEN Input.Read(ch);
      WHILE (ch > " ") & (ch # "/") DO
        IF i # 7 THEN user[i] := ch; INC(i) END; Input.Read(ch)
      END;
      IF ch = "/" THEN Input.Read(ch);
        WHILE ch > " " DO
          IF j # 15 THEN password[j] := ch; INC(j) END; Input.Read(ch)
        END
      END
    ELSE
      WHILE (ch > " ") & (ch # "/") DO
        IF i # 7 THEN user[i] := ch; INC(i) END; Texts.Read(R, ch)
      END;
      IF ch = "/" THEN Input.Read(ch);
        WHILE ch > " " DO
          IF j # 15 THEN password[j] := ch; INC(j) END; Input.Read(ch)
        END
      END
    END;
    user[i] := 0X; password[j] := 0X;
    Oberon.SetUser(user, password)
  END SetUser;

  PROCEDURE SetFont*;
  VAR beg, end, time: LONGINT;
      T: Texts.Text; S: Texts.Scanner;
  BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") THEN
      Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN
        Texts.OpenScanner(S, T, beg); Texts.Scan(S);
        IF S.class = Texts.Name THEN Oberon.SetFont(Fonts.This(S.s)) END
      END
    ELSIF S.class = Texts.Name THEN Oberon.SetFont(Fonts.This(S.s))
    END
  END SetFont;

  PROCEDURE SetColor*;
  VAR beg, end, time: LONGINT;
      T: Texts.Text; S: Texts.Scanner; ch: CHAR;
  BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") THEN
      Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN
        Texts.OpenReader(S, T, beg); Texts.Read(S, ch); Oberon.SetColor(S.col)
      END
    ELSIF S.class = Texts.Int THEN Oberon.SetColor(S.i);
    END
  END SetColor;

  PROCEDURE SetOffset*;
  VAR beg, end, time: LONGINT;
      T: Texts.Text;S: Texts.Scanner; ch: CHAR;
  BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") THEN
      Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN
        Texts.OpenReader(S, T, beg); Texts.Read(S, ch); Oberon.SetOffset(S.voff)
      END
    ELSIF S.class = Texts.Int THEN Oberon.SetOffset(SHORT(SHORT(S.i)))
    END
  END SetOffset;

  PROCEDURE Time*;
  VAR par: Oberon.ParList;
      S: Texts.Scanner;
      t, d, hr, min, sec, yr, mo, day: LONGINT;
  BEGIN par := Oberon.Par;
    Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
    IF S.class = Texts.Int THEN (*set date*)
      day := S.i; Texts.Scan(S); mo := S.i; Texts.Scan(S); yr := S.i; Texts.Scan(S);
      hr := S.i; Texts.Scan(S); min := S.i; Texts.Scan(S); sec := S.i;
      t := (hr*64 + min)*64 + sec; d := (yr*16 + mo)*32 + day;
      ASSERT(FALSE); (*SetClock(t, d)*)
    ELSE (*read date*)
      Texts.WriteString(W, "System.Time");
      Oberon.GetClock(t, d); Texts.WriteDate(W, t, d); Texts.WriteLn(W);
      Texts.Append(Oberon.Log, W.buf)
    END
  END Time;

  PROCEDURE Collect*;
  BEGIN Oberon.Collect
  END Collect;

  (* ------------- Toolbox for standard display ---------------*)

  PROCEDURE Open*;
  VAR par: Oberon.ParList;
      T: Texts.Text;
      S: Texts.Scanner;
      V: Viewers.Viewer;
      X, Y: INTEGER;
      beg, end, time: LONGINT;
  BEGIN
    par := Oberon.Par;
    Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") OR (S.line # 0) THEN
      Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S) END
    END;
    IF S.class = Texts.Name THEN
      Oberon.AllocateSystemViewer(par.vwr.X, X, Y);
      V := MenuViewers.New(
        TextFrames.NewMenu(S.s, StandardMenu),
        TextFrames.NewText(TextFrames.Text(S.s), 0),
        TextFrames.menuH,
        X, Y)
    END
  END Open;

  PROCEDURE OpenLog*;
  VAR logV: Viewers.Viewer; X, Y: INTEGER;
  BEGIN
    Oberon.AllocateSystemViewer(Oberon.Par.vwr.X, X, Y);
    logV := MenuViewers.New(
      TextFrames.NewMenu("System.Log", LogMenu),
      TextFrames.NewText(Oberon.Log, Max(0, Oberon.Log.len - 200)),
      TextFrames.menuH,
      X, Y)
  END OpenLog;

  PROCEDURE Close*;
  VAR  par: Oberon.ParList; V: Viewers.Viewer;
  BEGIN par := Oberon.Par;
    IF par.frame = par.vwr.dsc THEN V := par.vwr
    ELSE V := Oberon.MarkedViewer()
    END;
    Viewers.Close(V)
  END Close;

  PROCEDURE CloseTrack*;
  VAR V: Viewers.Viewer;
  BEGIN V := Oberon.MarkedViewer(); Viewers.CloseTrack(V.X)
  END CloseTrack;

  PROCEDURE Recall*;
  VAR V: Viewers.Viewer; M: Display.ControlMsg;
  BEGIN
    Viewers.Recall(V);
    IF (V#NIL) & (V.state = 0) THEN
      Viewers.Open(V, V.X, V.Y + V.H); M.id := Display.restore; V.handle(V, M)
    END
  END Recall;

  PROCEDURE Copy*;
  VAR V, V1: Viewers.Viewer; M: Objects.CopyMsg; N: Display.ControlMsg;
  BEGIN
        M.id := Objects.shallow;
    V := Oberon.Par.vwr; V.handle(V, M); V1 := M.obj(Viewers.Viewer);
    Viewers.Open(V1, V.X, V.Y + V.H DIV 2);
    N.id := Display.restore; V1.handle(V1, N)
  END Copy;

  PROCEDURE Grow*;
  VAR V, V1: Viewers.Viewer; M: Objects.CopyMsg; N: Display.ControlMsg;
      DW, DH: INTEGER;
  BEGIN V := Oberon.Par.vwr;
    DW := Oberon.DisplayWidth(V.X); DH := Oberon.DisplayHeight(V.X);
    IF V.H < DH - Viewers.minH THEN Oberon.OpenTrack(V.X, V.W)
    ELSIF V.W < DW THEN Oberon.OpenTrack(Oberon.UserTrack(V.X), DW)
    END;
    IF (V.H < DH - Viewers.minH) OR (V.W < DW) THEN
      M.id := Objects.shallow;
            V.handle(V, M); V1 := M.obj(Viewers.Viewer);
      Viewers.Open(V1, V.X, DH);
      N.id := Display.restore; V1.handle(V1, N)
    END
  END Grow;

  (* ------------- Toolbox for module management ---------------*)

    PROCEDURE Free*;
    VAR par: Oberon.ParList; S: Texts.Scanner; F: TextFrames.Frame;

      PROCEDURE FreeFile;
      BEGIN
        Texts.WriteString(W, S.s); Texts.WriteString(W, " unloading");
        Texts.Append(Oberon.Log, W.buf);
        IF S.nextCh # "*" THEN Modules.Free(S.s, FALSE)
          ELSE Modules.Free(S.s, TRUE); Texts.Scan(S); Texts.WriteString(W, " all")
        END;
        IF Modules.res # 0 THEN Texts.WriteString(W, " failed") END;
        Texts.WriteLn(W);
        Texts.Append(Oberon.Log, W.buf)
      END FreeFile;

    BEGIN par := Oberon.Par;
        Texts.WriteString(W, "System.Free"); Texts.WriteLn(W);
        Texts.Append(Oberon.Log, W.buf);
        IF par.vwr.dsc # par.frame THEN
          Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
          WHILE S.class = Texts.Name DO FreeFile; Texts.Scan(S) END;
        ELSE
          F := par.vwr.dsc.next(TextFrames.Frame);
          IF F.sel > 0 THEN
            Texts.OpenScanner(S, F.text, F.selbeg.pos);
            WHILE ~S.eot & (Texts.Pos(S) < F.selend.pos) DO Texts.Scan(S);
              IF S.class = Texts.Name THEN FreeFile;
                IF Modules.res = 0 THEN
                  Texts.OpenReader(S, F.text, F.selbeg.pos);
                  REPEAT Texts.Read(S, S.nextCh) UNTIL S.eot OR (S.nextCh = 0DX);
                  Texts.Delete(F.text, F.selbeg.pos, Texts.Pos(S));
                  DEC(F.selend.pos, Texts.Pos(S) - F.selbeg.pos);
                  Texts.OpenScanner(S, F.text, F.selbeg.pos);
                END
              ELSE F.selbeg.pos := Texts.Pos(S)
              END
            END
          END
        END
    END Free;

  PROCEDURE ShowModules*;
  VAR T: Texts.Text;
      V: Viewers.Viewer;
      M: Modules.Module;
      X, Y: INTEGER;
  BEGIN T := TextFrames.Text("");
    M := Modules.modules;
    WHILE M # NIL DO
      Texts.WriteString(W, M.name^);
      ASSERT(M.code # NIL); (* there must always be a code segment *)
      Texts.WriteInt(W, LEN(M.code^), 8);
      Texts.WriteInt(W, M.refcnt, 4);
      Texts.WriteLn(W); M := M.next;
    END;
    Texts.Append(T, W.buf);
    Oberon.AllocateSystemViewer(Oberon.Par.vwr.X, X, Y);
    V := MenuViewers.New(TextFrames.NewMenu("System.ShowModules", ModulesMenu),
            TextFrames.NewText(T, 0), TextFrames.menuH, X, Y);
  END ShowModules;

  (* ------------- Toolbox for library management ---------------*)
    
  PROCEDURE ListLibrary (L: Objects.Library);
  BEGIN Texts.WriteString(W, L.name); Texts.WriteLn(W)
  END ListLibrary;

  PROCEDURE ShowLibraries*;
    VAR T: Texts.Text; V: Viewers.Viewer; X, Y: INTEGER;
  BEGIN Objects.Enumerate(ListLibrary);
    Texts.Append(Oberon.Log, W.buf)
  END ShowLibraries;

  PROCEDURE FreeLibraries*;
    VAR par: Oberon.ParList;
      T: Texts.Text; S: Texts.Scanner; F: TextFrames.Frame;
      f: Files.File; L: Objects.Library;
      beg, end, time, len: LONGINT; res : INTEGER;
  BEGIN    
    par := Oberon.Par;
    Texts.WriteString(W, "Libraries.Free "); Texts.WriteLn(W);
    Texts.Append(Oberon.Log, W.buf);
    Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") THEN
      Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S) END
    END;
    WHILE S.class = Texts.Name DO
      Objects.FreeLibrary(S.s); Texts.WriteString(W,S.s); Texts.WriteLn(W);
      Texts.Scan(S);
    END;
    Texts.Append(Oberon.Log, W.buf)
  END FreeLibraries;

  (* ------------- Toolbox of file system ---------------*)

  PROCEDURE List(VAR (* R/O *) name: FileDir.Filename; VAR cont: BOOLEAN);
  VAR i0, i1, j0, j1: INTEGER; f: BOOLEAN; Time, Date, size: LONGINT;
  BEGIN
    ASSERT(FALSE);
(*    
     i0 := pos; j0 := pos; f := TRUE;
    LOOP
      IF pat[i0] = "*" THEN INC(i0);
        IF pat[i0] = 0X THEN EXIT END
      ELSE
        IF name[j0] # 0X THEN f := FALSE END;
        EXIT
      END;
      f := FALSE;
      LOOP
        IF name[j0] = 0X THEN EXIT END;
        i1 := i0; j1 := j0;
        LOOP
          IF (pat[i1] = 0X) OR (pat[i1] = "*") THEN f := TRUE; EXIT END;
          IF pat[i1] # name[j1] THEN EXIT END;
          INC(i1); INC(j1)
        END;
        IF f THEN j0 := j1; i0 := i1; EXIT END;
        INC(j0)
      END;
      IF ~f THEN EXIT END
    END;
    IF f & (name[0] # 0X) THEN
      Texts.WriteString(W, name);
      IF diroption = "d" THEN
        Files.FileList(name, dos, f);
        ASSERT(FALSE); (*DirOpt(dos, Time, Date, size); *)
        Texts.WriteString(W, "  "); Texts.WriteDate(W, Time, Date);
        Texts.WriteString(W, "  "); Texts.WriteInt(W, size, 5)
      END;
      Texts.WriteLn(W)
    END
*)
  END List;

  PROCEDURE Directory*;
  VAR par: Oberon.ParList;
      R: Texts.Reader;
      T, t: Texts.Text;
      V: Viewers.Viewer;
      beg, end, time: LONGINT;
      X, Y, i: INTEGER;
      ch: CHAR;
      pre: ARRAY 32 OF CHAR;
      opt: CHAR;
  BEGIN
    par := Oberon.Par;
    Texts.OpenReader(R, par.text, par.pos); Texts.Read(R, ch);
    WHILE ch = " " DO Texts.Read(R, ch) END;
    IF (ch = "^") OR (ch = 0DX) THEN
       Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN
        Texts.OpenReader(R, T, beg); Texts.Read(R, ch);
        WHILE ch <= " " DO Texts.Read(R, ch) END
      END
    END;
    i := 0;
    WHILE (ch > " ") & (ch # "/") & (ch # "%") DO pat[i] := ch; INC(i); Texts.Read(R, ch) END;
    pat[i] := 0X;
    IF (ch = "/") OR (ch = "%") THEN Texts.Read(R, diroption); Texts.Read(R, opt) ELSE diroption := 0X END;
    IF (opt = "d") & (diroption = "l") THEN diroption := "d"; opt := "l"
    ELSIF (diroption = "l") THEN opt := "l" END;
    IF (diroption = "d") THEN opt := "l" END;
    i := 0;
    WHILE pat[i] > "*" DO pre[i] := pat[i]; INC(i) END;
    pre[i] := 0X; pos := i;
    t := TextFrames.Text("");
    FileDir.Enumerate(pre, List);
    Texts.Append(t, W.buf);
    Oberon.AllocateSystemViewer(par.vwr.X, X, Y);
    V := MenuViewers.New(
      TextFrames.NewMenu("System.Directory", StandardMenu),
      TextFrames.NewText(t, 0),
      TextFrames.menuH,
      X, Y);
  END Directory;

  PROCEDURE CopyFiles*;
  VAR beg, end, time: LONGINT; res: INTEGER;
      T: Texts.Text;
  BEGIN
    ASSERT(FALSE);
(*
    Texts.WriteString(W, "System.CopyFiles"); Texts.WriteLn(W);
    Texts.Append(Oberon.Log, W.buf);
    Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
    ScanDosName(S); (*Texts.Scan(S);*)
    IF (S.class = Texts.Char) & (S.c = "^") THEN Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN
        Texts.OpenScanner(S, T, beg); ScanDosName(S); (*Texts.Scan(S);*)
        IF S.class = Texts.Name THEN CopyFile(S.d, S) END
      END
    ELSE
      WHILE S.class = Texts.Name DO CopyFile(S.d, S); ScanDosName(S) (*Texts.Scan(S)*) END
    END
*)
  END CopyFiles;

  PROCEDURE RenameFile (name: ARRAY OF CHAR; VAR S: Texts.Scanner);
  VAR res: INTEGER;
  BEGIN Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "=") THEN Texts.Scan(S);
      IF (S.class = Texts.Char) & (S.c = ">") THEN Texts.Scan(S);
        IF S.class = Texts.Name THEN
          Texts.WriteString(W, name); Texts.WriteString(W, " => "); Texts.WriteString(W, S.s);
          Texts.WriteString(W, " renaming"); Texts.Append(Oberon.Log, W.buf);
          Files.Rename(name, S.s, res);
          IF res > 1 THEN Texts.WriteString(W, " failed") END;
          Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
        END
      END
    END
  END RenameFile;

  PROCEDURE RenameFiles*;
  VAR beg, end, time: LONGINT; res: INTEGER;
      T: Texts.Text;
      S: Texts.Scanner;
  BEGIN Texts.WriteString(W, "System.RenameFiles"); Texts.WriteLn(W);
    Texts.Append(Oberon.Log, W.buf);
    Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") THEN
      Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN
        Texts.OpenScanner(S, T, beg); Texts.Scan(S);
        IF S.class = Texts.Name THEN RenameFile(S.s, S) END
      END
    ELSE
      WHILE S.class = Texts.Name DO RenameFile(S.s, S); Texts.Scan(S) END
    END
  END RenameFiles;

  PROCEDURE DeleteFile(VAR name: ARRAY OF CHAR);
   VAR res: INTEGER;
  BEGIN Texts.WriteString(W, name); Texts.WriteString(W, " deleting");
    Texts.Append(Oberon.Log, W.buf); Files.Delete(name, res);
    IF res # 0 THEN Texts.WriteString(W, " failed") END;
    Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
  END DeleteFile;

  PROCEDURE DeleteFiles*;
  VAR beg, end, time: LONGINT;
      T: Texts.Text;
      S: Texts.Scanner;
  BEGIN Texts.WriteString(W, "System.DeleteFiles"); Texts.WriteLn(W);
    Texts.Append(Oberon.Log, W.buf);
    Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") THEN
      Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S);
        IF S.class = Texts.Name THEN DeleteFile(S.s) END
      END
    ELSE
      WHILE S.class = Texts.Name DO DeleteFile(S.s); Texts.Scan(S) END
    END
  END DeleteFiles;

  (* ------------- Toolbox for system inspection ---------------*)

  PROCEDURE Watch*;
  BEGIN
    Texts.WriteInt(W, Kernel.Available(), 1); Texts.WriteString(W, " bytes free");
    Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
  END Watch;

  PROCEDURE Locals(VAR R: Files.Rider; base: LONGINT);
  VAR adr, val: LONGINT;
      sval, form: SHORTINT;
      ch, mode: CHAR;
      ival, i: INTEGER;
      rval: REAL;
      lrval: LONGREAL;
  BEGIN Texts.WriteLn(W); Files.Read(R, mode);
    WHILE ~R.eof & (mode < 0F8X) DO
      Files.Read(R, form); Files.ReadBytes(R, adr, 4);
      Texts.WriteString(W, "    "); Files.Read(R, ch);
      WHILE ch > 0X DO Texts.Write(W, ch); Files.Read(R, ch) END;
      Texts.WriteString(W, " = "); INC(adr, base);
      IF mode = 3X THEN SYSTEM.GET(adr, adr) (*indirect*) END;
      CASE form OF
        2: (*BOOL*) SYSTEM.GET(adr, sval);
        IF sval = 0 THEN Texts.WriteString(W, "FALSE")
          ELSE Texts.WriteString(W, "TRUE")
        END
      | 1,3: (*CHAR*) SYSTEM.GET(adr, ch);
        IF (" " <= ch) & (ch <= "~") THEN Texts.Write(W, ch)
          ELSE Texts.WriteHex(W, ORD(ch)); Texts.Write(W, "X")
        END
      | 4: (*SINT*) SYSTEM.GET(adr, sval); Texts.WriteInt(W, sval, 1)
      | 5: (*INT*) SYSTEM.GET(adr, ival); Texts.WriteInt(W, ival, 1)
      | 6: (*LINT*) SYSTEM.GET(adr, val); Texts.WriteInt(W, val, 1)
      | 7: (*REAL*) SYSTEM.GET(adr, rval); Texts.WriteReal(W, rval, 15)
      | 8: (*LREAL*) SYSTEM.GET(adr, lrval); Texts.WriteLongReal(W, lrval, 24)
      | 9, 13, 14: (*SET, POINTER*)
        SYSTEM.GET(adr, val); Texts.WriteHex(W, val); Texts.Write(W, "H")
      | 15, 17, 18: (*String*) i := 0; Texts.Write(W, 22X);
        LOOP SYSTEM.GET(adr, ch);
          IF (ch < " ") OR (ch >= 90X) OR (i = 64) THEN EXIT END;
          Texts.Write(W, ch); INC(i); INC(adr)
        END;
        Texts.Write(W, 22X)
      END;
      Texts.WriteLn(W); Files.Read(R, mode)
    END
  END Locals;

  PROCEDURE OutState (VAR name: ARRAY OF CHAR; t: Texts.Text);
  VAR mod: Modules.Module;
    refpos: LONGINT;
    ch: CHAR; X, Y, i: INTEGER;
    F: Files.File; R: Files.Rider;
    skip: ARRAY 6 OF CHAR;
   BEGIN
    Texts.WriteString(W, name); mod := Modules.modules;
    WHILE (mod # NIL) & (mod.name^ # name) DO mod := mod.next; END;
    IF mod # NIL THEN
      i := 0;
      WHILE (i < 28) & (name[i] > 0X)  DO INC(i) END;
      name[i] := "."; name[i+1] := "O"; name[i+2] := "b"; name[i+3] := "j"; name[i+4] := 0X;
      F := Files.Old(name);
      IF F # NIL THEN
        Texts.WriteString(W, "  SB ="); Texts.WriteHex(W, SYSTEM.ADR(mod.data[mod.sb]));
        Files.Set(R, F, 1); Files.ReadBytes(R, refpos, 4); Files.Set(R, F, refpos+1);
        LOOP Files.Read(R, ch);
          IF R.eof THEN EXIT END;
          IF ch = 0F8X THEN
            Files.ReadBytes(R, i, 2); Files.Read(R, ch);
            IF ch = "$" THEN Files.Read(R, ch); Files.Read(R, ch); EXIT END;
            REPEAT Files.Read(R, ch) UNTIL ch = 0X  (*skip name*)
          ELSIF ch < 0F8X THEN  (*skip object*)
            Files.ReadBytes(R, skip, 6);
            REPEAT Files.Read(R, ch) UNTIL ch = 0X; (*skip name*)
          END
        END;
        IF ~R.eof THEN Locals(R, SYSTEM.ADR(mod.data[mod.sb])); END
      ELSE Texts.WriteString(W, ".Obj not found") END
    ELSE Texts.WriteString(W, " not loaded") END;
    Texts.WriteLn(W); Texts.Append(t, W.buf)
  END OutState;

  PROCEDURE State*;
  VAR T: Texts.Text;
      S: Texts.Scanner;
      V: Viewers.Viewer;
      beg, end, time: LONGINT;
      X, Y: INTEGER;
  BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") THEN
      Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S) END
    END;
    IF S.class = Texts.Name THEN
      T := TextFrames.Text(""); OutState(S.s, T);
      Oberon.AllocateSystemViewer(Oberon.Par.vwr.X, X, Y);
      V := MenuViewers.New(TextFrames.NewMenu("System.State", StandardMenu),
            TextFrames.NewText(T, 0), TextFrames.menuH, X, Y)
    END
  END State;

  PROCEDURE ShowCommands*;
(*
  TYPE Cmds = POINTER TO ARRAY 64 OF RECORD name: Kernel.Name; absentr: (*absolute*) LONGINT END;
  VAR M: Modules.Module;
    comadr, beg, end, time: LONGINT; ch: CHAR;
    T: Texts.Text;
    S: Texts.Scanner;
    V: Viewers.Viewer;
    X, Y, i: INTEGER;
    cmd: Cmds;
*)
  BEGIN
    ASSERT(FALSE);
(*
    Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") THEN
      Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S) END
    END;
    IF S.class = Texts.Name THEN
      M := Modules.ThisMod(S.s);
      IF M # NIL THEN comadr := SYSTEM.VAL(LONGINT, M.cmds);
        T := TextFrames.Text("");
        i := 0;
        WHILE i < M.nofcom DO
          cmd := SYSTEM.VAL(Cmds, M.cmds);
          Texts.WriteString(W, S.s); Texts.Write(W, "."); Texts.WriteString(W, cmd[i].name); Texts.WriteLn(W); INC(i)
        END;
        Texts.Append(T, W.buf);
        Oberon.AllocateSystemViewer(Oberon.Par.vwr.X, X, Y);
        V := MenuViewers.New(TextFrames.NewMenu("System.Commands", StandardMenu),
              TextFrames.NewText(T, 0), TextFrames.menuH, X, Y);
      END
    END
*)
  END ShowCommands;

  PROCEDURE Trap(trap, eip, ebp : LONGINT);
  VAR V: Viewers.Viewer;
      T: Texts.Text;
      RefFile: Files.File;
      R: Files.Rider;
      fp, pc, refpos, dmy, error, page: LONGINT;
      ch, mode: CHAR;
      X, Y, i: INTEGER;
      mod, curmod: Modules.Module;
      name: ARRAY 24 OF CHAR;
      skip: ARRAY 6 OF CHAR;
      procend: LONGINT;
      PrcRef: RECORD found: BOOLEAN; start, end: LONGINT END;

      PROCEDURE AllocateTrapViewer (VAR X, Y: INTEGER);
        VAR DH: INTEGER; fil, bot, alt, max: Display.Frame;
      BEGIN
        DH := Oberon.DisplayHeight(0);
        X := Oberon.SystemTrack(0);
        Viewers.Locate(X, DH, fil, bot, alt, max);
        IF fil.H >= DH DIV 8 THEN Y := DH
          ELSIF max.H > DH DIV 8 THEN Y := max.Y + DH DIV 8
          ELSE Y := max.Y + max.H DIV 2
        END
      END AllocateTrapViewer;

  BEGIN
    ASSERT(FALSE);
(*    
    IF trapped = 0 THEN trapped := 1;
      OriginalBC := Display.Broadcast; Display.Broadcast := NullBC;
      (*FPA.Reset;*)
      T := TextFrames.Text("");
      error := Kernel.err(SYSTEM.ADR(V));  (* Needs address of first local variable *)
      fp := Kernel.fp(); pc := Kernel.pc(SYSTEM.ADR(V));
      IF (error = 7) OR (error = 2) OR (error = 4) THEN DEC(pc, 6) END;
      IF error < 0 THEN error := 10 END;
      mod := SYSTEM.VAL(Modules.Module, Kernel.GetMod(pc));
      Texts.WriteString(W, "TRAP "); Texts.WriteInt(W, error, 1);

      IF error = 6 THEN Texts.WriteLn(W); Texts.WriteString(W, "Division by zero or Illegal instruction");
      ELSIF error = 7 THEN Texts.WriteLn(W); Texts.WriteString(W, "Overflow ");
      ELSIF error = 4 THEN
        IF page = -1 THEN Texts.WriteLn(W); Texts.WriteString(W, "General protection fault ")
        ELSE Texts.WriteLn(W); Texts.WriteString(W, "Page fault at address "); Texts.WriteInt(W, page, 7) END
      ELSIF error = 3 THEN Texts.WriteLn(W); Texts.WriteString(W, "FPU error ");
      ELSIF error = 2 THEN Texts.WriteLn(W); Texts.WriteString(W, "NIL reference, illegal address ")
      ELSIF error = 24 THEN Texts.WriteLn(W); Texts.WriteString(W, "Keyboard interrupt ");
      ELSIF error = 8 THEN Texts.WriteLn(W); Texts.WriteString(W, "Breakpoint ");
      ELSIF error = 10 THEN Texts.WriteLn(W); Texts.WriteString(W, "Reference to unloaded module ");
      END;
      Texts.WriteLn(W); curmod := NIL;
      LOOP
        IF mod = NIL THEN EXIT END;
        Texts.WriteString(W, mod.name);
        IF mod # curmod THEN
          (*load obj file*) i := 0;
          WHILE mod.name[i] > 0X DO name[i] := mod.name[i]; INC(i) END;
          name[i] := "."; name[i+1] := "O"; name[i+2] := "b"; name[i+3] := "j"; name[i+4] := 0X;
          RefFile := Files.Old(name);
          IF RefFile = NIL THEN curmod := NIL; Texts.WriteString(W, ".Obj not found"); Texts.WriteLn(W)
          ELSE curmod := mod; Files.Set(R, RefFile, 1);
            Files.ReadBytes(R, refpos, 4); Files.Set(R, RefFile, refpos); Files.Read(R, ch);
            IF ch = 8AX THEN INC(refpos)
            ELSE curmod := NIL;
              Texts.WriteString(W, "no reference information:"); Texts.WriteInt(W, pc - mod.code, 7); Texts.WriteLn(W);
            END;
          END
        END;
        IF curmod # NIL THEN  (*find procedure*)
          PrcRef.found := FALSE; Files.Set(R, RefFile, refpos);
          LOOP Files.Read(R, ch);
            IF R.eof THEN EXIT END;
            IF ch = 0F8X THEN (*start proc*)
              procend := 0; Files.ReadBytes(R, procend, 2);
              IF pc < mod.code + procend THEN
                IF ~PrcRef.found OR (procend < PrcRef.end) THEN PrcRef.found := TRUE; PrcRef.end := procend;
                  PrcRef.start := Files.Pos(R)
                END
              END;
              REPEAT Files.Read(R, ch) UNTIL ch = 0X; (*skip name*)
            ELSIF ch < 0F8X THEN (*skip object*)
              Files.ReadBytes(R, skip, 5);  (* first byte already read *)
              REPEAT Files.Read(R, ch) UNTIL ch = 0X; (*skip name*)
            END
          END;
          IF PrcRef.found THEN Files.Set(R, RefFile, PrcRef.start);
            Texts.Write(W, "."); Files.Read(R, ch);
            WHILE ch > 0X DO Texts.Write(W, ch); Files.Read(R, ch) END;
            Texts.WriteString(W, "  PC ="); Texts.WriteInt(W, pc-mod.code, 6);
            Locals(R, fp)
          END
        END;
        SYSTEM.GET(fp+4, pc); SYSTEM.GET(fp, fp); (* return addr from stack *)
        IF fp >= Kernel.StackOrg THEN EXIT END; (* not called from stack *)
        mod:=SYSTEM.VAL(Modules.Module, Kernel.GetMod(pc))
      END; (*LOOP*)
      Texts.Append(T, W.buf);
      AllocateTrapViewer(X, Y);
      V := MenuViewers.New(TextFrames.NewMenu("System.Trap", StandardMenu),
        TextFrames.NewText(T, 0), TextFrames.menuH, X, Y);
    ELSIF trapped = 1 THEN trapped := 2;
       T := TextFrames.Text("");
      fp := Kernel.fp(); pc := Kernel.pc(SYSTEM.ADR(V));
      Texts.WriteString(W, "REC TRAP "); Texts.WriteInt(W, Kernel.err(SYSTEM.ADR(V)), 3);
      Texts.WriteLn(W); Texts.Append(T, W.buf);
      AllocateTrapViewer(X, Y);
      V := MenuViewers.New(TextFrames.NewMenu("System.Trap", StandardMenu),
        TextFrames.NewText(T, 0), TextFrames.menuH, X, Y);
    END;
    Display.Broadcast := OriginalBC; trapped := 0;
    Kernel.GC;
*)
  END Trap;

  PROCEDURE OpenViewers;
  VAR logV, toolV: Viewers.Viewer; t, d: LONGINT; X, Y: INTEGER;
  BEGIN
    Oberon.GetClock(t, d);
    Texts.WriteString(W, "System.Time");
    Texts.WriteDate(W, t, d);
    Texts.WriteLn(W);
    Texts.WriteString(W,"Oberon (tm) System 3  Version 2.0");  Texts.WriteLn(W);
    Texts.Append(Oberon.Log, W.buf);

    Oberon.AllocateSystemViewer(0, X, Y);
    logV := MenuViewers.New(
      TextFrames.NewMenu("System.Log", LogMenu),
      TextFrames.NewText(Oberon.Log, 0),
      TextFrames.menuH,
      X, Y);
    Oberon.AllocateSystemViewer(0, X, Y);
    toolV := MenuViewers.New(
      TextFrames.NewMenu("System.Tool", StandardMenu),
      TextFrames.NewText(TextFrames.Text("System.Tool"), 0),
      TextFrames.menuH,
      X, Y);
  END OpenViewers;

  PROCEDURE Quit*;
  BEGIN
    ASSERT(FALSE); (*Quit*)
  END Quit;

  PROCEDURE InitColors;
  BEGIN
    Display.SetColor(0, 0, 0, 0);
    Display.SetColor(1, 255, 0, 0);
    Display.SetColor(2, 0, 255, 0);
    Display.SetColor(3, 0, 0, 255);
    Display.SetColor(4, 255, 0, 255);
    Display.SetColor(5, 255, 255, 0);
    Display.SetColor(6, 0, 255, 255);
    Display.SetColor(7, 170, 0, 0);
    Display.SetColor(8, 0, 153, 0);
    Display.SetColor(9, 0,  0, 153);
    Display.SetColor(10, 119, 0, 204);
    Display.SetColor(11, 187, 136, 0);
    Display.SetColor(12, 136, 136, 136);
    Display.SetColor(13, 190, 190, 190);
    Display.SetColor(14, 221, 221, 221);
    Display.SetColor(15, 255, 255, 255);
  END InitColors;

BEGIN
  Kernel.InstallLoop(Oberon.Loop);
  trapped := 0;
(*  Kernel.InstallTrap(Trap);
*)
  Texts.OpenWriter(W);
  Oberon.Log := TextFrames.Text("");
  InitColors;
  OpenViewers;
END System.



