(* Copyright (c) 2022 Logic Magicians Software *)
MODULE FileDir;
  IMPORT SYSTEM, Kernel, HostOS;

  CONST
    InitialYear = 1900; (* Initial year of Oberon-2 date system *)

  CONST
    FnLength* = 256; (* maximum pathname length (FILENAME_MAX) *)


  TYPE
    Filename* = ARRAY FnLength OF CHAR;


  TYPE
    DIR = LONGINT; (* LMS:machine-dependent: opendir: DIR *)
    FILE = LONGINT;  (* int; POSIX file descriptor *)

  TYPE (* File enumeration callback *)
    EntryHandler* = PROCEDURE (VAR name (* R/O *) : Filename;
                               VAR continue       : BOOLEAN);

  CONST
    MaxOpenFiles = 100; (* Allows Oberon application a total of
                         * MaxOpenFiles + 5 file handles + 1 (for Oberon.Out) *)


  CONST (* VMServiceDesc.service = Kernel.VMSVCFile, SVCFileDesc op *)
    svcOpenFile   = 0;   (* SVCFileOpenDesc *)
    svcCloseFile  = 1;   (* SVCFileCloseDesc *)
    svcReadFile   = 2;   (* SVCFileReadWriteDesc *)
    svcWriteFile  = 3;   (* SVCFileReadWriteDesc *)
    svcUnlinkFile = 4;   (* SVCFileUnlinkDesc *)
    svcRenameFile = 5;   (* SVCFileRenameDesc *)
    svcSeekFile   = 6;   (* SVCFileSeekDesc *)
    svcMkstemp    = 7;   (* SVCMkstempDesc *)


  CONST (* VMServiceDesc.service = Kernel.VMSVCDirectory, SVCFileDesc op *)

    svcOpenDir    = 1;   (* SVCDirectoryDesc *)
    svcReadDir    = 2;   (* SVCDirectoryDesc *)
    svcCloseDir   = 3;   (* SVCDirectoryDesc *)

  TYPE
    SVCFileDesc = RECORD (Kernel.VMServiceDesc)
      op : LONGINT;
    END;


  TYPE
    SVCFileOpenDesc = RECORD (SVCFileDesc)
      flags    : SET;           (* in : open() flags. *)
      mode     : SET;           (* in : open() mode   *)
      pathname : LONGINT;       (* in : SYSTEM.ADR(pathname) to open. *)
      fp       : FILE;          (* out: 'FILE *'. *)
    END;


    SVCFileCloseDesc = RECORD (SVCFileDesc)
      fp : FILE;          (* in: 'FILE *'. *)
    END;


  TYPE
    SVCFileReadWriteDesc = RECORD (SVCFileDesc)
      fp       : FILE;          (* in : 'FILE *'. *)
      bytes    : LONGINT;       (* in : Number of bytes to read / write. *)
      buffer   : LONGINT;       (* in : SYSTEM.ADR(original buffer) *)
      result   : LONGINT;       (* out: Number of bytes read / written. *)
    END;


  TYPE
    SVCFileUnlinkDesc = RECORD (SVCFileDesc)
      pathname : LONGINT;       (* in : SYSTEM.ADR(pathname to unlink). *)
      result   : LONGINT;       (* out: unlink() result. *)
    END;


  TYPE
    SVCFileRenameDesc = RECORD (SVCFileDesc)
      old    : LONGINT;       (* in : SYSTEM.ADR(old pathname). *)
      new    : LONGINT;       (* in : SYSTEM.ADR(new pathname). *)
      result : LONGINT;       (* out: rename() result. *)
    END;


  CONST (* SVCFileSeekDesc mode (C seek() symbols) *)
    SeekSet* = 0;
    SeekCur* = 1;
    SeekEnd* = 2;

  TYPE
    SVCFileSeekDesc = RECORD (SVCFileDesc)
      fp     : FILE;            (* FILE * on which to seek. *)
      pos    : LONGINT;         (* Destination seek position. *)
      mode   : LONGINT;         (* Seek mode. *)
      newpos : LONGINT;         (* Actual final seek position. *)
    END;


  TYPE
    SVCOpenCloseDirDesc = RECORD (SVCFileDesc)
      path   : LONGINT;         (* in : ASCIIZ string address. *)
      handle : LONGINT;         (* out: Host OS: opendir() 'DIR' value. *)
    END;

    SVCReadDirDesc = RECORD (SVCFileDesc)
      handle : LONGINT;           (* in : Host OS: opendir() 'DIR' value. *)
      done   : BOOLEAN;           (* out: when no more files. *)
      name   : Filename;          (* out: entry file name *)
    END;


  TYPE
    SVCMkstempDesc = RECORD (SVCFileDesc)
      template : LONGINT;         (* in : ASCIIZ template address. *)
      fd       : LONGINT;         (* out: Host OS: mkstemp() result. *)
    END;


  CONST (* res values *)
    NoError* = 0; (* must match Files.NoError *)
    FileNotFound* = -1;

  TYPE
    CloseDirProc = PROCEDURE [SYSTEM.C] (dir : LONGINT (* POINTER TO DIR *)) : LONGINT; (* int *)

  CONST (* File Descriptor *)
    InvalidHandle = -1;

  CONST (* OpenFileProc flags (POSIX open()) *)
    ofRDONLY   = { };
    ofWRONLY   = {0};
    ofRDWR     = {1}; (* open mode *)
    ofCREAT    = {6};           (* O_CREAT        40H *)
    ofEXCL     = {7};           (* O_EXCL         80H *)
    ofNOCTTY   = {8};           (* O_NOCTTY      100H *)
    ofTRUNC    = {9};           (* O_TRUNC       200H *)
    ofAPPEND   = {10};          (* O_APPEND      400H *)
    ofNONBLOCK = {11};          (* O_NONBLOCK    800H *)
    ofSYNC     = {12, 20};      (* O_SYNC     101000H *)

  CONST (* OpenFileProc modes (POSIX open()) *)
    sRUSR = 8;                  (* S_IRUSR *)
    sWUSR = 7;                  (* S_IWUSR *)
    sRGRP = 5;                  (* S_IRGRP *)
    sWGRP = 4;                  (* S_IWGRP *)
    sROTH = 3;                  (* S_IROTH *)
    sWOTH = 1;                  (* S_IWOTH *)


  CONST (* Handle flags *)
    hfOpen = 0; (* file is currently open; open IN flags => c.name # NIL  *)
    hfTemp = 1; (* file is a temporary file and should be deleted when no longer referenced *)

  TYPE
    (* Handle: describes an OS file handle
     *
     * name: current name on disk;
     *        used so multiple files can have the same name
     *         (temporary names are generated)
     *
     * inv: name # NIL
     * inv: hfTemp IN flags => file should be deleted when no longer referenced
     * inv: hfOpen IN flags => file is currently open
     * inv: fp = 0 => no active Files.File: can be removed from file list
     * inv: fp # 0 => active Files.File associated
     *)
    Handle* = POINTER TO HandleDesc;
    HandleDesc = RECORD
      next, prev : Handle;
      handle : FILE;
      fp : LONGINT;
      flags : SET;
      name : Filename;
    END;

  CONST (* PathInfo flags *)
    piPath* = 0; (* path present *)
    piFile* = 1; (* filename present *)
    piExtension* = 2; (* extension present *)
    piInvalid* = 31; (* invalid structure; generated by splitting invalid
                      *  filename (97.04.07: not used yet) *)

  TYPE
    PathInfo* = RECORD
      flags- : SET;
      path : Filename;
      name : Filename;
      ext  : Filename;
    END;

  VAR
    FileList : Handle; (* (currently) open files *)

  PROCEDURE ^ SearchAndOpen(VAR path : ARRAY OF CHAR) : Handle;
  PROCEDURE ^ FindNewResource(VAR path (* R/O *) : ARRAY OF CHAR) : Handle;
  PROCEDURE ^ NewResource() : Handle;
  PROCEDURE ^ GetResource(h : Handle);
  PROCEDURE ^ KillResource(h : Handle); (* called by close procedure *)


  PROCEDURE Split*(pathname : ARRAY OF CHAR; VAR info : PathInfo);
    VAR extPos, namePos, pathPos : INTEGER;

    PROCEDURE ReverseBuf(VAR in      : Filename;
                             nofChar : INTEGER;
                         VAR out     : Filename);
      VAR
        i : INTEGER;
    BEGIN
      i := 0;
      REPEAT
        DEC(nofChar);
        out[i] := in[nofChar];
        INC(i);
      UNTIL nofChar = 0;
    END ReverseBuf;

    (* ext <=> filename extension w/ '.' *)
    (* returns position where extension begins (0..LEN(Filename)] *)
    PROCEDURE GetExtension(VAR pathname : ARRAY OF CHAR;
                           VAR ext      : Filename;
                           VAR extStart : INTEGER);
      VAR
        buf : Filename;
        i, j, len : INTEGER;
        ch : CHAR;
    BEGIN
      len := 0;
      LOOP
        IF (len >= LEN(pathname) - 1) OR (pathname[len] = 0X) THEN
          EXIT;
        END;
        INC(len);
      END;

      (* inv: len <=> (index of 0X) OR (LEN(pathname) - 1) *)
      i := len;
      buf[0] := 0X; (* 0X-terminated when reversed *)
      j := 1;
      LOOP
        ch := pathname[i];
        IF ch = '/' THEN
          EXIT;
        END;
        buf[j] := ch;
        INC(j);
        DEC(i);
        IF (i < 0) OR (j >= LEN(buf)) OR (ch = '.') THEN
          EXIT;
        END;
      END; (* path separator before a '.' => no extension *)

      (* inv: (i < 0) OR (j = index of '.', '/' *)
      (* inv: j <=> index of last char in buf + 1 *)
      IF (i >= 0) & (ch = '.') THEN
        ReverseBuf(buf, j, ext);
        extStart := i + 1;
      ELSE
        ext[0] := 0X;
        extStart := len;
      END;
    END GetExtension;


    (* extIndex <=> index of first character of file
     *  extension (0..LEN(Filename)] *)
    (* ext <=> filename (no path separators)  *)
    (* returns index of first character of filename (0..LEN(Filename)])
     * (0 => no path in pathname, ~0 => returnwd value <=>
     *                                  path separator index) *)
    PROCEDURE GetFilename(VAR pathname      : ARRAY OF CHAR;
                              extIndex      : INTEGER;
                          VAR name          : Filename;
                          VAR filenameStart : INTEGER);
      VAR
        buf : Filename;
        i, j, k : INTEGER;
        ch : CHAR;
    BEGIN
      i := extIndex - 1;
      ch := ' ';
      buf[0] := 0X; (* 0X-terminated when reversed *)
      j := 1;
      LOOP
        IF (i < 0) OR (pathname[i] = '/') OR (j >= LEN(buf)) THEN
          EXIT;
        END;
        ch := pathname[i];
        buf[j] := ch;
        DEC(i);
        INC(j);
      END;

      (* inv: (i < 0) OR (i = index of '/') *)
      (* inv: j <=> index of last char in buf + 1 *)
      ReverseBuf(buf, j, name);
      IF i >= 0 THEN (* path separator found *)
        filenameStart := i + 1;
      ELSE (* no path separator found *)
        filenameStart := 0;
      END;
    END GetFilename;


    PROCEDURE GetPath(VAR pathname  : ARRAY OF CHAR;
                          nameStart     : INTEGER;
                      VAR path      : Filename;
                      VAR pathStart : INTEGER);
      VAR
        buf : Filename;
        nofSep, i, k, len : INTEGER;
    BEGIN
      ASSERT(nameStart < LEN(pathname));
      path[0] := 0X;
      len := LEN(path);
      k := 0;
      pathStart := 0;
      i := 0;
      WHILE (k < nameStart) & (k < len) DO
        path[i] := pathname[k];
        INC(k);
        INC(i);
      END;
      (* inv: k = 1 beyond last character stored *)
      IF i >= len THEN
        k := len - 1;
      END;
      path[i] := 0X;
    END GetPath;

  BEGIN
    info.flags := {};
    GetExtension(pathname, info.ext, extPos);
    GetFilename(pathname, extPos, info.name, namePos); (* inv: a filename must exist *)
    GetPath(pathname, namePos, info.path, pathPos); (* inv: pathname ends with '/' *)
  END Split;

  PROCEDURE Join*(VAR info (* R/O *) : PathInfo;
                  VAR pathname       : Filename);
    VAR j : INTEGER;

    PROCEDURE copy(VAR source : ARRAY OF CHAR;
                       d      : INTEGER;
                   VAR name   : ARRAY OF CHAR) : INTEGER;
      VAR
        len : LONGINT;
        s   : INTEGER;
        ch  : CHAR;
    BEGIN
      s   := 0;
      len := LEN(name);
      ch  := source[0];
      WHILE (ch # 0X) & (d < len) DO
        name[d] := ch;
        INC(s);
        INC(d);
        ch := source[s];
      END;
      IF d < len THEN
        name[d] := 0X;
      ELSE
        name[len - 1] := 0X;
      END;
      RETURN d;
    END copy;

  BEGIN
    j := copy(info.path, 0, pathname);
    j := copy(info.name, j, pathname);
    j := copy(info.ext,  j, pathname);
  END Join;

  PROCEDURE GetFileComponent*(VAR info (* R/O *) : PathInfo;
                                  part           : SHORTINT;
                              VAR data           : Filename);
  BEGIN (* part IN {piPath, piFile, piExtension} *)
    IF part = piPath THEN
      COPY(info.path, data);
    ELSIF part = piFile THEN
      COPY(info.name, data);
    ELSE
      COPY(info.ext, data);
    END;
  END GetFileComponent;


  PROCEDURE SetFileComponent*(    data : Filename;
                                  part : SHORTINT;
                              VAR info : PathInfo);
  BEGIN (* part IN {piPath, piFile, piExtension} *)
    IF part = piPath THEN
      COPY(data, info.path);
    ELSIF part = piFile THEN
      COPY(data, info.name);
    ELSE
      ASSERT(part = piExtension);
      COPY(data, info.ext);
    END;
  END SetFileComponent;

  (* --------------------- OS Access ----------------------------- *)

  PROCEDURE OpenDirectory(path : ARRAY OF CHAR) : LONGINT;
    VAR
      svc : SVCOpenCloseDirDesc;
  BEGIN
    svc.op   := svcOpenDir;
    svc.path := SYSTEM.ADR(path);
    Kernel.VMService(Kernel.VMSVCDirectory, svc);
    RETURN svc.handle;
  END OpenDirectory;


  PROCEDURE CloseDirectory(handle : DIR);
    VAR
      svc : SVCOpenCloseDirDesc;
  BEGIN
    svc.op     := svcCloseDir;
    svc.handle := handle;
    Kernel.VMService(Kernel.VMSVCDirectory, svc);
  END CloseDirectory;


  PROCEDURE ReadDirectory(    handle : DIR;
                          VAR name   : Filename);
    VAR
      svc : SVCReadDirDesc;
  BEGIN
    svc.op      := svcReadDir;
    svc.handle  := handle;
    Kernel.VMService(Kernel.VMSVCDirectory, svc);

    name[0] := 0X;
    IF ~svc.done THEN
      COPY(svc.name, name);
    END;
  END ReadDirectory;


  PROCEDURE closefile(fp : FILE);
    VAR
      svc : SVCFileCloseDesc;
  BEGIN
    svc.op := svcCloseFile;
    svc.fp := fp;
    Kernel.VMService(Kernel.VMSVCFile, svc);
  END closefile;


  PROCEDURE opencreate(VAR path (* R/O *) : Filename;
                       VAR fp             : FILE;
                       VAR err            : BOOLEAN;
                           flags          : SET);
    VAR
      svc : SVCFileOpenDesc;
  BEGIN
    svc.op       := svcOpenFile;
    svc.flags    := flags;
    svc.mode     := {sRUSR, sWUSR, sRGRP, sWGRP, sROTH, sWOTH};
    svc.pathname := SYSTEM.ADR(path);
    Kernel.VMService(Kernel.VMSVCFile, svc);
    fp  := svc.fp;              (* fp # 0 -> success. *)
    err := fp = 0;              (* err => file not opened. *)
  END opencreate;


  PROCEDURE openfile(VAR path (* R/O *) : Filename;
                     VAR fp             : FILE;
                     VAR err            : BOOLEAN);
  BEGIN
    opencreate(path, fp, err, ofRDWR + ofCREAT);
  END openfile;


  PROCEDURE createfile(VAR path (* R/O *) : Filename;
                       VAR fp             : FILE;
                       VAR err            : BOOLEAN);
  BEGIN
    opencreate(path, fp, err, ofRDWR + ofCREAT + ofTRUNC);
  END createfile;


  PROCEDURE readfile(    fp    : FILE;
                         bytes : LONGINT;
                     VAR buf   : ARRAY OF SYSTEM.BYTE;
                     VAR read  : LONGINT);
    VAR
      svc : SVCFileReadWriteDesc;
  BEGIN
    svc.op     := svcReadFile;
    svc.fp     := fp;
    svc.bytes  := bytes;
    svc.buffer := SYSTEM.ADR(buf);
    Kernel.VMService(Kernel.VMSVCFile, svc);
    read := svc.result;
  END readfile;

  PROCEDURE writefile(    fp      : FILE;
                          bytes   : LONGINT;
                      VAR buf     : ARRAY OF SYSTEM.BYTE;
                      VAR written : LONGINT);
    VAR
      svc : SVCFileReadWriteDesc;
  BEGIN
    svc.op     := svcWriteFile;
    svc.fp     := fp;
    svc.bytes  := bytes;
    svc.buffer := SYSTEM.ADR(buf);
    Kernel.VMService(Kernel.VMSVCFile, svc);
    written := svc.result;
  END writefile;

  PROCEDURE unlinkfile*(VAR name (* R/O *) : Filename;
                        VAR err : BOOLEAN);
    VAR
      svc : SVCFileUnlinkDesc;
  BEGIN
    svc.op       := svcUnlinkFile;
    svc.pathname := SYSTEM.ADR(name);
    Kernel.VMService(Kernel.VMSVCFile, svc);
    err := svc.result # 0;
  END unlinkfile;

  PROCEDURE renamefile(VAR old (* R/O *) : Filename;
                       VAR new (* R/O *) : Filename;
                       VAR err : BOOLEAN);
    VAR
      svc : SVCFileRenameDesc;
  BEGIN
    svc.op  := svcRenameFile;
    svc.old := SYSTEM.ADR(old);
    svc.new := SYSTEM.ADR(new);
    Kernel.VMService(Kernel.VMSVCFile, svc);
    err := svc.result # 0;
  END renamefile;

  PROCEDURE seekfile(    fp     : FILE;
                         pos    : LONGINT;
                         mode   : SHORTINT;
                     VAR newpos : LONGINT;
                     VAR err : BOOLEAN);
    VAR
      svc : SVCFileSeekDesc;
  BEGIN
    svc.op   := svcSeekFile;
    svc.fp   := fp;
    svc.pos  := pos;
    svc.mode := mode;
    Kernel.VMService(Kernel.VMSVCFile, svc);
    newpos := svc.newpos;
    err    := newpos # pos;
  END seekfile;


  PROCEDURE mkstemp(VAR template : ARRAY OF CHAR) : LONGINT;
    VAR
      svc : SVCMkstempDesc;
  BEGIN
    svc.op       := svcMkstemp;
    svc.template := SYSTEM.ADR(template[0]);
    Kernel.VMService(Kernel.VMSVCFile, svc);
    RETURN svc.fd;
  END mkstemp;


  (* post: name[0] = 0X -> unable to make a unique name *)
  (* post: name[0] # 0X -> name is a unique filename *)
  PROCEDURE gettempfilename(VAR (* R/O *) path: ARRAY OF CHAR;
                            VAR name : ARRAY OF CHAR);
    VAR
      template : Filename;
      fd : FILE;

    PROCEDURE concat(    s : ARRAY OF CHAR;
                     VAR str : ARRAY OF CHAR);
      VAR
        i, j : INTEGER;
        ch : CHAR;
    BEGIN
      i := 0;
      WHILE (i < LEN(str)) & (str[i] # 0X) DO
        INC(i);
      END;
      IF i < LEN(str) - 1 THEN
        j := 0;
        REPEAT
          ch := s[j];
          str[i] := ch;
          INC(i);
          INC(j);
        UNTIL (ch = 0X) OR (i >= LEN(str) - 1);
        str[i] := 0X;
      END;
    END concat;

  BEGIN
    template[0] := 0X;
    IF path[0] = 0X THEN
      concat('./', template);
    ELSE
      concat(path, template); (* inv: path ends in a '/' *)
    END;
    concat('LMS-XXXXXX', template);
    fd := mkstemp(template);
    IF fd # -1 THEN
      COPY(template, name);
      closefile(fd);
    ELSE
      name[0] := 0X;
    END;
  END gettempfilename;

  (* post: new[0] = 0X -> unable to make a unique name *)
  PROCEDURE mkname(VAR orig (* R/O *), new : ARRAY OF CHAR);
    VAR
      info : PathInfo;
      path, name : Filename;
  BEGIN
    Split(orig, info);
    info.name[0] := 0X;
    info.ext[0] := 0X;
    Join(info, path);
    gettempfilename(path, name);
    COPY(name, new);
  END mkname;

  PROCEDURE open*(VAR path (* R/O *) : Filename;
                  VAR h : Handle;
                  VAR err : BOOLEAN);
    VAR
      handle : FILE;
      h0 : Handle;
  BEGIN
    h0 := FindNewResource(path);
    IF ~(hfOpen IN h0.flags) THEN
      openfile(path, handle, err);
      IF ~err THEN
        h0.handle := handle;
        INCL(h0.flags, hfOpen);
        COPY(path, h0.name);
        h := h0;
      ELSE
        h := NIL;
      END;
    ELSE
      err := FALSE;
      h := h0;
    END;
  END open;

  PROCEDURE create*(VAR filename (* R/O *) : ARRAY OF CHAR;
                    VAR h : Handle;
                    VAR err : BOOLEAN);
    VAR
      temppath : Filename;
      h0 : Handle;
  BEGIN
    h0 := NewResource();
    INCL(h0.flags, hfTemp); (* unregistered files must be deleted *)
    mkname(filename, temppath);
    createfile(temppath, h0.handle, err);
    IF ~err THEN
      INCL(h0.flags, hfOpen);
      COPY(temppath, h0.name);
      h := h0;
    ELSE
      h := NIL;
    END;
  END create;

  PROCEDURE close*(h : Handle);
  BEGIN
    IF hfOpen IN h.flags THEN
      closefile(h.handle);
      EXCL(h.flags, hfOpen);
    END;
  END close;

  PROCEDURE unlink*(h : Handle; VAR err : BOOLEAN);
    VAR newname : Filename;
  BEGIN
    IF hfOpen IN h.flags THEN
      close(h);
      mkname(h.name, newname);
      renamefile(h.name, newname, err);
      COPY(newname, h.name);
      INCL(h.flags, hfTemp);
    ELSE
      (* no open files; delete immediately *)
      unlinkfile(h.name, err);
      KillResource(h);
    END;
  END unlink;

  (* change filename or delete file; avoids name conflicts during renaming *)
  PROCEDURE namedodge(VAR name (* R/O *) : Filename);
    VAR
      h : Handle;
      newname : Filename;
      fileH : FILE;
      err : BOOLEAN;
  BEGIN
    h := SearchAndOpen(name);
    IF h # NIL THEN (* A reference to a file of the same name exists;
                     * get rid of the name. *)
      (* inv: hfOpen IN h.flags *)
      close(h);
      mkname(h.name, newname);
      renamefile(h.name, newname, err);
      COPY(newname, h.name);
      INCL(h.flags, hfTemp);
    ELSE
      openfile(name, fileH, err);
      IF ~err THEN (* disk file exists *)
        closefile(fileH);
        unlinkfile(name, err);
      END;
    END;
  END namedodge;

  PROCEDURE renamehandle*(    h : Handle;
                          VAR new (* R/O *) : Filename;
                          VAR err : BOOLEAN);
  BEGIN
    IF h.name # new THEN
      namedodge(new);
      close(h);
      renamefile(h.name, new, err);
      COPY(new, h.name);
      EXCL(h.flags, hfTemp);
    END;
  END renamehandle;


  PROCEDURE rename*(VAR old (* R/O *) : Filename;
                    VAR new (* R/O *) : Filename;
                    VAR err : BOOLEAN);
    VAR
      oldH, newH : Handle;
      newname : Filename;
  BEGIN
    IF old # new THEN
      oldH := SearchAndOpen(old);
      IF oldH # NIL THEN
        (* currently open descriptor *)
        renamehandle(oldH, new, err);
      ELSE
        (* nothing open, rename physical file *)
        namedodge(new);
        renamefile(old, new, err);
      END;
    END;
  END rename;

  PROCEDURE read*(    h : Handle;
                      bytes : LONGINT;
                  VAR buf : ARRAY OF SYSTEM.BYTE;
                  VAR read : LONGINT);
  BEGIN
    GetResource(h);
    readfile(h.handle, bytes, buf, read);
  END read;

  PROCEDURE write*(    h : Handle;
                       bytes : LONGINT;
                   VAR buf : ARRAY OF SYSTEM.BYTE;
                   VAR nofWritten : LONGINT);
    VAR err : BOOLEAN;
  BEGIN
    GetResource(h);
    writefile(h.handle, bytes, buf, nofWritten);
  END write;

  PROCEDURE getname*(h : Handle; VAR name : Filename);
  BEGIN
    COPY(h.name, name);
  END getname;

  PROCEDURE getfiletimestamp(    h : Handle;
                             VAR create, (* host OS create time *)
                                 access, (* host OS last access time *)
                                 modify  (* host OS last modification time *) : LONGINT;
                             VAR err : BOOLEAN);
    VAR
      r : LONGINT;
  BEGIN
    GetResource(h);
    (* 2000.08.06: OSfstatfile not implemented *) (*r := OSfstatfile(h.handle, buf);*)
    r := -1;
    IF r # -1 THEN
      err := FALSE;
    ELSE
      err := TRUE;
    END;
  END getfiletimestamp;


  PROCEDURE MakeOberonTime(year, month, day, hour, minute, second : LONGINT;
                           VAR time, date : LONGINT);
  BEGIN
    date := ASH(year - InitialYear, 5 + 4) + ASH(month, 5) + day;
    time := ASH(hour, 6 + 6) + ASH(minute, 6) + second;
  END MakeOberonTime;


  (* ---------------------------------------------------------- *)
  (* Returns file timestamp:
     time as seconds from midnight, date as days since 1990.01.01
     (in Oberon format)
  *)
  PROCEDURE gettimestamp*(    h : Handle;
                          VAR time, date : LONGINT);
    VAR
      create, access, modify : LONGINT; err : BOOLEAN;
      year, month, day, hour, minute, second : LONGINT;
  BEGIN
    getfiletimestamp(h, create, access, modify, err);
    IF ~err THEN
      HostOS.SplitSystemTime(access, year, month, day, hour, minute, second);
      MakeOberonTime(year, month, day, hour, minute, second, time, date);
    ELSE
      time := 0;
      date := 0;
    END;
  END gettimestamp;


  PROCEDURE seek*(    h : Handle;
                      pos : LONGINT;
                      mode : SHORTINT;
                  VAR newpos : LONGINT;
                  VAR err : BOOLEAN);
  BEGIN
    GetResource(h);
    seekfile(h.handle, pos, mode, newpos, err);
  END seek;

  (* ----------------- LRU ----------------- *)
  PROCEDURE NewHandle(VAR h : Handle);
    VAR c : Handle;
  BEGIN
    NEW(c);
    c.flags := {};
    c.next := NIL;
    c.prev := NIL;
    c.fp := 0;
    c.handle := InvalidHandle;
    c.name[0] := 0X;
    h := c;
  END NewHandle;

  PROCEDURE Autoclose;
    VAR i : INTEGER; c : Handle;
  BEGIN (* close least recently used file *)
    i := 0;
    c := FileList.next;
    WHILE (c # FileList) & (i < MaxOpenFiles) DO
      IF hfOpen IN c.flags THEN
        INC(i);
      END;
      c := c.next;
    END;
    IF i >= MaxOpenFiles THEN
      c := FileList.prev;
      WHILE (c # FileList) & ~(hfOpen IN c.flags) DO
        c := c.prev;
      END; (* find LRU open file *)
      c.prev.next := c.next;
      c.next.prev := c.prev; (* unlink *)
      c.next := FileList;
      c.prev := FileList.prev;
      FileList.prev := c;
      c.prev.next := c; (* relink at end *)
      close(c);
    END;
  END Autoclose;

  (* looks for a handle referencing the given path.  if found,
   * moves to beginning of open file list *)
  PROCEDURE SearchAndOpen(VAR path (* R/O *) : ARRAY OF CHAR) : Handle;
    VAR c : Handle; err : BOOLEAN;
  BEGIN
    c := FileList.next;
    WHILE (c # FileList) & (c.name # path) DO
      c := c.next;
    END;
    IF c # FileList THEN (* on list; move to front *)
      IF ~(hfOpen IN c.flags) THEN
        Autoclose;
        openfile(c.name, c.handle, err);
        INCL(c.flags, hfOpen);
      END;
      c.prev.next := c.next;
      c.next.prev := c.prev; (* unlink *)
      c.next := FileList.next;
      c.prev := FileList;
      FileList.next := c;
      c.next.prev := c; (* relink at front *)
    ELSE
      c := NIL;
    END;
    RETURN c;
  END SearchAndOpen;

  PROCEDURE NewResource() : Handle;
    VAR c : Handle;
  BEGIN
    Autoclose;
    NewHandle(c);
    c.next := FileList.next;
    c.prev := FileList;
    FileList.next := c;
    c.next.prev := c;
    RETURN c;
  END NewResource;

  PROCEDURE FindNewResource(VAR path (* R/O *) : ARRAY OF CHAR) : Handle;
    VAR h : Handle;
  BEGIN
    h := SearchAndOpen(path);
    IF h = NIL THEN
      h := NewResource();
    END;
    RETURN h;
  END FindNewResource;

  PROCEDURE GetResource(h : Handle);
    VAR  err : BOOLEAN;
  BEGIN
    ASSERT(h # NIL, 1037);
    IF ~(hfOpen IN h.flags) THEN
      Autoclose;
      openfile(h.name, h.handle, err);
      INCL(h.flags, hfOpen);
    END;
  END GetResource;

  PROCEDURE KillResource(h : Handle);
    VAR err : BOOLEAN;
  BEGIN
    h.prev.next := h.next;
    h.next.prev := h.prev;
    h.name[0] := 0X;
  END KillResource;


  (* ----------------- File Enumeration ----------------- *)
  (* LMS:different-implementation: does not honor prefix *)
  PROCEDURE Enumerate*(prefix: ARRAY OF CHAR; proc: EntryHandler);
    VAR
      path     : ARRAY 2 OF CHAR;
      dir      : DIR;
      continue : BOOLEAN;
      name     : Filename;
  BEGIN
    COPY('.', path);
    dir := OpenDirectory(path);
    IF dir # 0 THEN
      ReadDirectory(dir, name);
      IF name[0] # 0X THEN
        REPEAT
          proc(name, continue);
          ReadDirectory(dir, name);
        UNTIL (name[0] = 0X) OR ~continue;
      END;
      CloseDirectory(dir);
    END;
  END Enumerate;


  PROCEDURE finish(h : Handle); (* close and remove from file system *)
    VAR err : BOOLEAN;
  BEGIN
    close(h);
    IF hfTemp IN h.flags THEN
      unlinkfile(h.name, err);
    END;
    KillResource(h);
  END finish;


  PROCEDURE GetHandleFile*(h : Handle) : LONGINT;
  BEGIN (* inv: (h.fp = 0) OR defined(SYSTEM.VAL(Files.File, h.hp)^) *)
    RETURN h.fp;
  END GetHandleFile;

  (* fp = 0 => no references to this Handle exist; disconnect file *)
  PROCEDURE SetHandleFile*(h : Handle; fp : LONGINT);
  BEGIN (* inv: (h # NIL) & defined(h^) *)
    h.fp := fp;
    IF fp = 0 THEN
      finish(h);
    END;
  END SetHandleFile;

  PROCEDURE terminate*;
    VAR h : Handle;
  BEGIN
    WHILE FileList.next # FileList DO
      h := FileList.next;
      finish(h);
    END;
  END terminate;

BEGIN
  (* Dummy list header (for ease of list handling). *)
  NewHandle(FileList);
  FileList.next := FileList;
  FileList.prev := FileList;
END FileDir.
