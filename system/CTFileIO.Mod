(* Copyright (c) 2021 Logic Magicians Software
 *
 * Test code around Files.Mod.
 *)
MODULE CTFileIO;
IMPORT Files, Console;
VAR
  buf : ARRAY 4096 * 5 OF CHAR;

PROCEDURE SingleByte(f : Files.File);
  VAR
    r : Files.Rider;
    ch : CHAR;
BEGIN
  Console.Str("SingleByteRead");
  Console.Ln;
  Files.Set(r, f, 0);
  WHILE ~r.eof DO
    Files.Read(r, ch);
    Console.Ch(ch);
  END;
  Console.Ln;
  Console.Ln;
END SingleByte;


PROCEDURE BlockRead(f : Files.File);
  PROCEDURE Read(pos, n : LONGINT);
    VAR
      r : Files.Rider;
      i : INTEGER;
      ch : CHAR;
  BEGIN

    ASSERT(n < LEN(buf));
    Console.Str("Read ");
    Console.Int(n, 5);
    Console.Str(" bytes at ");
    Console.Int(pos, 5);
    Console.Ln;

    (* Initialize buffer to known value that is not in the file. *)
    i := 0;
    WHILE i < LEN(buf) DO
      buf[i] := '^';
      INC(i);
    END;
    Files.Set(r, f, pos);
    Files.ReadBytes(r, buf, n);
    i := 0;
    WHILE i < n DO
      ch := CHR(ORD('0') + ((pos + i) DIV 4096));
      IF buf[i] # ch THEN
        Console.Str("Buffer[ ");
        Console.Hex(i);
        Console.Str("] value: '");
        Console.Ch(buf[i]);
        Console.Str("' # '");
        Console.Ch(ch);
        Console.Ch("'");
        Console.Ln;
      END;
      INC(i);
    END;
  END Read;
BEGIN
  Console.Str("BlockRead");
  Console.Ln;
  Read(0, 4097);
  Read(2048, 4 * 4096);
END BlockRead;


PROCEDURE Test*;
VAR
  f : Files.File;
BEGIN

  (* The data file that is opened contains, consecutively:
   *
   *   + 4096 '0'
   *   + 4096 '1'
   *   + 4096 '2'
   *   + 4096 '3'
   *   + 4096 '4'
   *)
  f := Files.Old("CTFileIO.data");
  ASSERT(f # NIL);
  SingleByte(f);
  BlockRead(f);
END Test;

END CTFileIO.
