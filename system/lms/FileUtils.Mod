(* Copyright (c) 2022 Logic Magicians Software *)
MODULE FileUtils;
IMPORT
  FileDir,
  Files,
  Environment;

PROCEDURE FindAndOpenFile*(search : Environment.Elements;
                           name   : ARRAY OF CHAR ) : Files.File;
  VAR
    result : Files.File;
    info  : FileDir.PathInfo;
    fname : FileDir.Filename;
    len   : LONGINT;
    i     : INTEGER;
    path  : FileDir.Filename;

BEGIN
  IF search # NIL THEN
    FileDir.Split(name, info);
    i   := 0;
    len := LEN(search^);
    WHILE i < len DO
      COPY(search[i]^, path);
      FileDir.SetFileComponent(path, FileDir.piPath, info);
      FileDir.Join(info, fname);
      result := Files.Old(fname);
      IF result # NIL THEN
        RETURN result;
      END;
      INC(i);
    END;
    RETURN NIL;
  ELSE
    RETURN Files.Old(name);
  END;
END FindAndOpenFile;

END FileUtils.
