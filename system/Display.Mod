MODULE Display;
  IMPORT SYSTEM, Objects, Console;
  
  CONST (* drawing modes *)
    replace* = MAX(SHORTINT); paint* = MAX(SHORTINT) - 1; invert* = MAX(SHORTINT) - 2;
    MaxPatternWidth = 32; MaxPatternHeight = 32;
    NofOberonColors = 16;

    (* Minimum set of colors defined by the host system.  
       A Display driver can provide more colors if desired, but it must at least provide
       `ColMinColors' colors to the display system; otherwise host colors will not be 
       supported: asking for a host color in this case will always return `white'.
       
       Note: The rules for returning `white' allow a display driver and client software to 
       take advantage of additional colors while not crashing on a less capable OS, but it's not 
       recommended to extend the color table beyond what is defined.
    *)
    ColBlack* = 0; ColWhite* = 1;
    ColWindow* = 2; ColWindowBg* = 3; 
    ColMenu* = 4; ColMenuBg* = 5;
    ColWindowText* = 6;
    ColActiveBorder* = 7; ColInactiveBorder* = 8;
    ColMinColors* = 9;

  TYPE
    ADDRESS = LONGINT;
    
    (* COLOR: a host color, transformed into the following attributes
        0..7: red
        8..15: green
        16..23:  blue
        24..31: extended attributes
        
        For a normal color : bits 24..31 should be 0.
        For an Oberon color: bits 24..31 contain the index into the Oberon
                             color table (which is a table of Windows colors)
                             Standard Oberon has 16 colors
    *)
    COLOR* = LONGINT;

    (* DisplayColors: Driver-supplied array of colors supported by the display *)
    DisplayColors = POINTER TO ARRAY OF COLOR;
    
    Frame* = POINTER TO FrameDesc;
    Font = POINTER TO ARRAY OF SYSTEM.BYTE;

    Pattern* = ADDRESS; (* BYTE[0] = w, BYTE[1] = h, [2..LEN-1] = pattern data (bit 0 is leftmost on the display) *)

    FrameDesc* = RECORD (Objects.ObjDesc)
      X*, Y*, W*, H*: INTEGER;
      dsc*, next*: Frame;
    END;

    FrameMsg* = RECORD (Objects.ObjMsg)
      F*: Frame; (*target*)
      x*, y*, res*: INTEGER
    END;
    
  CONST
    remove* = 0; suspend* = 1; restore* = 2; (*ControlMsg id*)

  TYPE
    ControlMsg* = RECORD (FrameMsg)
      id*: INTEGER
    END;
    
  CONST
    reduce* = 0; extend* = 1; move* = 2; (*ModifyMsg id*)
    display* = 0; state* = 1; (*ModifyMsg mode*)

  TYPE
    ModifyMsg* = RECORD (FrameMsg)
      id*, mode*: INTEGER;
      dX*, dY*, dW*, dH*: INTEGER;
      X*, Y*, W*, H*: INTEGER
    END;
    
  CONST
    frame* = 0; area* = 1; (*DisplayMsg id*)

  TYPE
    DisplayMsg* = RECORD (FrameMsg)
      id*: INTEGER;
      u*, v*, w*, h*: INTEGER
    END;

  CONST    
    contents* = 0; view* = 1; (*PrintMsg id*)

  TYPE
    PrintMsg* = RECORD (FrameMsg)
      id*, pageno*: INTEGER
    END;

    LocateMsg* = RECORD (FrameMsg)
      loc*: Frame;
      X*, Y*, u*, v*: INTEGER
    END;
    
  CONST
    get* = 0; set* = 1; reset* = 2; (*SelectMsg id*)

  TYPE
    SelectMsg* = RECORD (FrameMsg)
      id*: INTEGER;
      time*: LONGINT;
      sel*: Frame;
      obj*: Objects.Object
    END;
    
  CONST
    drop* = 0; integrate* = 1; (*ConsumeMsg id*)

  TYPE
    ConsumeMsg* = RECORD (FrameMsg)
      id*: INTEGER;
      u*, v*: INTEGER;
      obj*: Objects.Object
    END;
    
  TYPE (* DriverAPI *)
    DriverAPI* = POINTER TO DriverAPIDesc;
    DriverAPIDesc* = RECORD
      WorldWidth*     : INTEGER; 
      WorldHeight*    : INTEGER; (* physical display size *)

      Height*, Width* : INTEGER; (* current window size *)

      OSColors*       : DisplayColors; (* value for HostColors *)

      Map*            : PROCEDURE(X: INTEGER): LONGINT;
      DisplayBlock*   : PROCEDURE(B: LONGINT; DX, DY, W, H, SX, SY, mode: INTEGER);
      SetMode*        : PROCEDURE(X: INTEGER; s: SET);
      ResetClip*      : PROCEDURE;
      SetClip*        : PROCEDURE(x, y, w, h: INTEGER);
      GetClip*        : PROCEDURE(VAR x, y, w, h : INTEGER);
      Intersect*      : PROCEDURE(VAR (* in; r/o *) r0, r1 : FrameDesc; VAR (* out *) r : FrameDesc);
      Dot*            : PROCEDURE(col : COLOR; X, Y : INTEGER; mode : SHORTINT);
      ReplConst*      : PROCEDURE(col: COLOR; X, Y, W, H : INTEGER; mode: SHORTINT);
      CopyBlock*      : PROCEDURE(SX, SY, W, H, DX, DY : INTEGER; mode : SHORTINT);
      Line*           : PROCEDURE(col : COLOR; X0, Y0, X1, Y1 : INTEGER; mode : SHORTINT);
      CopyPattern*    : PROCEDURE(col: COLOR; pat: Pattern; X, Y : INTEGER; mode: SHORTINT);
      FillPattern*    : PROCEDURE(col: COLOR; pat: Pattern; pX, pY, X, Y, W, H : INTEGER; mode: SHORTINT);
      Circle*         : PROCEDURE(col : COLOR; X, Y, R : INTEGER; mode: SHORTINT);
      Ellipse*        : PROCEDURE(col : COLOR; X, Y, A, B : INTEGER; mode: SHORTINT);
      RGB*            : PROCEDURE(red, green, blue : INTEGER) : COLOR;
      GetRGB*         : PROCEDURE(col : COLOR; VAR red, green, blue : INTEGER);
      ReplPattern*    : PROCEDURE(col: COLOR; pat: Pattern; X, Y, W, H : INTEGER; mode : SHORTINT);
    END;

  TYPE
    Handler* = PROCEDURE (f: Frame; VAR msg: FrameMsg);
    MsgProc* = PROCEDURE (VAR M: FrameMsg);

  VAR
    api : DriverAPI;
    WorldWidth-, WorldHeight- : INTEGER; (* physical display size *)
    Height-, Width- : INTEGER; (* current window size *)
    Unit- : LONGINT; (*RasterUnit = Unit/36000 mm (dot pitch * 36000 <= Unit) *)
    white-, black- : COLOR;
    BG-, FG- : COLOR; (*background, foreground*)
    StandardPat : ARRAY 10 OF Pattern;
    arrow-, star-, cross-, downArrow-, hook-, grey0-, grey1-, grey2-, ticks-, solid- : Pattern;
    Broadcast*: MsgProc;
    OberonColors : ARRAY NofOberonColors OF COLOR;
    HostColors : DisplayColors; (* inv: (HostColors = NIL) OR (LEN(HostColors) >= ColMinColors) *)
  
  PROCEDURE min(x, y : INTEGER) : INTEGER;
  BEGIN IF x < y THEN RETURN x ELSE RETURN y; END;
  END min;

  PROCEDURE Map*(X: INTEGER): LONGINT;
  BEGIN IF api # NIL THEN RETURN api.Map(X); ELSE RETURN 0; END;
  END Map;
  
  PROCEDURE GetDim*(pat: Pattern; VAR w, h: INTEGER);
    VAR b : SHORTINT;
  BEGIN SYSTEM.GET(pat, b); w := b; SYSTEM.GET(pat + 1, b); h := b;
  END GetDim;

  PROCEDURE GetOberonColor*(col : SHORTINT) : COLOR;
  BEGIN RETURN ASH(LONG(LONG(col)), 24);
  END GetOberonColor;

  PROCEDURE SetColor*(col : COLOR; red, green, blue: INTEGER);
  BEGIN
    IF (0 <= col) & (col < LEN(OberonColors)) THEN 
      IF api # NIL THEN OberonColors[col] := api.RGB(red, green, blue); 
      ELSE OberonColors[col] := 0;
      END;
    END;
  END SetColor;

  PROCEDURE GetColor*(col: COLOR; VAR red, green, blue: INTEGER);
  BEGIN
    IF (0 <= col) & (col < LEN(OberonColors)) THEN 
      IF api # NIL THEN api.GetRGB(OberonColors[col], red, green, blue);
      ELSE red := 0; green := 0; blue := 0;
      END;
    ELSE api.GetRGB(col, red, green, blue);
    END;
  END GetColor;

  PROCEDURE DisplayBlock*(B:LONGINT; DX, DY, W, H, SX, SY, mode:INTEGER);
  BEGIN IF api # NIL THEN api.DisplayBlock(B, DX, DY, W, H, SX, SY, mode); END;
  END DisplayBlock;

  PROCEDURE SetMode*(X: INTEGER; s: SET);
  BEGIN IF api # NIL THEN api.SetMode(X, s); END;
  END SetMode;
  
  PROCEDURE ResetClip*;
  BEGIN IF api # NIL THEN api.ResetClip; END;
  END ResetClip;
  
  PROCEDURE SetClip*(x, y, w, h: INTEGER); (* IF (x + w > Width) OR (y  + h > Height-1) OR (y < -330) OR (x < 0)  THEN HALT(40) END;*)
  BEGIN IF api # NIL THEN api.SetClip(x, y, w, h); END;
  END SetClip;

  PROCEDURE GetClip*(VAR x, y, w, h : INTEGER);
  BEGIN
    IF api # NIL THEN api.GetClip(x, y, w, h); 
    ELSE x := 0; y := 0; w := -1; h := -1;
    END;
  END GetClip;

  PROCEDURE AdjustClip*(X, Y, W, H: INTEGER);
  BEGIN ResetClip; SetClip(X, Y, W, H);
  END AdjustClip;
  
  PROCEDURE Intersect*(VAR (* in; r/o *) r0, r1 : FrameDesc; VAR (* out *) r : FrameDesc);
  BEGIN IF api # NIL THEN api.Intersect(r0, r1, r); END;
  END Intersect;

  PROCEDURE Dot*(col : COLOR; X, Y : INTEGER; mode : SHORTINT);
  BEGIN IF api # NIL THEN api.Dot(col, X, Y, mode); END;
  END Dot;

  PROCEDURE ReplConst*(col: COLOR; X, Y, W, H : INTEGER; mode: SHORTINT);
  BEGIN IF api # NIL THEN api.ReplConst(col, X, Y, W, H, mode); END;
  END ReplConst;
  
  PROCEDURE CopyBlock*(SX, SY, W, H, DX, DY : INTEGER; mode : SHORTINT);
  BEGIN IF api # NIL THEN api.CopyBlock(SX, SY, W, H, DX, DY, mode); END;
  END CopyBlock;

  PROCEDURE Line*(col : COLOR; X0, Y0, X1, Y1 : INTEGER; mode : SHORTINT); (* from from (X0, Y0) to [X1, Y1] *)
  BEGIN IF api # NIL THEN api.Line(col, X0, Y0, X1, Y1, mode); END;
  END Line;

  PROCEDURE MakeColor*(red, green, blue : INTEGER) : COLOR; (* pre: (red, green, blue) IN {0..255} *)
  BEGIN IF api # NIL THEN RETURN api.RGB(red, green, blue); ELSE RETURN 0; END;
  END MakeColor;

  PROCEDURE GetRGB*(col: COLOR; VAR red, green, blue: INTEGER);
  BEGIN IF api # NIL THEN api.GetRGB(col, red, green, blue); ELSE red := 0; green := 0; blue := 0; END;
  END GetRGB;
  
  (* Changes a Ceres type Display byte into a VGA type Display byte.
     Bit 0 on Ceres is left most, bit 0 on VGA is rightmost
  *)
  PROCEDURE InvertPatternByte*(addr : ADDRESS);
  VAR s, ts : SET; i : LONGINT; byte : SYSTEM.BYTE;
  BEGIN SYSTEM.GET(addr, byte); ts := SYSTEM.VAL(SET, ORD(SYSTEM.VAL(CHAR, byte))) * {0..7}; s := {}; i := 0;
    WHILE i < 8 DO
      IF i IN ts THEN INCL(s, 8 - (i + 1)); END;
      INC(i);
    END;
    SYSTEM.PUT(addr, SYSTEM.VAL(SYSTEM.BYTE, s))
  END InvertPatternByte;

  PROCEDURE GetPatternSize*(pat: Pattern; VAR W, H: INTEGER);
    VAR w, h : SHORTINT;
  BEGIN SYSTEM.MEMR(pat, 0, w); SYSTEM.MEMR(pat, SIZE(SHORTINT), h); W := w; H := h;
  END GetPatternSize;

(* Allocates a new pattern with width w and height h. The i-th pattern
  line from bottom (increasing y-value) corresponds to the image
  entries i*lineLen .. (i+1)*lineLen-1, where lineLen = (w+31) DIV 32.
  The set elements desribe the pixels from left to right (increasing
  x-value). *)
  PROCEDURE NewPattern*(image: ARRAY OF SET; W, H: INTEGER): Pattern;
    VAR i, size : INTEGER; ptr : ADDRESS; dlen, slen, src, dst, pat : LONGINT;
  BEGIN
    size := (W + 7) DIV 8 * H; dlen := (W + 7) DIV 8; slen := (W + 31) DIV 32 * 4;
    SYSTEM.NEW(SYSTEM.VAL(SYSTEM.PTR, pat), LONG(2 * SIZE(SHORTINT) + size));
    SYSTEM.MEMW(pat, 0, SHORT(W)); SYSTEM.MEMW(pat, SIZE(SHORTINT), SHORT(H));

    dst := pat + 2 * SIZE(SHORTINT); src := SYSTEM.ADR(image); i := 0;
    WHILE i < H DO SYSTEM.MOVE(src, dst, dlen); INC(src, slen); INC(dst, dlen); INC(i); END;

    i := 0; ptr := pat + 2 * SIZE(SHORTINT);
    WHILE i < size DO InvertPatternByte(ptr); INC(ptr); INC(i); END;
    RETURN pat;
  END NewPattern;

  PROCEDURE ThisPattern* (n: INTEGER) : Pattern;
  BEGIN IF n < LEN(StandardPat) THEN RETURN StandardPat[n]; ELSE RETURN 0; END;
  END ThisPattern;

  PROCEDURE CopyPattern*(col: COLOR; pat: Pattern; X, Y : INTEGER; mode: SHORTINT);
  BEGIN IF api # NIL THEN api.CopyPattern(col, pat, X, Y, mode); END;
  END CopyPattern;

  PROCEDURE ReplPattern*(col: COLOR; pat: Pattern; X, Y, W, H : INTEGER; mode : SHORTINT);
  BEGIN IF api # NIL THEN api.ReplPattern(col, pat, X, Y, W, H, mode); END;
  END ReplPattern;

  (* Replicate pattern to (X, Y)-(X+W, Y+H], but draw as if actual drawing started at pX, pY *)
  PROCEDURE FillPattern*(col: COLOR; pat: Pattern; pX, pY, X, Y, W, H : INTEGER; mode: SHORTINT);
  BEGIN IF api # NIL THEN api.FillPattern(col, pat, pX, pY, X, Y, W, H, mode); END;
  END FillPattern;
  
  PROCEDURE Circle*(col : COLOR; X, Y, R : INTEGER; mode: SHORTINT);
  BEGIN IF api # NIL THEN api.Circle(col, X, Y, R, mode); END;
  END Circle;
  
  PROCEDURE Ellipse*(col : COLOR; X, Y, A, B : INTEGER; mode: SHORTINT);
  BEGIN IF api # NIL THEN api.Ellipse(col, X, Y, A, B, mode); END;
  END Ellipse;

  PROCEDURE GetHostColor*(color : INTEGER) : COLOR;
  BEGIN 
    IF (HostColors # NIL) & (color >= 0) & (color < LEN(HostColors^)) THEN RETURN HostColors[color];
    ELSE RETURN white;
    END;
  END GetHostColor;

  PROCEDURE InstallDriver*(interface : DriverAPI);
  BEGIN api := interface;
    IF api # NIL THEN 
      WorldWidth := api.WorldWidth; WorldHeight := api.WorldHeight; Height := api.Height; Width := api.Width;
      HostColors := api.OSColors;
      IF (HostColors = NIL) OR (LEN(HostColors^) < ColMinColors) THEN HostColors := NIL; BG := black;
      ELSE BG := HostColors[ColWindowBg];
      END;
      FG := white;
    ELSE WorldWidth := 0; WorldHeight := 0; Width := 0; Height := 0; HostColors := NIL; FG := white; BG := black;
    END;
  END InstallDriver;

  PROCEDURE InitStandardPat;
    VAR image: ARRAY 4 OF SET;
  BEGIN
    image[0] := {};
    StandardPat[0] := NewPattern(image, 32, 1);

    image[3] := {0, 8, 16, 24}; image[2] := {}; image[1] := {4, 12, 20, 28}; image[0] := {};
    StandardPat[1] := NewPattern(image, 32, 4);

    image[1] := {0, 4, 8, 12, 16, 20, 24, 28}; image[0] := {2, 6, 10, 14, 18, 22, 26, 30};
    StandardPat[2] := NewPattern(image, 32, 2);

    image[1] := {0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30};
    image[0] := {1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31};
    StandardPat[3] := NewPattern(image, 32, 2);

    image[1] := {1..3, 5..7, 9..11, 13..15, 17..19, 21..23, 25..27, 29..31};
    image[0] := {0, 1, 3..5, 7..9, 11..13, 15..17, 19..21, 23..25, 27..29, 31};
    StandardPat[4] := NewPattern(image, 32, 2);

    image[0] := {0..31};
    StandardPat[5] := NewPattern(image, 32, 1);

    image[3] :={3, 7, 11, 15, 19, 23, 27, 31}; image[2] :={2, 6, 10, 14, 18, 22, 26, 30};
    image[1] :={1, 5, 9, 13, 17, 21, 25, 29}; image[0] :={0, 4, 8, 12, 16, 20, 24, 28};
    StandardPat[6] := NewPattern(image, 32, 4);

    image[3] :={0, 4, 8, 12, 16, 20, 24, 28}; image[2] :={1, 5, 9, 13, 17, 21, 25, 29};
    image[1] :={2, 6, 10, 14, 18, 22, 26, 30}; image[0] :={3, 7, 11, 15, 19, 23, 27, 31};
    StandardPat[7] := NewPattern(image, 32, 4);

    image[0] := {2, 6, 10, 14, 18, 22, 26, 30};
    StandardPat[8] := NewPattern(image, 32, 1);

    image[3] := {}; image[2] := {}; image[1] := {}; image[0] := {0..31};
    StandardPat[9] := NewPattern(image, 32, 4)
  END InitStandardPat;

  PROCEDURE InitPatterns;
    VAR pat : ARRAY 16 OF SET;
  BEGIN
    pat[10] := {}; pat[09] := {}; pat[08] := { 4, 5 }; pat[07] := { 4, 5 }; pat[06] := { 4, 5 };
    pat[05] := { 0..9}; pat[04] := { 4, 5 }; pat[03] := { 4, 5 }; pat[02] := { 4, 5 }; pat[01] := {}; pat[00] := {};
    cross := NewPattern(pat, 10, 11);

    (* page 7-24 of the MS-Mouse reference book *)
    pat[15] := { }; pat[14] := { 1 }; pat[13] := { 1..2 }; 
    pat[12] := { 1..3 }; pat[11] := { 1..4 }; pat[10] := { 1..5 };
    pat[09] := { 1..6 }; pat[08] := { 1..7 }; pat[07] := { 1..8 }; pat[06] := { 1..9 }; pat[05] := { 1..5 };
    pat[04] := { 1, 5..6 }; pat[03] := { 5..6 }; pat[02] := { 6..7 }; pat[01] := { 6..7 }; pat[00] := { 7..8 };
    arrow := NewPattern(pat, 10, 16);

    pat[15] := { }; pat[14] := { }; pat[13] := { }; pat[12] := { }; pat[11] := { }; pat[10] := { };
    pat[09] := { }; pat[08] := { }; pat[07] := { }; pat[06] := { }; pat[05] := { };
    pat[04] := { }; pat[03] := { }; pat[02] := { }; pat[01] := { 0 }; pat[00] := { };
    ticks := NewPattern(pat, 16, 16);

    pat[03] := { 0, 4, 8, 12, 16, 20, 24, 28 }; pat[02] := { 0, 4, 8, 12, 16, 20, 24, 28 };
    pat[01] := { 6, 10, 14, 18, 22, 26  }; pat[00] := { 6, 10, 14, 18, 22, 26  };
    grey0 := NewPattern(pat, 32, 4);

    pat[03] := { 1, 5, 9, 13, 17, 21, 25, 29 }; pat[02] := { 1, 5, 9, 13, 17, 21, 25, 29 };
    pat[01] := { 0, 4, 8, 12, 16, 20, 24, 28 }; pat[00] := { 0, 4, 8, 12, 16, 20, 24, 28 };
    grey1 := NewPattern(pat, 32, 4);

    pat[01] := { 1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31 };
    pat[00] := { 0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30 };
    grey2 := NewPattern(pat, 32, 2);
    
    pat[15] := { };  pat[14] := { 5..6 }; pat[13] := { 5..6 }; pat[12] := { 5..6 }; pat[11] := { 5..6 };
    pat[10] := { 5..6 }; pat[09] := { 5..6 }; pat[08] := { 1..10 }; pat[07] := { 2..9 }; pat[06] := { 2..9 };
    pat[05] := { 3..8 }; pat[04] := { 3..8 }; pat[03] := { 4..7 }; 
    pat[02] := { 4..7 }; pat[01] := { 5, 6 }; pat[00] := { };
    downArrow := NewPattern(pat, 12, 16);
    
    pat[0] := {0..8}; pat[1] := {0..7}; pat[2] := {0..6}; pat[3] := {0..5};
    pat[4] := {0..4}; pat[5] := {0..3}; pat[6] := {0..2}; pat[7] := {0, 1}; pat[8] := {0};
    hook := NewPattern(pat, 9, 9);
  
    pat[14] := { 7 }; pat[13] := { 7 }; pat[12] := { 2, 7, 12 }; pat[11] := { 3, 7, 11 }; pat[10] := { 4, 7, 10 };
    pat[09] := { 5, 7, 9 }; pat[08] := { 6, 7, 8 }; 
    pat[07] := { 0..6, 8..14 }; pat[06] := { 6, 7, 8 }; pat[05] := { 5, 7, 9 };
    pat[04] := { 4, 7, 10 }; pat[03] := { 3, 7, 11 }; pat[02] := { 2, 7, 12 }; pat[01] := { 7 }; pat[00] := { 7 };
    star := NewPattern(pat, 15, 15);

    pat[0] := -{};
    pat[1] := -{};
    solid := NewPattern(pat, 16, 2);
  END InitPatterns;
  
  PROCEDURE Init;
    VAR i : INTEGER;
  BEGIN InstallDriver(NIL);
    InitPatterns;
    InitStandardPat;
    Unit := 10000;
    black := MakeColor(0, 0, 0); white := MakeColor(255, 255, 255);
  END Init;
  
BEGIN Init;
END Display.
