(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Gcopy;

PROCEDURE P0;
  VAR
    s : ARRAY 32 OF CHAR;
BEGIN
  COPY('string', s);
END P0;

END Gcopy.
