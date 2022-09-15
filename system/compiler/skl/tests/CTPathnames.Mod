(* Copyright (c) 2022 Logic Magicians Software *)
(* Test for Pathnames.Mod *)

MODULE CTPathnames;
IMPORT
  Console,
  Environment,
  Pathnames;

VAR
  home : Environment.Text;

PROCEDURE match(ep : Pathnames.Element; VAR (* R/O *) expected : ARRAY OF CHAR);
  VAR
    pass : BOOLEAN;
BEGIN
  pass := ((expected = "") & (ep = NIL)) OR ((ep # NIL) & (ep^ = expected));
  IF pass THEN
    Console.Str("PASS  ");
  ELSE
    Console.Str("FAIL  ");
  END;
  IF ep # NIL THEN
    Console.Str("'");
    Console.Str(ep^);
    Console.Str("'");
  ELSE
    Console.Str("NIL");
  END;
  Console.Str("  --> (expected) '");
  Console.Str(expected);
  Console.Str("'");
  Console.Ln;
  ASSERT(pass);
END match;

PROCEDURE MatchPathname(path : Pathnames.Pathname; expected : ARRAY OF CHAR);
BEGIN
  match(path.Pathname(), expected);
END MatchPathname;

  
PROCEDURE MatchDirname(path : Pathnames.Pathname; expected : ARRAY OF CHAR);
BEGIN
  match(path.Dirname(), expected);
END MatchDirname;

  
PROCEDURE MatchBasename(path : Pathnames.Pathname; expected : ARRAY OF CHAR);
BEGIN
  match(path.Basename(), expected);
END MatchBasename;

  
PROCEDURE MatchExtension(path : Pathnames.Pathname; expected : ARRAY OF CHAR);
BEGIN
  match(path.Extension(), expected);
END MatchExtension;

  
PROCEDURE MatchFilename(path : Pathnames.Pathname; expected : ARRAY OF CHAR);
  VAR
    ep : Pathnames.Element;
BEGIN
  ep   := path.Filename();
  match(ep, expected);
END MatchFilename;

  
PROCEDURE TestCreate;
  VAR
    p : Pathnames.Pathname;

BEGIN
  p := Pathnames.Create("/");
  MatchPathname(p, "/");
  p := Pathnames.Create("/mount/etc/fstab");
  MatchPathname(p, "/mount/etc/fstab");

  p := Pathnames.Create(".dot/etc/fstab");
  MatchPathname(p, ".dot/etc/fstab");

  p := Pathnames.Create(".dot/./etc/fstab");
  MatchPathname(p, ".dot/./etc/fstab");

  p := Pathnames.Create(".dot/./../etc/fstab");
  MatchPathname(p, ".dot/./../etc/fstab");

  p := Pathnames.Create("/etc/fstab");
  MatchPathname(p, "/etc/fstab");

  p := Pathnames.Create("etc/fstab");
  MatchPathname(p, "etc/fstab");

  p := Pathnames.Create("e/tc/fstab");
  MatchPathname(p, "e/tc/fstab");

  p := Pathnames.Create("e//tc//fstab");
  MatchPathname(p, "e/tc/fstab");

  p := Pathnames.Create("e//tc//fstab/");
  MatchPathname(p, "e/tc/fstab");

  p := Pathnames.Create("e");
  MatchPathname(p, "e");

  p := Pathnames.Create("//e");
  MatchPathname(p, "/e");

  p := Pathnames.Create("~/.emacs");
  MatchDirname(p, home^);
  MatchBasename(p, ".emacs");
  MatchExtension(p, "");

  p := Pathnames.Create("~/.emacs.save");
  MatchDirname(p, home^);
  MatchFilename(p, ".emacs.save");
  MatchBasename(p, ".emacs");
  MatchExtension(p, ".save");

  p := Pathnames.Create(".emacs.save");
  ASSERT(p.elements = NIL);     (* No path, just a filename. *)
  p := Pathnames.Create("");
  ASSERT(p = NIL);     (* No input. *)
END TestCreate;


PROCEDURE TestDelete;
  VAR 
    p : Pathnames.Pathname;
    success : BOOLEAN;
BEGIN
  p := Pathnames.Create("/example/deep/0/1/2/3/4/5/6/7/config.in");
  p.Delete(4, 8, success);
  ASSERT(success);
  MatchPathname(p, "/example/deep/0/1/6/7/config.in");

  p.Delete(-1, 20, success);   (* Invalid indices. *)
  ASSERT(~success);

  p := Pathnames.Create("/etc/fstab");
  p.Delete(0, 2, success);     (* Cannot delete whole pathname. *)
  ASSERT(~success);
END TestDelete;  


PROCEDURE TestFilenameExtension;
  VAR 
    p : Pathnames.Pathname;
    str : Pathnames.Element;
    success : BOOLEAN;
BEGIN
  p := Pathnames.Create("/example/0/1/2/3/4/5/6/7/config.in");
  p.SetExtension(".out", success);
  ASSERT(success);
  p.SetBasename("a", success);
  ASSERT(success);
  MatchPathname(p, "/example/0/1/2/3/4/5/6/7/a.out");

  p.SetBasename("", success);
  ASSERT(~success);

  p.SetExtension("", success);
  ASSERT(success);
  MatchPathname(p, "/example/0/1/2/3/4/5/6/7/a");

  p.SetExtension(".skl", success);
  ASSERT(success);
  MatchPathname(p, "/example/0/1/2/3/4/5/6/7/a.skl");
END TestFilenameExtension;


PROCEDURE TestInsert;
  VAR 
    p   : Pathnames.Pathname;
    usr : Pathnames.Pathname;
    str : Pathnames.Element;
    success : BOOLEAN;
BEGIN
  p   := Pathnames.Create("local/bin/emacs");
  usr := Pathnames.Create("/usr");

  p.Insert(0, usr, success);
  ASSERT(success);
  MatchPathname(p, "/usr/local/bin/emacs");
END TestInsert;

PROCEDURE TestDotFile;
  VAR 
    p     : Pathnames.Pathname;
BEGIN
  p := Pathnames.Create(".emacs");
  MatchPathname(p, ".emacs");
  MatchDirname(p, "");
  MatchBasename(p, ".emacs");
  MatchExtension(p, "");

  p := Pathnames.Create(".emacs.save");
  MatchPathname(p, ".emacs.save");
  MatchDirname(p, "");
  MatchBasename(p, ".emacs");
  MatchExtension(p, ".save");

  p := Pathnames.Create(".emacs.save.save");
  MatchPathname(p, ".emacs.save.save");
  MatchDirname(p, "");
  MatchBasename(p, ".emacs.save");
  MatchExtension(p, ".save");

  p := Pathnames.Create("/.emacs.save.save.");
  MatchPathname(p, "/.emacs.save.save.");
  MatchDirname(p, "/");
  MatchBasename(p, ".emacs.save.save");
  MatchExtension(p, ".");
END TestDotFile;


PROCEDURE TestAbsolute;
  VAR p : Pathnames.Pathname;
BEGIN
  p := Pathnames.Create("/proc/cpuinfo");
  MatchPathname(p, "/proc/cpuinfo");
  p.SetAbsolute(FALSE);
  MatchPathname(p, "proc/cpuinfo");
END TestAbsolute;


PROCEDURE Test*;
BEGIN
  TestCreate;
  TestDelete;
  TestInsert;
  TestFilenameExtension;
  TestDotFile;
  TestAbsolute;
END Test;

BEGIN
  home := Environment.Lookup("HOME");
END CTPathnames.
