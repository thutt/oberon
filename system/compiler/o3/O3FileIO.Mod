MODULE O3FileIO;
IMPORT
  SYSTEM,
  Config:=O3Config,
  Console,
  Environment,
  FileDir,
  Files,
  FileUtils,
  Objects,
  Texts;

  CONST
    debug = FALSE;

  TYPE
    Text = POINTER TO TextDesc;
    Binary = POINTER TO BinaryDesc;

    File = POINTER TO FileDesc;
    FileDesc = RECORD (Config.FileDesc)
      next : File;
    END;

    (* Oberon source files.
      They can be treated as raw files, but it is better to use Texts.Text since
      that data structure will ignore elements (and Files.Rider does not).
    *)
    TextDesc = RECORD (FileDesc)
      f : Texts.Text;
      r : Texts.Reader;
    END;

    BinaryDesc = RECORD (FileDesc)
      f : Files.File;
      r : Files.Rider;
    END;

  VAR
    (* files which are open *)
    OpenFiles : File;

  VAR
    SearchPath : Environment.Elements;

  PROCEDURE AddOpenFile(f : File);
  BEGIN f.next := OpenFiles.next; OpenFiles.next := f;
  END AddOpenFile;

  PROCEDURE RemoveOpenFile(f : File);
    VAR c, p : File;
  BEGIN p := OpenFiles; c := OpenFiles.next;
    WHILE (c # NIL) & (c # f) DO p := c; c := c.next; END;
    ASSERT(c # NIL); (* inv: f must be on the list *)
    p.next := c.next;
  END RemoveOpenFile;

  PROCEDURE IsOpen(h : File) : BOOLEAN;
    VAR f : File;
  BEGIN f := OpenFiles.next; WHILE (f # NIL) & (f # h) DO f := f.next; END; RETURN f = h;
  END IsOpen;

  PROCEDURE SetFileFlags(h : Config.File);
  BEGIN
    IF h IS Binary THEN h.eof := h(Binary).r.eof; h.err := h(Binary).r.res # 0;
    ELSE ASSERT(h IS Text); h.eof := h(Text).r.eot; h.err := FALSE;
    END;
  END SetFileFlags;

  PROCEDURE opentext(name : ARRAY OF CHAR; pos : LONGINT) : Config.File;
    VAR t : Text;
  BEGIN
    NEW(t); (* opening a text does not produce an error? *)
    COPY(name, t.name);
    Texts.New;
    t.f := Objects.NewObj(Texts.Text);
    Texts.Open(t.f, name);
    Texts.OpenReader(t.r, t.f, pos);
    AddOpenFile(t);
    RETURN t;
  END opentext;

  PROCEDURE openbinary(name : ARRAY OF CHAR; pos : LONGINT) : Config.File;
    VAR
      b : Binary;
      f : Files.File;
  BEGIN
    f := Files.Old(name);
    IF f # NIL THEN
      NEW(b);
      COPY(name, b.name);
      b.f := f;
      Files.Set(b.r, b.f, 0);
      AddOpenFile(b);
      RETURN b;
    ELSE
      RETURN Config.InvalidHandle;
    END;
  END openbinary;

  PROCEDURE findandopenbinary(name : ARRAY OF CHAR) : Config.File;
    VAR
      b : Binary;
      f : Files.File;
      symName : FileDir.Filename;
  BEGIN
    f := FileUtils.FindAndOpenFile(SearchPath, symName);
    IF f # NIL THEN
      NEW(b);
      COPY(name, b.name);
      b.f := f;
      Files.Set(b.r, b.f, 0);
      AddOpenFile(b);
      RETURN b;
    ELSE
      RETURN Config.InvalidHandle;
    END;
  END findandopenbinary;

  PROCEDURE createtext(name : ARRAY OF CHAR) : Config.File;
  BEGIN RETURN Config.InvalidHandle; (* not supported by this compiler *)
  END createtext;

  PROCEDURE createbinary(name : ARRAY OF CHAR) : Config.File;
    VAR F : Binary; f : Files.File;
  BEGIN
    f := Files.New(name);
    IF f # NIL THEN
      NEW(F);
      F.f := f;
      Files.Set(F.r, F.f, 0);
      AddOpenFile(F);
      RETURN F;
    ELSE
      RETURN Config.InvalidHandle;
    END;
  END createbinary;

  PROCEDURE close(h : Config.File);
  BEGIN
    ASSERT((h IS Binary) OR (h IS Text));
    RemoveOpenFile(h(File));
    IF h IS Binary THEN
      Files.Close(h(Binary).f);
    ELSE (* nop *)
    END;
    h.err := FALSE;
    h.eof := FALSE;
  END close;

  PROCEDURE delete(h : Config.File);
  BEGIN ASSERT(~IsOpen(h(File)), 1024); ASSERT(h IS Binary, 1025); Files.Purge(h(Binary).f);
  END delete;

  PROCEDURE register(h : Config.File);
  BEGIN ASSERT(h IS Binary); Files.Register(h(Binary).f);
  END register;

  PROCEDURE set(h : Config.File; pos : LONGINT);
  BEGIN ASSERT((h IS Binary) OR (h IS Text));
    IF h IS Binary THEN Files.Set(h(Binary).r, h(Binary).f, pos); h.eof := h(Binary).r.eof; h.err := h(Binary).r.res # 0;
    ELSE Texts.OpenReader(h(Text).r, h(Text).f, pos); h.eof := h(Text).r.eot; h.err := FALSE;
    END;
  END set;

  PROCEDURE pos(h : Config.File) : LONGINT;
  BEGIN ASSERT((h IS Binary) OR (h IS Text));
    IF h IS Binary THEN RETURN Files.Pos(h(Binary).r);
    ELSE RETURN Texts.Pos(h(Text).r);
    END;
  END pos;

  PROCEDURE write(h : Config.File; ch : CHAR);
  BEGIN ASSERT(h IS Binary); Files.Write(h(Binary).r, ch); SetFileFlags(h);
  END write;

  PROCEDURE writelint(h : Config.File; l : LONGINT);
  BEGIN ASSERT(h IS Binary); Files.WriteLInt(h(Binary).r, l); SetFileFlags(h);
  END writelint;

  PROCEDURE writeset(h : Config.File; s : SET);
  BEGIN ASSERT(h IS Binary); Files.WriteSet(h(Binary).r, s); SetFileFlags(h);
  END writeset;

  PROCEDURE writenum(h : Config.File; l : LONGINT);
  BEGIN ASSERT(h IS Binary); Files.WriteNum(h(Binary).r, l); SetFileFlags(h);
  END writenum;

  PROCEDURE writereal(h : Config.File; r : REAL);
  BEGIN ASSERT(h IS Binary); Files.WriteReal(h(Binary).r, r); SetFileFlags(h);
  END writereal;

  PROCEDURE writelreal(h : Config.File; r : LONGREAL);
  BEGIN ASSERT(h IS Binary); Files.WriteLReal(h(Binary).r, r); SetFileFlags(h);
  END writelreal;

  PROCEDURE writebytes(h : Config.File; VAR buf : ARRAY OF SYSTEM.BYTE; len : LONGINT);
  BEGIN ASSERT(h IS Binary); Files.WriteBytes(h(Binary).r, buf, len); SetFileFlags(h);
  END writebytes;

  PROCEDURE read(h : Config.File; VAR ch : CHAR);
  BEGIN ASSERT((h IS Binary) OR (h IS Text));
    IF h IS Binary THEN Files.Read(h(Binary).r, ch);
    ELSE Texts.Read(h(Text).r, ch); h.eof := h(Text).r.eot; h.err := FALSE;
    END;
    SetFileFlags(h);
  END read;

  PROCEDURE readlint(h : Config.File; VAR l : LONGINT);
  BEGIN ASSERT(h IS Binary); Files.ReadLInt(h(Binary).r, l); SetFileFlags(h);
  END readlint;

  PROCEDURE readset(h : Config.File; VAR s : SET);
  BEGIN ASSERT(h IS Binary); Files.ReadSet(h(Binary).r, s); SetFileFlags(h);
  END readset;

  PROCEDURE readnum(h : Config.File; VAR l : LONGINT);
  BEGIN ASSERT(h IS Binary); Files.ReadNum(h(Binary).r, l); SetFileFlags(h);
  END readnum;

  PROCEDURE readreal(h : Config.File; VAR l : REAL);
  BEGIN ASSERT(h IS Binary); Files.ReadReal(h(Binary).r, l); SetFileFlags(h);
  END readreal;

  PROCEDURE readlreal(h : Config.File; VAR l : LONGREAL);
  BEGIN ASSERT(h IS Binary); Files.ReadLReal(h(Binary).r, l); SetFileFlags(h);
  END readlreal;

  PROCEDURE readbytes(h : Config.File; VAR buf : ARRAY OF SYSTEM.BYTE; len : LONGINT);
  BEGIN ASSERT(h IS Binary); Files.ReadBytes(h(Binary).r, buf, len); SetFileFlags(h);
  END readbytes;

  (** Filename  *)

  (*
    pre: ASCIIZ(name)
    pre: ASCIIZ(ext)
    pre: LEN(fname) >= LEN(name) + LEN(ext)
    post: (Ei: 0 <= i < LEN(fname): fname[i] = 0X)
  *)
  PROCEDURE makename(srcName : ARRAY OF CHAR;
                     name, ext : ARRAY OF CHAR;
                     VAR fname : ARRAY OF CHAR);
    VAR
      info : FileDir.PathInfo;
      temp : FileDir.Filename;
  BEGIN
    FileDir.Split(srcName, info);
    COPY(name, temp);
    FileDir.SetFileComponent(temp, FileDir.piFile, info);
    COPY(ext, temp);
    FileDir.SetFileComponent(temp, FileDir.piExtension, info);
    FileDir.Join(info, temp);
    COPY(temp, fname);
  END makename;

  PROCEDURE NILGlobalPointers;
  BEGIN OpenFiles := NIL;
  END NILGlobalPointers;

  PROCEDURE ModuleBegin(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN NILGlobalPointers;
    NEW(OpenFiles); (* create a dummy link for easy list handling *) OpenFiles.next := NIL; RETURN TRUE;
  END ModuleBegin;

  PROCEDURE ModuleEnd(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN NILGlobalPointers; RETURN TRUE;
  END ModuleEnd;

  PROCEDURE SetFileIO;
    VAR x : Config.FileIO;
  BEGIN NEW(x); x.x := 0;
    INC(x.x); x.opentext := opentext;
    INC(x.x); x.openbinary:= openbinary;
    INC(x.x); x.findandopenbinary:= findandopenbinary;
    INC(x.x); x.createtext := createtext;
    INC(x.x); x.createbinary:= createbinary;
    INC(x.x); x.close := close;
    INC(x.x); x.delete := delete;

    INC(x.x); x.set := set;
    INC(x.x); x.pos := pos;
    INC(x.x); x.makename := makename;
    INC(x.x); x.register := register;

    INC(x.x); x.write := write;
    INC(x.x); x.writelint := writelint;
    INC(x.x); x.writeset := writeset;
    INC(x.x); x.writenum := writenum;
    INC(x.x); x.writereal := writereal;
    INC(x.x); x.writelreal := writelreal;
    INC(x.x); x.writebytes := writebytes;

    INC(x.x); x.read := read;
    INC(x.x); x.readlint := readlint;
    INC(x.x); x.readset := readset;
    INC(x.x); x.readnum := readnum;
    INC(x.x); x.readreal := readreal;
    INC(x.x); x.readlreal := readlreal;
    INC(x.x); x.readbytes := readbytes;

    Config.SetFileIO(x);
  END SetFileIO;

BEGIN
  IF debug THEN Console.Str("loaded file i/o subsystem"); Console.Ln; END;
  Config.ControlModule(ModuleBegin, ModuleEnd); SetFileIO;
  SearchPath := FileDir.GetEnvironmentPaths("SKL_SEARCH_PATH");
END O3FileIO.
