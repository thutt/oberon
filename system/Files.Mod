MODULE Files;
  IMPORT SYSTEM, Kernel, FileDir, Console;

  CONST (* exported constants *)
    NoError* = 0; (* generic *)
    InvalidFilename* = 21; (* Check *)
    CannotDelete* = 22; (* Delete *)
    CannotRename* = 23; (* Rename *)
    NoName* = 24; (* "" is given as filename *)
    
  CONST
    MaxBufs    = 4;

  CONST
    NotDiskFile = NIL;
    PageSize = 4 * 1024;  (* careful to remain under page size *)

  TYPE
    File*   = POINTER TO FileDesc;
    Buffer   = POINTER TO BufferDesc;

    Rider* = RECORD
      eof*: BOOLEAN;
      res*: LONGINT;
      file: File;
      page: LONGINT; (* (Apage: 0 <= page < file.length DIV PageSize: page MOD PageSize = 0) *)
      pageofs : LONGINT; (* offset in 'buf' [0..PageSize) *)
      buf: Buffer;
    END;

    (* if a handle = NotDiskFile, the entire file, [0..f.length), is in memory
      Multiple calls to Old() with the same filename result in the same File.
    *)
    FileDesc* = RECORD
      firstbuf: Buffer;
      time*, date*: LONGINT; (* Oberon style *)
      length* : LONGINT; (* [0..MAX(LONGINT)] *)
      handle : FileDir.Handle;
      nofbufs*: INTEGER; (* (0..MaxBufs] *)
      name*: FileDir.Filename;
    END;

  (* buffer records will always be located on a multiple of PageSize bytes *)
  BufferDesc = RECORD
    page : LONGINT; (* (Apage: 0 <= page < file.length DIV PageSize: page MOD PageSize = 0) *)
    lim: INTEGER; (* [0, PageSize); lim = 0 signifies empty buffer; (number of bytes currently stored in buffer) *)
    mod: BOOLEAN;
    next: Buffer;
    data: ARRAY PageSize OF SYSTEM.BYTE; (* [0..lim) bytes in buffer are valid *)
  END;

  PROCEDURE GetHandleFile(h : FileDir.Handle) : File;
  BEGIN RETURN SYSTEM.VAL(File, FileDir.GetHandleFile(h));
  END GetHandleFile;

  PROCEDURE SetHandleFile(h : FileDir.Handle; fp : File);
  BEGIN FileDir.SetHandleFile(h, SYSTEM.VAL(LONGINT, fp));
  END SetHandleFile;

  PROCEDURE NewBuffer(VAR b : Buffer);
    VAR b0 : Buffer;
  BEGIN NEW(b0); b := b0; b0.page := 0; b0.lim := 0; b0.mod := FALSE; b0.next := NIL;
  END NewBuffer;

  PROCEDURE NewFile(VAR h : File);
    VAR h0 : File;
  BEGIN NEW(h0);
    h := h0; h0.nofbufs := 0; h0.firstbuf := NIL; 
    h0.name[0] := 0X; h0.time := 0; h0.date := 0; h0.length := 0; h0.handle := NotDiskFile;
  END NewFile;

  (* turn unvalidated name into validated name, if name is 0X, anonymous file *)
  PROCEDURE Check(VAR s: ARRAY OF CHAR; VAR name: FileDir.Filename; VAR res : INTEGER);
    VAR info : POINTER TO FileDir.PathInfo;
  BEGIN
    (* FIXME: this is a pointer because `enter', `leave' on Linux 2.2.14 
     * can cause SEGV.  When compiler updated to work with `sub esp', this should
     * be changed back to a non-pointer variable
     *)
    NEW(info); res := NoError; name[0] := 0X;
    FileDir.Split(s, info^);
    IF ~(FileDir.piInvalid IN info.flags) THEN COPY(s, name);
      IF name[0] = 0X THEN res := NoName; END;
    ELSE (* invalid conversion *) res := InvalidFilename;
    END;
    info := NIL;
  END Check;

  PROCEDURE Old*(name: ARRAY OF CHAR): File;
    VAR
      handle : FileDir.Handle; 
      res : INTEGER; f: File;
      buf: Buffer; namebuf: FileDir.Filename; read : LONGINT; err : BOOLEAN;
  BEGIN f := NIL; Check(name, namebuf, res);
    IF res = NoError THEN
      FileDir.open(namebuf, handle, err);
      IF ~err THEN f := GetHandleFile(handle);
        IF f = NIL THEN
          NewBuffer(buf); buf.next := buf; buf.mod := FALSE; buf.page := 0;
          FileDir.read(handle, PageSize, buf.data, read); buf.lim := SHORT(read);
          NewFile(f); f.handle := handle; FileDir.gettimestamp(handle, f.time, f.date);
          f.firstbuf := buf; f.nofbufs := 1; f.name := namebuf;
          FileDir.seek(handle, 0, FileDir.SeekEnd, f.length, err); SetHandleFile(handle, f);
        END;
      END;
    END;
    RETURN f;
  END Old;

  (* Until files are registered or they occupy disk space, they are not kept on any list of files *)
  PROCEDURE New*(name: ARRAY OF CHAR): File;
    VAR res: INTEGER; f: File; buf: Buffer; namebuf: FileDir.Filename;

    PROCEDURE AllocateBuffers(VAR h : Buffer); (* get all the buffers for a new file *)
    VAR bp, buf : Buffer; i : LONGINT;
    BEGIN NewBuffer(h); h.mod := TRUE; bp := h; i := 1;
      WHILE i < MaxBufs DO NewBuffer(buf); bp.next := buf; bp := buf; bp.page := i * PageSize; INC(i); END;
      bp.next := h;
    END AllocateBuffers;

  BEGIN f := NIL; Check(name, namebuf, res);
    IF res IN {NoError, NoName} THEN AllocateBuffers(buf);
      NewFile(f); Kernel.GetClock(f.time, f.date); f.firstbuf := buf; f.nofbufs := MaxBufs; COPY(namebuf, f.name);
    END;
    RETURN f;
  END New;

  PROCEDURE Delete*(name: ARRAY OF CHAR; VAR res: INTEGER);
  VAR f : File; err : BOOLEAN; namebuf : FileDir.Filename;
  BEGIN Check(name, namebuf, res);
    IF res = NoError THEN FileDir.unlinkfile(namebuf, err);
      IF err THEN res := CannotDelete; END;
    END;
  END Delete;

  PROCEDURE Rename*(old, new: ARRAY OF CHAR; VAR res: INTEGER);
    VAR err : BOOLEAN; oldbuf, newbuf : FileDir.Filename;
  BEGIN Check(old, oldbuf, res);
    IF res = NoError THEN Check(new, newbuf, res);
      IF res = NoError THEN FileDir.rename(oldbuf, newbuf, err);
        IF err THEN res := CannotRename; END;
      END;
    END;
  END Rename;

  PROCEDURE Pos*(VAR r: Rider): LONGINT;
  BEGIN RETURN r.page + r.pageofs;
  END Pos;

  PROCEDURE Base*(VAR r: Rider): File;
  BEGIN RETURN r.file;
  END Base;

  PROCEDURE ReadBuf(f: File; buf: Buffer; pos: LONGINT);
  VAR err : BOOLEAN; read, newpos : LONGINT;
  BEGIN (* pre:: f.handle # NotDiskFile *)
    FileDir.seek(f.handle, pos, FileDir.SeekSet, newpos, err);
    IF ~err THEN FileDir.read(f.handle, PageSize, buf.data, read); buf.lim := SHORT(read);
    ELSE buf.lim := 0;
    END;
    buf.page := pos; buf.mod := FALSE;
  END ReadBuf;
  
  PROCEDURE WriteBuf(f: File; buf: Buffer);
  VAR err : BOOLEAN; newpos, written : LONGINT;
  BEGIN (* pre: f.handle # NotDiskFile *)
    FileDir.seek(f.handle, buf.page, FileDir.SeekSet, newpos, err); (* inv: ~err (else internal error) *)
    FileDir.write(f.handle, buf.lim, buf.data, written); buf.mod := FALSE;
  END WriteBuf;

  (* find a buffer of 'f' which matches the desired position. *)
  (* pre: pos MOD PageSize = 0 *)
  (* post: buf # NIL => buffer found *)
  (* post: buf # NIL => buffer not found *)
  PROCEDURE Buf(f: File; pos: LONGINT): Buffer;
  VAR buf: Buffer;
  BEGIN (* pre: pos MOD PageSize = 0 *)
    buf := f.firstbuf;
    LOOP
      IF pos = buf.page THEN EXIT; END;
      buf := buf.next;
      IF buf = f.firstbuf THEN buf := NIL; EXIT; END;
    END;
    RETURN buf;
  END Buf;

  (* create a DOS file and flush all buffers; at least first buffer will be written *)
  PROCEDURE CreateFile(f : File);
  VAR buf : Buffer; err : BOOLEAN;
  BEGIN (* pre: f.handle = NotDiskFile *)
    FileDir.create(f.name, f.handle, err); SetHandleFile(f.handle, f);
    buf := f.firstbuf; (* inv: (Ai: 0 <= i < MaxBufs: page(buf[i]) < page(buf[i + 1])) *)
    REPEAT WriteBuf(f, buf); buf := buf.next; UNTIL (buf = f.firstbuf) OR (buf.lim = 0);
  END CreateFile;

  (* Get a buffer for 'f'.  Create if possible; write to disk if required *)
  PROCEDURE GetBuf(f: File; page: LONGINT): Buffer;
  VAR buf: Buffer;
  BEGIN (* pre: page MOD PageSize = 0 *)
    buf := f.firstbuf;
    LOOP
      IF page = buf.page THEN EXIT; END;
      IF buf.next = f.firstbuf THEN
        IF f.nofbufs < MaxBufs THEN (* allocate buffer *) 
          NewBuffer(buf); buf.next := f.firstbuf.next; f.firstbuf.next := buf; INC(f.nofbufs);
        ELSE (* replace buffer *)
          IF f.handle = NotDiskFile THEN CreateFile(f); END;
          f.firstbuf := buf;
          IF buf.mod THEN WriteBuf(f, buf); END;
        END;
        buf.page := page;
        (* inv: NotDiskFile => page < f.length *)
        IF page < f.length THEN ReadBuf(f, buf, page); END; (* page is always page boundary *)
        EXIT;
      END;
      buf := buf.next;
    END;
    RETURN buf;
  END GetBuf;

  PROCEDURE Unbuffer(f: File);
  VAR buf: Buffer;
  BEGIN (* pre: f.handle # NotDiskFile *)
    buf := f.firstbuf;
    REPEAT
      IF buf.mod THEN WriteBuf(f, buf); END;
      buf := buf.next
    UNTIL buf = f.firstbuf;
  END Unbuffer;

  (* does not close the file *)
  PROCEDURE Register*(f: File);
  VAR err : BOOLEAN;
  BEGIN
    IF f # NIL THEN
      IF f.handle = NotDiskFile THEN
        CreateFile(f);
      END;
      Unbuffer(f);
      FileDir.close(f.handle);
      FileDir.renamehandle(f.handle, f.name, err);
    END;
  END Register;

  PROCEDURE Close*(f: File);
  BEGIN
    IF (f # NIL) & (f.handle # NotDiskFile) THEN Unbuffer(f); END;
  END Close;

  PROCEDURE Purge*(f: File);
  VAR err : BOOLEAN;
  BEGIN IF (f # NIL) & (f.handle # NotDiskFile) THEN FileDir.unlink(f.handle, err); END;
  END Purge;

  PROCEDURE Length*(f: File): LONGINT;
  BEGIN RETURN f.length;
  END Length;

  PROCEDURE GetDate*(f: File; VAR t, d: LONGINT);
  BEGIN t := f.time; d := f.date
  END GetDate;

  PROCEDURE Set*(VAR r: Rider; f: File; pos: LONGINT);
  VAR a, b, l : LONGINT;
  BEGIN r.eof := FALSE; r.res := 0;
    IF f # NIL THEN
      IF pos <= 0 THEN  a := 0; b := 0;
      ELSIF pos < f.length THEN a := PageSize * (pos DIV PageSize); b := pos MOD PageSize;
      ELSE l := f.length; a := PageSize * (l DIV PageSize); b := l MOD PageSize;
      END;
      r.file := f; r.page := a; r.pageofs := b; r.buf := f.firstbuf;
    ELSE r.file:= NIL;
    END;
  END Set;

  PROCEDURE Read*(VAR r: Rider; VAR x: SYSTEM.BYTE);
  VAR buf: Buffer; l : LONGINT;
  BEGIN
    IF r.page # r.buf.page THEN r.buf := GetBuf(r.file, r.page); END;
    IF r.pageofs < r.buf.lim THEN x := r.buf.data[r.pageofs]; INC(r.pageofs);
    ELSIF r.page DIV PageSize < r.file.length DIV PageSize THEN
        (* all but last page *)
        INC(r.page, PageSize); buf := Buf(r.file, r.page);
        IF buf = NIL THEN
          IF r.buf.mod THEN WriteBuf(r.file, r.buf); END;
          ReadBuf(r.file, r.buf, r.page);
        ELSE r.buf := buf;
        END;
        x := r.buf.data[0]; r.pageofs := 1;
        r.eof :=  r.page + r.pageofs >= r.file.length;
    ELSE
      x := 0X; r.eof := TRUE;
    END;
  END Read;

  PROCEDURE ReadBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
  VAR src, dst, m: LONGINT; buf: Buffer;
  BEGIN
    dst := SYSTEM.ADR(x);
    IF LEN(x) < n THEN HALT(1028) END ;
    IF r.page # r.buf.page THEN r.buf := GetBuf(r.file, r.page); END;

    LOOP
      IF n <= 0 THEN EXIT; END;
      src := SYSTEM.ADR(r.buf.data) + r.pageofs; m := r.pageofs + n;
    
      IF m < r.buf.lim THEN SYSTEM.MOVE(src, dst, n); r.pageofs := SHORT(m); r.res := 0; EXIT;
      ELSIF r.buf.lim = PageSize THEN
        m := PageSize - r.pageofs;
        IF m > 0 THEN SYSTEM.MOVE(src, dst, m); INC(dst, m); DEC(n, m) END;
        IF r.page DIV PageSize < r.file.length DIV PageSize THEN
          (* all but last page *)
          INC(r.page, PageSize); r.pageofs := 0; buf := Buf(r.file, r.page);
          IF buf = NIL THEN
            IF r.buf.mod THEN WriteBuf(r.file, r.buf); END;
            ReadBuf(r.file, r.buf, r.page);
          ELSE r.buf := buf;
          END;
        ELSE r.res := n; r.eof := TRUE; EXIT;
        END;
      ELSE
        m := r.buf.lim - r.pageofs;
        IF m > 0 THEN SYSTEM.MOVE(src, dst, m); r.pageofs := r.buf.lim; END;
        r.res := n - m; r.eof := TRUE; EXIT;
      END;
    END;
  END ReadBytes;

  PROCEDURE ReadInt*(VAR R: Rider; VAR x: INTEGER);
    VAR x0, x1: SHORTINT;
  BEGIN Read(R, x0); Read(R, x1); x := LONG(x1) * 100H + LONG(x0) MOD 100H
  END ReadInt;

  PROCEDURE ReadLInt*(VAR R: Rider; VAR x: LONGINT);
  BEGIN ReadBytes(R, x, 4)
  END ReadLInt;

  PROCEDURE ReadSet*(VAR R: Rider; VAR x: SET);
  BEGIN ReadBytes(R, x, 4)
  END ReadSet;

  PROCEDURE ReadBool*(VAR R: Rider; VAR x: BOOLEAN);
    VAR s: SHORTINT;
  BEGIN Read(R, s); x := s # 0
  END ReadBool;

  PROCEDURE ReadReal*(VAR R: Rider; VAR x: REAL);
  BEGIN ReadBytes(R, x, 4)
  END ReadReal;

  PROCEDURE ReadLReal*(VAR R: Rider; VAR x: LONGREAL);
  BEGIN ReadBytes(R, x, 8)
  END ReadLReal;

  PROCEDURE ReadString*(VAR R: Rider; VAR x: ARRAY OF CHAR);
    VAR i: INTEGER; ch: CHAR;
  BEGIN i := 0;
    LOOP
      Read(R, ch); x[i] := ch; INC(i);
      IF ch = 0X THEN EXIT END ;
      IF i = LEN(x) THEN x[i-1] := 0X;
        REPEAT Read(R, ch) UNTIL ch = 0X;
        EXIT
      END
    END
  END ReadString;

  PROCEDURE ReadNum*(VAR R: Rider; VAR x: LONGINT);
    VAR ch: CHAR; n: INTEGER; y: LONGINT;
  BEGIN
    n := 0;
    y := 0;
    Read(R, ch);
    WHILE ch >= 80X DO
      INC(y, SYSTEM.LSH(LONG(ORD(ch)) - 128, n));
      INC(n, 7);
      Read(R, ch);
    END;
    x := ASH(SYSTEM.LSH(LONG(ORD(ch)), 25), n-25) + y;
  END ReadNum;

  PROCEDURE Write*(VAR r: Rider; x: SYSTEM.BYTE);
  VAR f: File; buf: Buffer;
  BEGIN
    IF r.page # r.buf.page THEN r.buf := GetBuf(r.file, r.page); END;
    IF r.pageofs >= r.buf.lim THEN
      IF r.pageofs < PageSize THEN INC(r.buf.lim); INC(r.file.length);
      ELSE
        f := r.file; INC(r.page, PageSize); buf := Buf(f, r.page);
        IF buf = NIL THEN
          IF r.file.handle = NotDiskFile THEN CreateFile(r.file); END;
          WriteBuf(f, r.buf);
          IF r.page < f.length THEN ReadBuf(f, r.buf, r.page);
          ELSE r.buf.page := r.page; r.buf.lim := 1; INC(f.length);
          END;
        ELSE r.buf := buf;
          IF buf.lim = 0 THEN INC(f.length); buf.lim := 1; END;
        END;
        r.pageofs := 0;
      END;
    END;
    r.buf.data[r.pageofs] := x; INC(r.pageofs); r.buf.mod := TRUE;
  END Write;

  PROCEDURE WriteBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
  VAR src, dst, m: LONGINT; f: File; buf: Buffer;
  BEGIN
    src := SYSTEM.ADR(x);
    IF LEN(x) < n THEN HALT(1028); END;
    IF r.page # r.buf.page THEN r.buf := GetBuf(r.file, r.page); END;

    LOOP
      IF n <= 0 THEN EXIT; END;
      r.buf.mod := TRUE; dst := SYSTEM.ADR(r.buf.data) + r.pageofs;
      m := r.pageofs + n;

      IF m <= PageSize THEN
        IF m > r.buf.lim THEN r.buf.lim := SHORT(m); INC(r.file.length, n); END;
        SYSTEM.MOVE(src, dst, n); r.pageofs := SHORT(m); r.res := 0; EXIT;
      ELSE
        f := r.file; m := PageSize - r.pageofs;
        IF m > 0 THEN SYSTEM.MOVE(src, dst, m); INC(src, m); DEC(n, m); END;
        IF r.buf.lim < PageSize THEN INC(f.length, m); r.buf.lim := PageSize; END; (* last page *)
        INC(r.page, PageSize); r.pageofs := 0; buf := Buf(f, r.page);
        IF buf = NIL THEN
          IF f.handle = NotDiskFile THEN CreateFile(f); END;
          WriteBuf(f, r.buf);
          IF r.page  < f.length THEN ReadBuf(f, r.buf, r.page)
          ELSE (* extending file *) r.buf.page := r.page; r.buf.lim := 0;
          END;
        ELSE r.buf := buf;
        END;
      END;
    END;
  END WriteBytes;

  PROCEDURE WriteInt*(VAR R: Rider; x: INTEGER);
  BEGIN WriteBytes(R, x, SIZE(INTEGER));
  END WriteInt;

  PROCEDURE WriteLInt*(VAR R: Rider; x: LONGINT);
  BEGIN WriteBytes(R, x, SIZE(LONGINT));
  END WriteLInt;

  PROCEDURE WriteSet*(VAR R: Rider; x: SET);
  BEGIN WriteBytes(R, x, SIZE(SET))
  END WriteSet;

  PROCEDURE WriteBool*(VAR R: Rider; x: BOOLEAN);
  BEGIN IF x THEN Write(R, 1) ELSE Write(R, 0) END
  END WriteBool;

  PROCEDURE WriteReal*(VAR R: Rider; x: REAL);
  BEGIN WriteBytes(R, x, SIZE(REAL))
  END WriteReal;

  PROCEDURE WriteLReal*(VAR R: Rider; x: LONGREAL);
  BEGIN WriteBytes(R, x, SIZE(LONGREAL))
  END WriteLReal;

  PROCEDURE WriteString*(VAR R: Rider; x: ARRAY OF CHAR);
    VAR i: INTEGER; ch: CHAR;
  BEGIN i := 0;
    LOOP ch := x[i];
      IF ch = 0X THEN EXIT END ;
      Write(R, ch); INC(i);
      IF i = LEN(x) THEN Write(R, 0X); EXIT END
    END
  END WriteString;

  PROCEDURE WriteNum*(VAR R: Rider; x: LONGINT);
  BEGIN WHILE (x < - 64) OR (x > 63) DO Write(R, CHR(x MOD 128 + 128)); x := x DIV 128 END; Write(R, CHR(x MOD 128))
  END WriteNum;

  (* FileDir.Handle will be collected during next invocation of GC *)
  PROCEDURE FinalizeFile(f : File);
  BEGIN IF f.handle # NotDiskFile THEN Unbuffer(f); SetHandleFile(f.handle, NIL); f.handle := NIL; END;
  END FinalizeFile;

  PROCEDURE Init;
  BEGIN SYSTEM.FINALIZE(FileDesc, FinalizeFile);
  END Init;

BEGIN Init;
END Files.

