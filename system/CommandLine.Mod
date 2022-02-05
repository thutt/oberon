(* Copyright (c) 2000, 2021-2022 Logic Magicians Software *)
MODULE CommandLine;  (* A command line is a series of (tab, space)-delimitted arguments *)
  IMPORT Kernel, Console;

  CONST
    OptionChar* = '-';

  TYPE
    Parameter* = POINTER TO ARRAY OF CHAR;
    ParmList = POINTER TO ParmListDesc;
    ParmListDesc = RECORD
      next : ParmList;
      text : Parameter;      
    END;
    
    ParmListRoot = POINTER TO ParmListRootDesc;
    ParmListRootDesc = RECORD (ParmListDesc)
      last : ParmList;
    END;

  VAR    
    (* Argument 0 <=> oberon loader
     * Argument 1 <=> Module.Command to load & execute
     * Argument 2..ParameterCount - 1 <=> arguments for Argument 1
     *
     * inv: 0 < ParameterCount <= MAX(INTEGER)
     *)
    ParameterCount- : INTEGER;

  VAR
    cmdline : ARRAY 4096 OF CHAR; (* Ei: 0 <= i < LEN(cmdline): cmdline[i] = 0X *)
    parmlist : ParmList;

  PROCEDURE GetArg*(num : INTEGER) : Parameter;
    VAR pl : ParmList;
  BEGIN pl := parmlist.next;
    WHILE (pl # NIL) & (num > 0) DO DEC(num); pl := pl.next; END;
    IF pl # NIL THEN RETURN pl.text; ELSE RETURN NIL; END;
  END GetArg;

  PROCEDURE InitParm( parm : ParmList);
  BEGIN parm.next := NIL; parm.text := NIL;
  END InitParm;

  PROCEDURE AddParm(parm : ParmList);
  BEGIN (* pre: parmlist # NIL *)
    WITH parmlist:ParmListRoot DO
      IF parmlist.last # NIL THEN parmlist.last.next := parm;
      ELSE parmlist.next := parm;
      END;
      parmlist.last := parm;
    END;
  END AddParm;

  PROCEDURE NewParm(beg, len : INTEGER);
    VAR parm : ParmList; i : INTEGER;
  BEGIN
    IF len > 0 THEN i := 0; NEW(parm); InitParm(parm); AddParm(parm); NEW(parm.text, len + 1);
      WHILE len > 0 DO parm.text[i] := cmdline[beg]; INC(i); INC(beg); DEC(len); END;
      parm.text[i] := 0X;
    END;
  END NewParm;
  
  (* pre: 0 <= i < LEN(cmdline) *)
  (* pre: defined(cmdline) *)
  (* post: (0 <= result < LEN(cmdline)) & (result is length of parameter) *)
  PROCEDURE ParseNextParm(i : INTEGER) : INTEGER;
    VAR beg, j, len : INTEGER; ch : CHAR;
  BEGIN
    LOOP (* skip leading tabs & spaces *)
      ch := cmdline[i];
      IF (ch # 9X) & (ch # ' ') OR (ch = 0X) THEN EXIT; END;
      INC(i);
    END;

    IF ch # 0X THEN
      len := 0;
      IF ch = '"' THEN (* collect until ending quote or end of command line *)
        INC(i); beg := i;
        LOOP
          ch := cmdline[i];
          IF (ch = '"' ) OR (ch = 0X) THEN EXIT; END;
          INC(i); INC(len);
        END;
      ELSE (* copy characters directly, until tab or space or end of command line *)
        beg := i;
        LOOP (* inv: ~(ch IN [' ', 9X, 0X]) *)
          INC(len); INC(i); ch := cmdline[i];
          IF (ch = ' ' ) OR (ch = 9X) OR (ch = 0X) THEN EXIT; END;
        END;
      END;
      NewParm(beg, len);
    END;
    RETURN beg + len;
  END ParseNextParm;

  (* pre: there must be no trailing whitespace characters at the end of the command line *)
  PROCEDURE Parse;
    VAR i, NextOffset : INTEGER;
  BEGIN i := 0;
    WHILE (i < LEN(cmdline)) & (cmdline[i] # 0X) DO
      NextOffset := ParseNextParm(i);
      i := NextOffset;
      INC(ParameterCount);
    END;
  END Parse;

  PROCEDURE Init;
    VAR root : ParmListRoot;
  BEGIN ParameterCount := 0; NEW(root); InitParm(root); root.last := NIL; parmlist := root; (* dummy list head *)
    Kernel.GetCommandLine(cmdline);
    Parse;
  END Init;

BEGIN Init;
END CommandLine.
