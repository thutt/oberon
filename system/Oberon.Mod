MODULE Oberon; (*JG 22.7.94*)

  IMPORT Kernel, Modules, Display, Input, Objects, Viewers, Fonts, Texts, Console;

  CONST

    (*message ids*)
    defocus* = 0; neutralize* = 1; mark* = 2; (*ControlMsg*)
    consume* = 0; track* = 1; (*InputMsg*)
    get* = 0; set* = 1; reset* = 2; (*CaretMsg id/ SelectMsg id*)
    drop* = 0; integrate* = 1; (*ConsumeMsg id*)

    GCInterval = 100000; ActVal = 5000;

    ESC = 1BX; SETUP = 0A4X;

  TYPE

    Painter* = PROCEDURE (x, y: INTEGER);
    Marker* = RECORD
      Fade*, Draw*: Painter;
    END;
  
    Cursor* = RECORD
      marker*: Marker;
      on*: BOOLEAN;
      X*, Y*: INTEGER;
    END;

    ParList* = POINTER TO ParRec;

    ParRec* = RECORD
      vwr*: Viewers.Viewer;
      frame*: Display.Frame;
      obj*: Objects.Object;
      text*: Texts.Text;
      pos*: LONGINT
    END;

    ControlMsg* = RECORD (Display.FrameMsg)
      id*, X*, Y*: INTEGER
    END;

    InputMsg* = RECORD (Display.FrameMsg)
      id*: INTEGER;
      keys*: SET;
      X*, Y*: INTEGER;
      ch*: CHAR;
      fnt*: Fonts.Font;
      col* : LONGINT;
      voff*: SHORTINT
    END;

    CaretMsg* = RECORD (Display.FrameMsg)
      id*: INTEGER;
      car*: Display.Frame;
      text*: Texts.Text;
      pos*: LONGINT
    END;

    SelectMsg* = RECORD (Display.FrameMsg)
      id*: INTEGER;
      time*: LONGINT;
      sel*: Display.Frame;
      text*: Texts.Text;
      beg*, end*: LONGINT
    END;

    ConsumeMsg* = RECORD (Display.FrameMsg)
      id*: INTEGER;
      u*, v*: INTEGER;
      text*: Texts.Text;
      beg*, end*: LONGINT
    END;

    RecallMsg* = RECORD (Display.FrameMsg)
    END;

    Task* = POINTER TO TaskDesc;

    Handler* = PROCEDURE (me: Task);

    TaskDesc* = RECORD
      next: Task;
      time*: LONGINT;
      safe*: BOOLEAN;
      handle*: Handler
    END;

  VAR
    User*: ARRAY 8 OF CHAR;
    Password*: LONGINT;

  Arrow*, Star*: Marker;
  Mouse*, Pointer*: Cursor;

    Log*: Texts.Text;
    Par*: ParList; (*actual parameters*)

    CurTask, NextTask: Task;

    CurFnt*: Fonts.Font;
    CurCol* : LONGINT;
    CurOff*: SHORTINT;

    DW, DH, CL, H0, H1, H2, H3: INTEGER;

    GCTask: Task; (* garbage collection task *)
    Mod: Modules.Module;

    ColTab: ARRAY 16 OF RECORD r, g, b: INTEGER END;
    ScreenOn, Inverted: BOOLEAN;

  (*user identification*)

  PROCEDURE Code(VAR s: ARRAY OF CHAR): LONGINT;
    VAR i: INTEGER; a, b, c: LONGINT;
  BEGIN
    a := 0; b := 0; i := 0;
    WHILE s[i] # 0X DO
      c := b; b := a; a := (c MOD 509 + 1) * 127 + ORD(s[i]);
      INC(i)
    END;
    IF b >= 32768 THEN b := b - 65536 END;
    RETURN b * 65536 + a
  END Code;

  PROCEDURE SetUser* (VAR user, password: ARRAY OF CHAR);
  BEGIN COPY(user, User); Password := Code(password)
  END SetUser;

  (*clocks*)

  PROCEDURE GetClock* (VAR t, d: LONGINT);
  BEGIN Kernel.GetClock(t, d);
  END GetClock;

  PROCEDURE SetClock* (t, d: LONGINT);
  BEGIN Kernel.SetClock(t, d);
  END SetClock;

  PROCEDURE Time* (): LONGINT;
  BEGIN RETURN Input.Time()
  END Time;

  (*cursor handling*)

    PROCEDURE FlipArrow (X, Y: INTEGER);
    BEGIN
