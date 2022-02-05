MODULE Input;
  IMPORT Kernel, Console;

  CONST
    BufferSize = 32; (* number of typeahead characters handled by the system *)

  TYPE
    MouseInfo = RECORD
      x, y : INTEGER;
      keys : SET;
    END;
    
  VAR
    mouse : MouseInfo;
    buf : ARRAY BufferSize OF CHAR;
    head, tail : INTEGER;

  PROCEDURE Available*() : INTEGER;
  BEGIN RETURN (tail - head) MOD LEN(buf);
  END Available;

  PROCEDURE Read*(VAR ch : CHAR);
  BEGIN
    IF head # tail THEN ch := buf[head]; head := (head + 1) MOD LEN(buf);
    ELSE ch := 0X;
    END;
  END Read;

  PROCEDURE Mouse*(VAR keys : SET; VAR x, y : INTEGER);
  BEGIN x := mouse.x; y := mouse.y; keys := mouse.keys;
  END Mouse;

  PROCEDURE Time*() : LONGINT; (* returns counter in millisecond increments *)
  BEGIN RETURN 0; (* FIXME: 2000.07.13 (twh): unimplemented *)
  END Time;

  PROCEDURE Init;
  BEGIN
    head := 0; tail := 0;
    mouse.x := 0; mouse.y := 0; mouse.keys := {};
  END Init;

BEGIN Init;
END Input.
