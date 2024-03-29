MODULE Objects; (*JG 21.9.93*)

  IMPORT SYSTEM, Kernel, Files, Modules;

  CONST
    enum* = 0; get* = 1; set* = 2; (*AttrMsg*)
    shallow* = 0; deep* = 1; (*CopyMsg id*)
    load* = 0; store* = 1; (*FileMsg id*)
    Inval* = 0;
    String* = 2;
    Int* = 3;
    Real* = 4;
    LongReal* = 5;
    Char* = 6;
    Bool* = 7;

    MaxNews = 32; MaxRuns = 64; MaxBlks = 16; MaxObjs = 64;
    standard = -2;

  TYPE
    Name* = ARRAY 32 OF CHAR;
    Object* = POINTER TO ObjDesc;
    Dummy* = POINTER TO DummyDesc;
    Library* = POINTER TO LibDesc;

    ObjMsg* = RECORD
      stamp*: LONGINT;
      dlink*: Object
    END;

    Handler* = PROCEDURE (obj: Object; VAR M: ObjMsg);

    ObjDesc* = RECORD
      stamp*: LONGINT;
      dlink*, slink*: Object;
      lib*: Library; ref*: INTEGER;
      handle*: Handler
    END;

    AttrMsg* = RECORD (ObjMsg)
      id*: INTEGER;
      Enum*: PROCEDURE (name: ARRAY OF CHAR);
      name*: Name;
      res*: INTEGER;
      class*: INTEGER;
      i*: LONGINT;
      x*: REAL;
      y*: LONGREAL;
      c*: CHAR;
      b*: BOOLEAN;
      s*: ARRAY 64 OF CHAR
    END;

    LinkMsg* = RECORD (ObjMsg)
      id*: INTEGER;
      Enum*: PROCEDURE (name: ARRAY OF CHAR);
      name*: Name;
      res*: INTEGER;
      obj*: Object
    END;

    CopyMsg* = RECORD (ObjMsg)
      id*: INTEGER; obj*: Object
    END;

    BindMsg* = RECORD (ObjMsg)
      lib*: Library
    END;

    FileMsg* = RECORD (ObjMsg)
      id*: INTEGER;
      len*: LONGINT;
      R*: Files.Rider
    END;

    FindMsg* = RECORD (ObjMsg)
      name*: Name;
      obj*: Object
    END;

    DummyDesc* = RECORD (ObjDesc)
      GName*: Name
    END;

    Index* = POINTER TO IndexDesc;
    IndexDesc* = RECORD END;

    Block = POINTER TO BlockDesc;
    BlockDesc = RECORD
      obj: ARRAY MaxObjs OF Object
    END;

    Fan = POINTER TO FanDesc;
    FanDesc = RECORD (IndexDesc)
      blk: ARRAY MaxBlks OF Block
    END;

    Entry = POINTER TO EntryDesc;
    EntryDesc = RECORD
      next: Entry;
      key: INTEGER;
      name: Name
    END;

    Dictionary* = RECORD
      key: INTEGER; first: Entry
    END;

    LibDesc* = RECORD
      next: Library; (*offset used by GC*)
      ind*: Index; (*offset used*)
      name*: Name;
      dict*: Dictionary;
      maxref*: INTEGER;
      GenRef*: PROCEDURE (L: Library; VAR ref: INTEGER);
      GetObj*: PROCEDURE (L: Library; ref: INTEGER; VAR obj: Object);
      PutObj*: PROCEDURE (L: Library; ref: INTEGER; obj: Object);
      FreeObj*: PROCEDURE (L: Library; ref: INTEGER);
      Load*: PROCEDURE (L: Library);
      Store*: PROCEDURE (L: Library)
    END;

    NewProc* = PROCEDURE (): Library;
    EnumProc* = PROCEDURE (L: Library);

    RunRec = RECORD beg, end: INTEGER END;

  VAR
    LibBlockId*: CHAR;
    FirstLib: Library;

    NewObj*: Object;
    stamp: LONGINT;
    minint: INTEGER;

    nofreg: INTEGER;
    LibExt: ARRAY  8, 8 OF CHAR;
    LibNew: ARRAY 8 OF NewProc;

  PROCEDURE Stamp* (VAR M: ObjMsg);
  BEGIN M.stamp := stamp; INC(stamp)
  END Stamp;

  (*general library management*)

  PROCEDURE ThisLibrary* (name: ARRAY OF CHAR): Library;
    VAR L: Library; f: Files.File; R: Files.Rider;
      len: LONGINT; i, j, n: INTEGER; id: CHAR;
      ext: ARRAY 8 OF CHAR;
  BEGIN L := FirstLib;
    WHILE (L # NIL) & (name # L.name) DO L := L.next END;
    IF L = NIL THEN i := -1; j := 0;
      WHILE name[j] # 0X DO
        IF name[j] = "." THEN i := j END; INC(j)
      END;
      INC(i); j := 0;
      WHILE (name[i] # 0X) & (j # 7) DO ext[j] := name[i]; INC(i); INC(j) END;
      ext[j] := 0X; n := 0;
      WHILE (n # nofreg) & (ext # LibExt[n]) DO INC(n) END;
      IF n # nofreg THEN L := LibNew[n]();
        COPY(name, L.name); L.next := FirstLib; FirstLib := L;
        L.Load(L);
      END
    END;
    RETURN L
  END ThisLibrary;

  PROCEDURE FreeLibrary* (name: ARRAY OF CHAR);
    VAR L: Library;
  BEGIN
    IF FirstLib # NIL THEN
      IF name = FirstLib.name THEN FirstLib := FirstLib.next
      ELSE L := FirstLib;
        WHILE (L.next # NIL) & (name # L.next.name) DO L := L.next END;
        IF L.next # NIL THEN L.next := L.next.next END
      END
    END
  END FreeLibrary;

  PROCEDURE Enumerate* (P: EnumProc);
    VAR L: Library;
  BEGIN L := FirstLib;
    WHILE L # NIL DO P(L); L := L.next END
  END Enumerate;

  PROCEDURE Register* (ext: ARRAY OF CHAR; new: NewProc);
    VAR n: INTEGER;
  BEGIN n := 0;
    WHILE (n # nofreg) & (ext # LibExt[n]) DO INC(n) END;
    IF n # nofreg THEN LibNew[n] := new
      ELSE COPY(ext, LibExt[nofreg]); LibNew[nofreg] := new; INC(nofreg)
    END
  END Register;

  (*standard libraries*)

  PROCEDURE ReadInt (VAR R: Files.Rider; VAR x: INTEGER);
   VAR c0: CHAR; s1: SHORTINT;
  BEGIN Files.Read(R, c0); Files.Read(R, s1); x := s1; x := x * 100H + ORD(c0)
  END ReadInt;

  PROCEDURE ReadLong (VAR R: Files.Rider; VAR x: LONGINT);
  VAR c0, c1, c2: CHAR; s1: SHORTINT;
  BEGIN Files.Read(R, c0); Files.Read(R, c1); Files.Read(R, c2); Files.Read(R, s1);
  x := s1; x := ((x * 100H + LONG(ORD(c2))) * 100H + LONG(ORD(c1))) * 100H + LONG(ORD(c0))
  END ReadLong;

  PROCEDURE WriteInt (VAR R: Files.Rider; x: INTEGER);
  BEGIN Files.Write(R, CHR(x)); Files.Write(R, CHR(x DIV 100H))
  END WriteInt;

  PROCEDURE WriteLong (VAR R: Files.Rider; x: LONGINT);
  BEGIN Files.Write(R, CHR(x)); Files.Write(R, CHR(x DIV 100H));
  Files.Write(R, CHR(x DIV 10000H)); Files.Write(R, CHR(x DIV 1000000H))
  END WriteLong;

  PROCEDURE ReadName (VAR R: Files.Rider; VAR name: ARRAY OF CHAR);
    VAR i: INTEGER; ch: CHAR;
  BEGIN i := 0; Files.Read(R, ch);
    WHILE (ch # ".") & (ch # 0X) DO name[i] := ch; INC(i); Files.Read(R, ch) END;
    name[i] := "."; INC(i); Files.Read(R, ch);
    WHILE ch # 0X DO name[i] := ch; INC(i); Files.Read(R, ch) END;
    name[i] := 0X
  END ReadName;

  PROCEDURE WriteName (VAR R: Files.Rider; name: ARRAY OF CHAR);
    VAR i: INTEGER; ch: CHAR;
  BEGIN i := 0; ch := name[i];
    WHILE ch # 0X DO Files.Write(R, ch); INC(i); ch := name[i] END;
    Files.Write(R, 0X)
  END WriteName;

  PROCEDURE SplitName (VAR name, MName, PName: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN i := 0;
    WHILE name[i] # "." DO MName[i] := name[i]; INC(i) END;
    MName[i] := 0X; INC(i); j := 0;
    WHILE name[i] # 0X DO PName[j] := name[i]; INC(i); INC(j) END;
    PName[j] := 0X
  END SplitName;

  PROCEDURE HandleDummy (obj: Object; VAR M: ObjMsg);
    VAR dum: Dummy; n: LONGINT; ch: CHAR;
  BEGIN
    WITH obj: Dummy DO
      IF M IS AttrMsg THEN
        WITH M: AttrMsg DO COPY(obj.GName, M.s) END
      ELSIF M IS CopyMsg THEN
        WITH M: CopyMsg DO NEW(dum); dum^ := obj^; M.obj := dum END
      ELSIF M IS FileMsg THEN
        WITH M: FileMsg DO
          IF M.id = load THEN n := M.len;
            WHILE n # 0 DO Files.Read(M.R, ch); DEC(n) END
          END
        END
      END
    END
  END HandleDummy;

  PROCEDURE NewDummy (VAR GName: ARRAY OF CHAR);
    VAR dum: Dummy;
  BEGIN
    NEW(dum); dum.handle := HandleDummy;
    COPY(GName, dum.GName);
    NewObj := dum
  END NewDummy;

  PROCEDURE GetObj (L: Library; ref: INTEGER; VAR obj: Object);
    VAR fan: Fan;
  BEGIN fan := L.ind(Fan);
    IF ref DIV MaxObjs >= MaxBlks THEN obj := NIL
      ELSIF fan.blk[ref DIV MaxObjs] = NIL THEN obj := NIL
      ELSE obj := fan.blk[ref DIV MaxObjs].obj[ref MOD MaxObjs]
    END
  END GetObj;

  PROCEDURE PutObj (L: Library; ref: INTEGER; obj: Object);
    VAR fan: Fan;
  BEGIN fan := L.ind(Fan);
    IF fan.blk[ref DIV MaxObjs] = NIL THEN
      NEW(fan.blk[ref DIV MaxObjs])
    END;
    fan.blk[ref DIV MaxObjs].obj[ref MOD MaxObjs] := obj;
    obj.lib := L; obj.ref := ref;
    IF ref >= L.maxref THEN L.maxref := ref + 1 END
  END PutObj;

  PROCEDURE FreeObj (L: Library; ref: INTEGER);
    VAR fan: Fan;
  BEGIN fan := L.ind(Fan);
    IF fan.blk[ref DIV MaxObjs] # NIL THEN
      fan.blk[ref DIV MaxObjs].obj[ref MOD MaxObjs] := NIL
    END
  END FreeObj;

  PROCEDURE GenRef (L: Library; VAR ref: INTEGER);
    VAR fan: Fan; blk: Block; a, b: INTEGER;
  BEGIN fan := L.ind(Fan); b := 0;
    LOOP
      IF b = MaxBlks THEN ref := -1; EXIT END;
      IF fan.blk[b] = NIL THEN ref := b*MaxObjs; EXIT END;
      blk := fan.blk[b]; a := 0;
      WHILE (a # MaxObjs) & (blk.obj[a] # NIL) DO INC(a) END;
      IF a # MaxObjs THEN ref := b*MaxObjs + a; EXIT END;
      INC(b)
    END
  END GenRef;

  PROCEDURE LoadLibrary* (L: Library; f: Files.File; pos: LONGINT; VAR len: LONGINT);
    VAR
      R, S: Files.Rider;
      Mod: Modules.Module; Cmd: Modules.Command;
      NofRuns, key, N, i, k, l, m: INTEGER;
      clen, dlen: LONGINT;
      type, n: SHORTINT; ch: CHAR;
      fan: Fan; entry: Entry;
      obj: Object; M: FileMsg;
      MName, PName: Name;
      GName: ARRAY MaxNews OF Name;
    run: ARRAY MaxRuns OF RunRec;
  BEGIN fan := L.ind(Fan);
    Files.Set(R, f, pos); Files.Read(R, type);
    ReadLong(R, clen);
    Files.Set(S, f, pos + 1 + clen);
    ReadLong(S, dlen);
    ReadInt(S, key);
    WHILE key # minint DO NEW(entry);
      i := 0; Files.Read(S, ch);
      WHILE ch # 0X DO
        entry.name[i] := ch; INC(i); Files.Read(S, ch)
      END;
      entry.name[i] := 0X;
      entry.key := key;
      entry.next := L.dict.first; L.dict.first := entry;
      IF key < L.dict.key THEN L.dict.key := key END;
      ReadInt(S, key)
    END;
    IF type >= 0 THEN (*old format*)
      Files.Read(R, ch); Files.Read(R, ch);
      ReadInt(R, i); ReadInt(R, i); ReadInt(R, i);
      ReadInt(R, i); ReadInt(R, i)
    END;
    ReadInt(R, NofRuns);
    k := 0;
     WHILE k # NofRuns DO
      ReadInt(R, run[k].beg); ReadInt(R, run[k].end);
      INC(k)
    END;
    N := 0; k := 0; m := 0;
    WHILE k < NofRuns DO m := run[k].beg;
      WHILE m < run[k].end DO Files.Read(R, n);
      IF n = N THEN ReadName(R, GName[N]); INC(N) END;
        SplitName(GName[n], MName, PName);
      Mod := Modules.ThisMod(MName);
      IF Modules.res = 0 THEN
        Cmd := Modules.ThisCommand(Mod, PName);
          IF Modules.res = 0 THEN Cmd
            ELSE NewDummy(GName[n])
          END
        ELSE NewDummy(GName[n])
        END;
        IF fan.blk[m DIV MaxObjs] = NIL THEN NEW(fan.blk[m DIV MaxObjs]) END;
        fan.blk[m DIV MaxObjs].obj[m MOD MaxObjs] := NewObj;
        NewObj.lib := L; NewObj.ref := m;
      INC(m)
      END;
      INC(k)
    END;
    L.maxref := m;
    M.id := load; Stamp(M);
    Files.Set(M.R, f, Files.Pos(R));
    k := 0; m := 0;
    WHILE k < NofRuns DO m := run[k].beg;
    WHILE m < run[k].end DO ReadLong(M.R, M.len);
        IF M.len # 0 THEN
          obj := fan.blk[m DIV MaxObjs].obj[m MOD MaxObjs];
          obj.handle(obj, M)
        END;
        INC(m)
      END;
      INC(k)
    END;
    L.ind := fan;
    len := 1 + clen + dlen
  END LoadLibrary;

  PROCEDURE StoreLibrary* (L: Library; f: Files.File; pos: LONGINT; VAR len: LONGINT);
  VAR R: Files.Rider;
        prevObj, obj: Object;
        clen, dlen, olen: LONGINT;
    NofRuns, NofObjs, N, i, j, k, m: INTEGER;
    n: SHORTINT;
        M: FileMsg; M0: AttrMsg;
        fan: Fan; entry: Entry;
        GName: ARRAY MaxNews OF Name;
    run: ARRAY MaxRuns OF INTEGER;
  BEGIN fan := L.ind(Fan);
    k := 0; m := 0; prevObj := NIL;
    REPEAT
      IF fan.blk[m DIV MaxObjs] # NIL THEN
        obj := fan.blk[m DIV MaxObjs].obj[m MOD MaxObjs]
      ELSE obj := NIL
      END;
      IF (prevObj= NIL) # (obj = NIL) THEN run[k] := m; INC(k) END;
      prevObj := obj;
      INC(m)
    UNTIL m DIV MaxObjs >= MaxBlks;
    IF k MOD 2 # 0 THEN run[k] := m; INC(k) END;
    NofRuns := k DIV 2;
    Files.Set(R, f, pos);
    Files.Write(R, LibBlockId);
    Files.Write(R, standard); (*format type*)
    WriteLong(R, clen); (*place holder*)
    WriteInt(R, NofRuns);
    k := 0;
    WHILE k # NofRuns DO
    WriteInt(R, run[2*k]); WriteInt(R, run[2*k+1]); INC(k)
    END;
    M0.id := get; M0.name := "Gen";
    N := 0; k := 0;
    WHILE k # NofRuns DO m := run[2*k];
      WHILE m < run[2*k+1] DO L.GetObj(L, m, obj);
        obj.handle(obj, M0); COPY(M0.s, GName[N]);
        n := 0;
      WHILE GName[n] # GName[N] DO INC(n) END;
      Files.Write(R, n);
      IF n = N THEN WriteName(R, GName[N]); INC(N) END;
        INC(m)
      END;
      INC(k)
    END;
    M.id := store; Stamp(M);
    Files.Set(M.R, f, Files.Pos(R));
    k := 0;
    WHILE k # NofRuns DO m := run[2*k];
      WHILE m < run[2*k+1] DO
        WriteLong(M.R, olen); (*dummy*)
        L.GetObj(L, m, obj); obj.handle(obj, M);
        olen := Files.Pos(M.R) - Files.Pos(R) - 4;
        WriteLong(R, olen);
        Files.Set(R, f, Files.Pos(M.R));
        INC(m)
      END;
      INC(k)
    END;
    clen := Files.Pos(R) - pos - 2;
    WriteLong(R, dlen); (*place holder*)
    entry := L.dict.first;
    WHILE entry # NIL DO
      WriteInt(R, entry.key); i := 0;
      WHILE entry.name[i] # 0X DO Files.Write(R, entry.name[i]); INC(i) END;
      Files.Write(R, 0X);
      entry := entry.next
    END;
    WriteInt(R, minint);
    dlen := Files.Pos(R) - pos - 2 - clen;
    Files.Set(R, f, pos + 2);
    WriteLong(R, clen); (*fixup*)
    Files.Set(R, f, pos + 2 + clen);
    WriteLong(R, dlen); (*fixup*)
    len := 2 + clen + dlen
  END StoreLibrary;

  PROCEDURE LoadFileLib (L: Library);
    VAR f: Files.File; R: Files.Rider; len: LONGINT; id: CHAR;
  BEGIN f := Files.Old(L.name);
    IF f # NIL THEN Files.Set(R, f, 0); Files.Read(R, id) END;
    IF (f # NIL) & (id = LibBlockId) THEN LoadLibrary(L, f, 1, len) END
  END LoadFileLib;

  PROCEDURE StoreFileLib (L: Library);
    VAR f: Files.File; len: LONGINT;
  BEGIN f := Files.New(L.name);
    IF f # NIL THEN StoreLibrary(L, f, 0, len); Files.Register(f) END
  END StoreFileLib;

  PROCEDURE OpenLibrary* (L: Library);
    VAR fan: Fan;
  BEGIN
    L.Load := LoadFileLib; L.Store := StoreFileLib;
    L.GenRef:= GenRef; L.GetObj := GetObj;
    L.PutObj := PutObj; L.FreeObj := FreeObj;
    L.dict.key := 0; L.dict.first := NIL;
    NEW(fan); L.ind := fan; L.maxref := 0
  END OpenLibrary;

  PROCEDURE NewLibrary (): Library;
    VAR L: Library;
  BEGIN NEW(L); OpenLibrary(L); RETURN L
  END NewLibrary;

  PROCEDURE GetRef* (VAR D: Dictionary; name: ARRAY OF CHAR; VAR ref: INTEGER);
    VAR cur: Entry;
  BEGIN cur := D.first;
    WHILE (cur # NIL) & ((cur.key < 0) OR (cur.name # name)) DO cur := cur.next END;
    IF cur = NIL THEN ref := minint ELSE ref := cur.key END
  END GetRef;

  PROCEDURE GetKey* (VAR D: Dictionary; name: ARRAY OF CHAR; VAR key: INTEGER);
    VAR cur: Entry;
  BEGIN cur := D.first;
    WHILE (cur # NIL) & ((cur.key >= 0) OR (cur.name # name)) DO cur := cur.next END;
    IF cur = NIL THEN DEC(D.key);
      NEW(cur); cur.key := D.key; COPY(name, cur.name); cur.next := D.first; D.first := cur
    END;
    key := cur.key
  END GetKey;

  PROCEDURE GetName* (VAR D: Dictionary; key: INTEGER; VAR name: ARRAY OF CHAR);
    VAR cur: Entry;
  BEGIN cur := D.first;
    WHILE (cur # NIL) & (cur.key # key) DO cur := cur.next END;
    IF cur = NIL THEN name[0] := 0X ELSE COPY(cur.name, name) END
  END GetName;

  PROCEDURE PutName* (VAR D: Dictionary; key: INTEGER; name: ARRAY OF CHAR);
    VAR cur: Entry;
  BEGIN
    IF key >= 0 THEN cur := D.first;
      WHILE (cur # NIL) & (cur.key # key) DO cur := cur.next END;
      IF cur = NIL THEN
        NEW(cur); cur.key := key; cur.next := D.first; D.first := cur
      END;
      COPY(name, cur.name)
    END
  END PutName;

BEGIN LibBlockId := 0DBX;
  minint := MIN(INTEGER);
  FirstLib := NIL; Kernel.FontRoot := SYSTEM.ADR(FirstLib);
  stamp := MIN(LONGINT);
  nofreg := 0;
  Register("Lib", NewLibrary)
END Objects.