(*
      IF X < CL THEN
        IF X > DW - 15 THEN X := DW - 15 END
      ELSE
        IF X > CL + DW - 15 THEN X := CL + DW - 15 END
      END;
      IF Y < 15 THEN Y := 15 ELSIF Y > DH THEN Y := DH END;
      Display.CopyPattern(Display.FG, Display.arrow, X, Y - 15, Display.invert)
*)
    END FlipArrow;

    PROCEDURE FlipStar (X, Y: INTEGER);
    BEGIN
      IF X < CL THEN
        IF X < 7 THEN X := 7 ELSIF X > DW - 8 THEN X := DW - 8 END
      ELSE
        IF X < CL + 7 THEN X := CL + 7 ELSIF X > CL + DW - 8 THEN X := CL + DW - 8 END
      END ;
      IF Y < 7 THEN Y := 7 ELSIF Y > DH - 8 THEN Y := DH - 8 END;
      Display.CopyPattern(Display.FG, Display.star, X - 7, Y - 7, Display.invert)
    END FlipStar;

    PROCEDURE OpenCursor* (VAR c: Cursor);
    BEGIN c.on := FALSE; c.X := 0; c.Y := 0
    END OpenCursor;

    PROCEDURE FadeCursor* (VAR c: Cursor);
    BEGIN IF c.on THEN c.marker.Fade(c.X, c.Y); c.on := FALSE END
    END FadeCursor;

    PROCEDURE DrawCursor* (VAR c: Cursor; VAR m: Marker; X, Y: INTEGER);
    BEGIN
      IF c.on & ((X # c.X) OR (Y # c.Y) OR (m.Draw # c.marker.Draw)) THEN
            c.marker.Fade(c.X, c.Y); c.on := FALSE
          END;
      IF ~c.on THEN
            m.Draw(X, Y); c.marker := m; c.X := X; c.Y := Y; c.on := TRUE
          END
    END DrawCursor;

(*display management*)

    PROCEDURE Defocus*;
      VAR M: ControlMsg;
    BEGIN M.F := NIL; M.id := defocus; Display.Broadcast(M)
    END Defocus;

    PROCEDURE RemoveMarks* (X, Y, W, H: INTEGER);
    BEGIN
      IF (Mouse.X > X - 16) & (Mouse.X < X + W + 16) & (Mouse.Y > Y - 16) & (Mouse.Y < Y + H + 16) THEN
          FadeCursor(Mouse)
      END;
      IF (Pointer.X > X - 8) & (Pointer.X < X + W + 8) & (Pointer.Y > Y - 8) & (Pointer.Y < Y + H + 8) THEN
          FadeCursor(Pointer)
      END
    END RemoveMarks;

    PROCEDURE *HandleFiller (V: Objects.Object; VAR M: Objects.ObjMsg);
    BEGIN
      WITH V: Viewers.Viewer DO
        IF M IS InputMsg THEN
          WITH M: InputMsg DO
            IF M.id = track THEN DrawCursor(Mouse, Arrow, M.X, M.Y) END
          END;
        ELSIF M IS ControlMsg THEN
           WITH M: ControlMsg DO
             IF M.id = mark THEN
               IF (M.X >= V.X) & (M.X < V.X + V.W) & (M.Y >= V.Y) & (M.Y < V.Y + V.H) THEN
                 DrawCursor(Pointer, Star, M.X, M.Y)
               END
             END
           END
        ELSIF M IS Display.ControlMsg THEN
          WITH M: Display.ControlMsg DO
            IF (M.id = Display.restore) & (V.W > 0) & (V.H > 0) THEN
              RemoveMarks(V.X, V.Y, V.W, V.H);
              Display.ReplConst(Display.BG, V.X, V.Y, V.W, V.H, Display.replace)
            END
          END
        ELSIF M IS Display.ModifyMsg THEN
          WITH M: Display.ModifyMsg DO
            IF (M.F = V) & (M.id = Display.extend) THEN
              RemoveMarks(V.X, M.Y, V.W, V.Y - M.Y);
              Display.ReplConst(Display.BG, V.X, M.Y, V.W, V.Y - M.Y, Display.replace)
            END
          END
        END
      END
    END HandleFiller;

    PROCEDURE OpenDisplay* (UW, SW, H: INTEGER); (* UW<=>UserWidth, SW<=>SystemWidth *)
       VAR Filler: Viewers.Viewer;
    BEGIN
       Display.ReplConst(Display.BG, Viewers.curW, 0, UW + SW, H, Display.replace);
       NEW(Filler); Filler.handle := HandleFiller;
       Viewers.InitTrack(UW, H, Filler); (*init user track*)
       NEW(Filler); Filler.handle := HandleFiller;
       Viewers.InitTrack(SW, H, Filler) (*init system track*)
    END OpenDisplay;

    PROCEDURE DisplayWidth* (X: INTEGER): INTEGER;
    BEGIN RETURN DW
    END DisplayWidth;

    PROCEDURE DisplayHeight* (X: INTEGER): INTEGER;
    BEGIN RETURN DH
    END DisplayHeight;

    PROCEDURE OpenTrack* (X, W: INTEGER);
       VAR Filler: Viewers.Viewer;
    BEGIN
       NEW(Filler); Filler.handle := HandleFiller;
       Viewers.OpenTrack(X, W, Filler)
    END OpenTrack;

    PROCEDURE UserTrack* (X: INTEGER): INTEGER;
    BEGIN RETURN X DIV DW * DW
    END UserTrack;

    PROCEDURE SystemTrack* (X: INTEGER): INTEGER;
    BEGIN RETURN X DIV DW * DW + DW DIV 8 * 5
    END SystemTrack;

    PROCEDURE UY (X: INTEGER): INTEGER;
      VAR fil, bot, alt, max: Display.Frame;
    BEGIN
      Viewers.Locate(X, 0, fil, bot, alt, max);
      IF fil.H >= DH DIV 8 THEN RETURN DH END;
      RETURN max.Y + max.H DIV 2
    END UY;

    PROCEDURE AllocateUserViewer* (DX: INTEGER; VAR X, Y: INTEGER);
    BEGIN
      IF Pointer.on THEN X := Pointer.X; Y := Pointer.Y
        ELSE X := DX DIV DW * DW; Y := UY(X)
      END
    END AllocateUserViewer;

    PROCEDURE SY (X: INTEGER): INTEGER;
      VAR fil, bot, alt, max: Display.Frame;
    BEGIN
      Viewers.Locate(X, DH, fil, bot, alt, max);
      IF fil.H >= DH DIV 8 THEN RETURN DH END;
      IF max.H >= DH - H0 THEN RETURN max.Y + H3 END;
      IF max.H >= H3 - H0 THEN RETURN max.Y + H2 END;
      IF max.H >= H2 - H0 THEN RETURN max.Y + H1 END;
      IF max # bot THEN RETURN max.Y + max.H DIV 2 END;
      IF bot.H >= H1 THEN RETURN bot.H DIV 2 END;
      RETURN alt.Y + alt.H DIV 2
    END SY;

    PROCEDURE AllocateSystemViewer* (DX: INTEGER; VAR X, Y: INTEGER);
    BEGIN
      IF Pointer.on THEN X := Pointer.X; Y := Pointer.Y
        ELSE X := DX DIV DW * DW + DW DIV 8 * 5; Y := SY(X)
      END
    END AllocateSystemViewer;

    PROCEDURE MarkedViewer* (): Viewers.Viewer;
    BEGIN RETURN Viewers.This(Pointer.X, Pointer.Y)
    END MarkedViewer;

  (*command interpretation*)

    PROCEDURE Call* (name: ARRAY OF CHAR; par: ParList; new: BOOLEAN; VAR res: INTEGER);
      VAR Mod: Modules.Module; P: Modules.Command; i, j: INTEGER;
    BEGIN res := 1;
      i := 0; j := 0;
      WHILE name[j] # 0X DO
        IF name[j] = "." THEN i := j END;
        INC(j)
      END;
      IF i > 0 THEN
        name[i] := 0X;
        IF new THEN Modules.Free(name, FALSE) END;
        Mod := Modules.ThisMod(name);
        IF Modules.res = 0 THEN
          INC(i); j := i;
          WHILE name[j] # 0X DO name[j - i] := name[j]; INC(j) END;
          name[j - i] := 0X;
          P := Modules.ThisCommand(Mod, name);
          IF Modules.res = 0 THEN
            Par := par; Par.vwr := Viewers.This(par.frame.X, par.frame.Y); P; res := 0
          ELSE res := Modules.res
          END
        ELSE res := Modules.res
        END
      END
    END Call;

    PROCEDURE GetSelection* (VAR text: Texts.Text; VAR beg, end, time: LONGINT);
      VAR M: SelectMsg;
    BEGIN
        M.F := NIL; M.id := get; M.time := -1; Display.Broadcast(M);
        text := M.text; beg := M.beg; end := M.end; time := M.time
    END GetSelection;

    PROCEDURE GC(me: Task);
      VAR T: LONGINT;
    BEGIN
      Kernel.GC; T := Input.Time();
      IF  T <= MAX(LONGINT) - GCInterval THEN GCTask.time := T + GCInterval
      ELSE GCTask.time := 0
      END
    END GC;

    PROCEDURE Install* (T: Task);
      VAR t: Task;
    BEGIN t := NextTask;
      WHILE (t.next # NextTask) & (t.next # T) DO t := t.next END;
      IF t.next # T THEN T.next := t.next; t.next := T END
    END Install;

    PROCEDURE Remove* (T: Task);
      VAR t: Task;
    BEGIN t := NextTask;
      WHILE (t.next # NextTask) & (t.next # T) DO t := t.next END;
      IF t.next = T THEN t.next := t.next.next;
        IF NextTask = T THEN NextTask := NextTask.next END
      END
    END Remove;

    PROCEDURE Collect*;
    BEGIN GCTask.time := Input.Time()
    END Collect;

    PROCEDURE SetFont* (fnt: Fonts.Font);
    BEGIN CurFnt := fnt
    END SetFont;

    PROCEDURE SetColor* (col: Display.COLOR);
    BEGIN CurCol := col
    END SetColor;

    PROCEDURE SetOffset* (voff: SHORTINT);
    BEGIN CurOff := voff
    END SetOffset;

    PROCEDURE Quit;
    VAR P: Modules.Command;
    BEGIN
      P := Modules.ThisCommand(Modules.ThisMod("System"), "Quit"); P
    END Quit;

    PROCEDURE SwitchColors;
      VAR i: INTEGER;
    BEGIN
      IF ScreenOn THEN
        FOR i := 0 TO 15 DO Display.GetColor(SHORT(i), ColTab[i].r, ColTab[i].g, ColTab[i].b) END;
        FOR i := 0 TO 15 DO Display.SetColor(SHORT(i), 0, 0, 0) END;
       ELSE
        FOR i := 0 TO 15 DO Display.SetColor(SHORT(i), ColTab[i].r, ColTab[i].g, ColTab[i].b) END;
       END;
       ScreenOn := ~ScreenOn
    END SwitchColors;

  PROCEDURE ResetColors;
  BEGIN
    Display.SetColor(15, 0, 0, 0); Display.SetColor(1, 255, 0, 0);
    Display.SetColor(2, 0, 255, 0); Display.SetColor(3, 0, 0, 255);
    Display.SetColor(4, 255, 0, 255); Display.SetColor(5, 255, 255, 0);
    Display.SetColor(6, 0, 255, 255); Display.SetColor(7, 170, 0, 0);
    Display.SetColor(8, 0, 153, 0); Display.SetColor(9, 0,  0, 153);
    Display.SetColor(10, 119, 0, 204); Display.SetColor(11, 187, 136, 0);
    Display.SetColor(12, 136, 136, 136); Display.SetColor(13, 190, 190, 190);
    Display.SetColor(14, 221, 221, 221); Display.SetColor(0, 255, 255, 255);
    Inverted := FALSE; ScreenOn := TRUE
  END ResetColors;

    PROCEDURE InvColors;
    BEGIN
      IF ~Inverted THEN Display.SetColor(0, 0, 0, 0); Display.SetColor(15, 255, 255, 255);
      ELSE Display.SetColor(15, 0, 0, 0); Display.SetColor(0, 255, 255, 255) END;
      Inverted := ~Inverted;
    END InvColors;

  PROCEDURE LoopProcess;
    VAR V: Viewers.Viewer; M: InputMsg; N: ControlMsg;
      X, Y: INTEGER; keys: SET; ch: CHAR;
  BEGIN
    IF (CurTask # NIL) & ~CurTask.safe THEN Remove(CurTask) END;
    Input.Mouse(keys, X, Y);
    IF Input.Available() > 0 THEN Input.Read(ch);
      IF ch < 0F0X THEN
        IF ch = ESC THEN
          N.F := NIL; N.id := neutralize; Display.Broadcast(N);
          FadeCursor(Pointer)
        ELSIF ch = SETUP THEN
          N.F := NIL; N.id := mark; N.X := X; N.Y := Y; Display.Broadcast(N)
        ELSIF ch = 99X THEN Quit
        ELSIF ch = 95X THEN SwitchColors
        ELSIF ch = 97X THEN ResetColors
        ELSIF ch = 9AX THEN InvColors
        ELSE
          M.F := NIL; M.id := consume; M.ch := ch; M.fnt := CurFnt; M.col := CurCol; M.voff := CurOff;
          Display.Broadcast(M);
          DEC(GCTask.time, ActVal)
        END
      END;
      Input.Mouse(keys, X, Y)
    ELSIF keys # {} THEN M.F := NIL; M.id := track;
      REPEAT
        M.keys := keys; M.X := X; M.Y := Y;
        M.dlink := NIL; M.x := 0; M.y := 0;
        M.res := MIN(INTEGER); Objects.Stamp(M);
        V := Viewers.This(M.X, M.Y);
        V.handle(V, M);
        Input.Mouse(keys, X, Y);
      UNTIL keys = {};
      DEC(GCTask.time, ActVal)
    ELSE (*keys = {}*)
      M.F := NIL; M.id := track; M.keys := keys; M.X := X; M.Y := Y;
      M.dlink := NIL; M.x := 0; M.y := 0;
      M.res := MIN(INTEGER);
      Objects.Stamp(M);
      V := Viewers.This(X, Y);
      V.handle(V, M);
      Input.Mouse(keys, X, Y);
      IF (keys = {}) & (X = M.X) & (Y = M.Y) & (Input.Available() = 0) THEN
        CurTask := NextTask; NextTask := CurTask.next;
        IF CurTask.time <= Input.Time() THEN
          CurTask.handle(CurTask); CurTask := NIL;
        END;
        Input.Mouse(keys, X, Y);
      END;
    END;
  END LoopProcess;

  PROCEDURE Loop*;
  BEGIN Console.Str('Oberon.Loop is not supported in this system');Console.Ln;
  END Loop;

  PROCEDURE Init;
  BEGIN
(*
    User[0] := 0X;
    Arrow.Fade := FlipArrow; Arrow.Draw := FlipArrow;
    Star.Fade := FlipStar; Star.Draw := FlipStar;
    OpenCursor(Mouse); OpenCursor(Pointer);

    DW := Display.Width; DH := Display.Height; CL := 0;
    H3 := DH - DH DIV 3;
    H2 := H3 - H3 DIV 2;
    H1 := DH DIV 5;
   H0 := DH DIV 10;

    OpenDisplay(DW DIV 8 * 5, DW DIV 8 * 3, DH);

    NEW(GCTask);
    GCTask.handle := GC;
    GCTask.safe := TRUE;
    NextTask := GCTask;
    NextTask.next := NextTask;
    Collect;

    Fonts.Default := Fonts.This("Syntax10.Scn.Fnt");
    ASSERT(Fonts.Default # NIL);
    CurFnt := Fonts.Default;
    CurCol := Display.FG;
    CurOff := 0;

    Mod := Modules.ThisMod("System");
    ASSERT(Mod # NIL);
    ScreenOn := TRUE; Inverted := FALSE;
*)
  END Init;

BEGIN Init;
END Oberon.
