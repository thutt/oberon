MODULE Fonts; (*JG 16.3.94*)
  IMPORT SYSTEM, Kernel, Files, Objects, Display, Console;

  CONST MaxRuns = 32; IndexSize = 256*4;
    substitute* = -1; font* = 0; metric* = 1; (*font types*)

  TYPE
    Char* = POINTER TO CharDesc;
    Font* = POINTER TO FontDesc;

    CharDesc* = RECORD (Objects.ObjDesc)
      dx*, x*, y*, w*, h*: INTEGER;
      pat*: Display.Pattern
    END;

    FontDesc* = RECORD (Objects.LibDesc)
      type*: SHORTINT;
      height*, minX*, maxX*, minY*, maxY*: INTEGER
    END;

    FontIndex = POINTER TO FontIndexDesc;
    FontIndexDesc = RECORD (Objects.IndexDesc)
      data : LONGINT;
    END;

    RunRec = RECORD beg, end: INTEGER END;

    BoxRec = RECORD
      dx, x, y, w, h: INTEGER
    END;

  VAR
    FontId*: CHAR;
    Default*: Font;
    theChar: Char;
  
  PROCEDURE Put1 (VAR a: LONGINT; x: INTEGER);
  VAR y: SHORTINT;
  BEGIN y := SHORT(x); SYSTEM.PUT(a, y); INC(a)
  END Put1;
  
  PROCEDURE Put2 (VAR a: LONGINT; x: LONGINT);
  VAR y: INTEGER;
  BEGIN y := SHORT(x); SYSTEM.PUT(a, y); a := a + 2
  END Put2;
  
  PROCEDURE Put4 (VAR a: LONGINT; x: LONGINT);
  BEGIN SYSTEM.PUT(a, x); a := a + 4
  END Put4;

  PROCEDURE ReadInt (VAR R: Files.Rider; VAR x: INTEGER);
  VAR c0: CHAR; s1: SHORTINT;
  BEGIN ASSERT(~R.eof, 1030); Files.Read(R, c0); Files.Read(R, s1); x := s1; x := x * 100H + ORD(c0)
  END ReadInt;
  
  PROCEDURE GetCharObj (L: Objects.Library; ref: INTEGER; VAR obj: Objects.Object);  
  VAR m: LONGINT; h1: SHORTINT; h2: LONGINT; ch: CHAR;
  BEGIN
    m := L.ind(FontIndex).data;
    SYSTEM.GET(m + ref * SIZE(LONGINT), h2); (* pat adr*)
    theChar.pat := h2;
    SYSTEM.GET(h2-3, h1); theChar.dx := h1;
    SYSTEM.GET(h2-2, h1); theChar.x := h1;
    SYSTEM.GET(h2-1, h1); theChar.y := h1;
    SYSTEM.GET(h2, ch); theChar.w := ORD(ch);  (*width & height always positive*)
    SYSTEM.GET(h2+1,ch); theChar.h := ORD(ch);
    obj := theChar;
  END GetCharObj;

  PROCEDURE GetChar* (F: Font; ch: CHAR; VAR dx, x, y, w, h: INTEGER; VAR pat: Display.Pattern);
  VAR obj: Objects.Object;
  BEGIN F.GetObj(F, ORD(ch), obj);
    WITH obj:Char DO dx := obj.dx; x := obj.x; y := obj.y; w := obj.w; h := obj.h; pat := obj.pat; END
  END GetChar;

  PROCEDURE Internalize (F: Font; VAR R: Files.Rider; type: SHORTINT);
  VAR n: SHORTINT; ch: CHAR;
      NofRuns, NofBoxes, N, i, k, l, m: INTEGER;
      NofBytes, RasterBase, A, a: LONGINT;
      run: ARRAY MaxRuns OF RunRec;
      box: ARRAY 256 OF BoxRec;
      index : FontIndex;
  BEGIN F.type := type;
    Files.Read(R, ch); (*family*)
    Files.Read(R, ch); (*variant*)
    ReadInt(R, F.height);
    ReadInt(R, F.minX); ReadInt(R, F.maxX);
    ReadInt(R, F.minY); ReadInt(R, F.maxY);
    ReadInt(R, NofRuns);
    NofBoxes := 0; k := 0;
    WHILE k # NofRuns DO
      ReadInt(R, run[k].beg); ReadInt(R, run[k].end);
      NofBoxes := NofBoxes + run[k].end - run[k].beg;
      INC(k)
    END;
    l := 0;
    WHILE l # NofBoxes DO
      ReadInt(R, box[l].dx);
      ReadInt(R, box[l].x); ReadInt(R, box[l].y);
      ReadInt(R, box[l].w); ReadInt(R, box[l].h);
      INC(l)
    END;
    IF type = font THEN
      NofBytes := IndexSize + 29; l := 0;
      WHILE l # NofBoxes DO
        NofBytes := NofBytes + 5 + (box[l].w + 7) DIV 8 * box[l].h; INC(l)
      END;
      NEW(index); SYSTEM.NEW(SYSTEM.VAL(SYSTEM.PTR, index.data), NofBytes); F.ind := index;
      RasterBase := index.data;
      A := RasterBase; a := A + IndexSize;
      Put1(a, 12); Put1(a, 0); Put1(a, -3); Put1(a, 12); Put1(a, 12); (*null char (box outline character) *)
      Put2(a, 0FFFH);
      Put2(a, 8080H); Put2(a, 8080H); Put2(a, 8080H); Put2(a, 8080H); Put2(a, 8080H);
      Put2(a, 8080H); Put2(a, 8080H); Put2(a, 8080H); Put2(a, 8080H); Put2(a, 8080H);
      Put2(a, 0FFFH);
      k := 0; l := 0; m := 0;
      WHILE k < NofRuns DO
        WHILE m < run[k].beg DO Put4(A, RasterBase + IndexSize + 3); INC(m) END;
        WHILE m < run[k].end DO Put4(A, a + 3);
          Put1(a, box[l].dx);
          Put1(a, box[l].x); Put1(a, box[l].y);
          Put1(a, box[l].w); Put1(a, box[l].h);
          i := (box[l].w + 7) DIV 8 * box[l].h;
          WHILE i # 0 DO
            Files.Read(R, ch); Display.InvertPatternByte(SYSTEM.ADR(ch)); Put1(a, ORD(ch)); DEC(i)
          END;
          INC(l); INC(m)
        END;
        INC(k)
      END;
      WHILE m < 256 DO Put4(A, RasterBase + IndexSize + 3); INC(m) END;
    ELSE (*type := metric*)
      NEW(index); SYSTEM.NEW(SYSTEM.VAL(SYSTEM.PTR, index.data), IndexSize + 5 + NofBoxes*5); F.ind := index;
      RasterBase := index.data;
      A := RasterBase; a := A + IndexSize;
      Put1(a, 12); Put1(a, 0); Put1(a, -3); Put1(a, 12); Put1(a, 12); (*null char*)
      k := 0; l := 0; m := 0;
      WHILE k < NofRuns DO
        WHILE m < run[k].beg DO Put4(A, RasterBase + IndexSize + 3); INC(m) END;
        WHILE m < run[k].end DO Put4(A, a + 3);
          Put1(a, box[l].dx);
          Put1(a, box[l].x); Put1(a, box[l].y);
          Put1(a, box[l].w); Put1(a, box[l].h);
          INC(l); INC(m)
        END;
        INC(k)
      END;
      WHILE m < 256 DO Put4(A, RasterBase + IndexSize + 3); INC(m) END
    END
  END Internalize;

  PROCEDURE Substitute (F: Font);
  BEGIN
    F.type := substitute;
    F.height := Default.height;
    F.minX := Default.minX; F.maxX := Default.maxX;
    F.minY := Default.minY; F.maxY := Default.maxY;
    F.ind := Default.ind
  END Substitute;

  PROCEDURE *Load (L: Objects.Library);
  VAR f: Files.File; R: Files.Rider; id: CHAR; i: INTEGER;
      name: ARRAY 32 OF CHAR;
  BEGIN
    WITH L: Font DO
      f := Files.Old(L.name);
      IF f # NIL THEN
        Files.Set(R, f, 0); Files.Read(R, id);
        IF id = FontId THEN Files.Read(R, L.type);
          IF (L.type = metric) OR (L.type = font) THEN Internalize(L, R, L.type)
          ELSE Substitute(L)
          END
        ELSE Substitute(L) END
      ELSE COPY(L.name, name); i := 0;
        WHILE name[i] # 0X DO INC(i) END;
        IF (i >= 8) & (name[i-8] = ".") & (name[i-7] = "M") & (name[i-6] = "d") THEN
          name[i-7] := "P"; name[i-6] := "r"; f := Files.Old(name);
          IF f # NIL THEN
            Files.Set(R, f, 0); Files.Read(R, id);
            IF id = FontId THEN Files.Read(R, L.type);
              IF (L.type = metric) OR (L.type = font) THEN Internalize(L, R, metric) ELSE Substitute(L) END
            ELSE Substitute(L) END
          ELSE Substitute(L) END
        ELSE Substitute(L) END
      END
    END
  END Load;

  PROCEDURE This* (name: ARRAY OF CHAR): Font;
  VAR L: Objects.Library;
  BEGIN L := Objects.ThisLibrary(name); ASSERT(L # NIL);
    IF L IS Font THEN RETURN L(Font); ELSE RETURN NIL; END;
  END This;

  PROCEDURE *New (): Objects.Library;
  VAR F: Font;
  BEGIN NEW(F); F.Load := Load; F.GetObj := GetCharObj; RETURN F
  END New;

BEGIN FontId := 0DBX; NEW(theChar); Objects.Register("Fnt", New)
END Fonts.
