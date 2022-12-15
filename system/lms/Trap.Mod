MODULE Trap;
IMPORT
  SYSTEM,
  Kernel,
  DebugIO,
  MI:=ModuleInspector,
  Console;

  CONST (* Hardware codes *)
    HaltInvalidOpCode  = Kernel.HaltInvalidOpCode;
    HaltBreak          = Kernel.HaltBreak;
    HaltAlignment      = Kernel.HaltAlignment;
    HaltReadAccess     = Kernel.HaltReadAccess;
    HaltWriteAccess    = Kernel.HaltWriteAccess;
    HaltDivideByZero   = Kernel.HaltDivideByZero;
    HaltReserved0      = Kernel.HaltReserved0;
    HaltReserved1      = Kernel.HaltReserved1;

  CONST (* Software codes *)
    HaltAssert        = Kernel.HaltAssert;
    HaltRange         = Kernel.HaltRange;
    HaltArray         = Kernel.HaltArray;
    HaltIGuard        = Kernel.HaltIGuard;
    HaltEGuard        = Kernel.HaltEGuard;
    HaltCase          = Kernel.HaltCase;
    HaltFunc          = Kernel.HaltFunc;
    HaltWith          = Kernel.HaltWith;
    HaltGuardCheck    = Kernel.HaltGuardCheck;
    HaltPointerCheck  = Kernel.HaltPointerCheck;
    HaltFileIO        = Kernel.HaltFileIO;
    
  TYPE
    IOInterface = POINTER TO IOInterfaceDesc;
    IOInterfaceDesc = RECORD
      Ch    : PROCEDURE (ch : CHAR);
      Str   : PROCEDURE (str : ARRAY OF CHAR);
      Int   : PROCEDURE (x, n : LONGINT);
      Hex   : PROCEDURE (x : LONGINT);
      Ln    : PROCEDURE;
      Set   : PROCEDURE (s : SET);
      Bool  : PROCEDURE (b : BOOLEAN);
      Real  : PROCEDURE (r : REAL; n : INTEGER);
      LReal : PROCEDURE (r : LONGREAL; n : INTEGER);
      Open  : PROCEDURE;
      Close : PROCEDURE;
    END;

  VAR
    trapped : BOOLEAN;
    console : IOInterface;
    debugio : IOInterface;
    io      : IOInterface;


  PROCEDURE Locals(VAR handle : MI.ModuleDesc;
                   base       : LONGINT);
    VAR
      adr    : LONGINT;
      locals : MI.LocalDesc;
  BEGIN
    WHILE MI.NextLocal(handle, locals, base) DO
      io.Str('   ');
      io.Str(locals.name);
      io.Str('[');
      io.Int(locals.offset, 1);
      io.Str(']');
      io.Str(' = ');
      
      CASE ORD(locals.typeform) OF
      | MI.tfbool:
        io.Bool(locals.bval);

      | MI.tfbyte, MI.tfchar:
        IF (' ' <= locals.ch) & (locals.ch <= '~') THEN
          io.Ch(locals.ch);
        ELSE
          io.Hex(ORD(locals.ch));
          io.Ch('X');
        END;

      | MI.tfsint:
        io.Int(locals.sval, 3);

      | MI.tfint:
        io.Int(locals.ival, 3);

      | MI.tflint:
        io.Int(locals.lval, 3);

      | MI.tfreal:
        io.Real(locals.rval, 14);

      | MI.tflreal:
        io.LReal(locals.lrval, 21);

      | MI.tfset:
        io.Set(locals.set);

      | MI.tfpointer:
        io.Hex(locals.pointer); io.Ch('H');

      | MI.tfarray, MI.tfdynarr:
        io.Ch(22X);
        io.Str(locals.string);
        io.Ch(22X);

      ELSE
        io.Str('Invalid form found: ');
        io.Int(ORD(handle.ch), 1);
      END;
      io.Ln;
    END;
  END Locals;

  PROCEDURE Show(hardware      : BOOLEAN;
                 trap, ip, sfp : LONGINT;
                 cr2           : LONGINT);
    VAR
      modDesc : MI.ModuleDesc;
      stkDesc : MI.StackDesc;
      procLen, dummy, modOffs : LONGINT;
      name : MI.Name;
  BEGIN
    (* If GC is active, the DebugIO module cannot be used
     * because it allocates heap structures.  Instead, write
     * directly to the console.
     *)
    IF Kernel.GCActive THEN io := console;
    ELSE io := debugio;
    END;

    Console.Ln;
    Console.Str('abnormal program termination');
    Console.Ln;
    io.Open;

    io.Str('TRAP code='); io.Int(trap, 1); io.Str(' (');
    CASE trap OF
    |  HaltReadAccess: io.Str('Read outside of memory bounds');
    |  HaltWriteAccess: io.Str('Write outside of memory bounds');
    |  HaltInvalidOpCode: io.Str('invalid opcode');
    |  HaltDivideByZero: io.Str('divide by zero');
    |  HaltReserved0: io.Str('reserved0');
    |  HaltReserved1: io.Str('reserved1');
    |  HaltAssert: io.Str('assertion failure');
    |  HaltRange: io.Str('invalid integer range');
    |  HaltArray: io.Str('array index');
    |  HaltIGuard: io.Str('implicit type guard');
    |  HaltEGuard: io.Str('explicit type guard');
    |  HaltCase: io.Str('invalid case in CASE');
    |  HaltFunc: io.Str('function without return');
    |  HaltWith: io.Str('invalid case in WITH');
    |  HaltGuardCheck: io.Str('NIL pointer used in type guard');
    |  HaltPointerCheck: io.Str('NIL pointer dereferenced');
    |  HaltFileIO: io.Str('Files.ReadBytes/Files.WriteBytes: LEN(a) < n');
    ELSE io.Str('user defined');
    END;

    io.Ch(')'); io.Ln; io.Str('     pc='); io.Hex(ip);
    MI.GetModule(ip, modDesc);
    IF modDesc.module # NIL THEN
      io.Str(' (');
      io.Str(modDesc.module.name^);
      io.Str(', offset=');
      io.Hex(ip - SYSTEM.ADR(modDesc.module.code^));
      io.Ch(')');
    END;
    io.Str(' sfp='); io.Hex(sfp);
    IF hardware THEN
      io.Str(' cr2={C=');
      io.Int(cr2 MOD 2, 1);
      io.Str(', I=');
      io.Int((cr2 DIV 2) MOD 2, 1);
      io.Str(', T=');
      io.Int((cr2 DIV 4) MOD 8, 1);
      io.Str('}');
    END;
    io.Ln;

    (* If a hardware fault has occurred, do not try to produce a stack dump.
     * This is because a hardware fault caused by stack corruption will
     * lead to more faults as functions are called, or the current stack
     * frame pointer is used to access memory.  Instead, return so an
     * orderly exit can be performed.
     *)
    IF ~(trap IN { HaltReadAccess, HaltWriteAccess }) THEN
      MI.OpenStack(sfp, stkDesc); (* Get info of trapped function. *)
      LOOP
        IF stkDesc.EOS OR (stkDesc.module = NIL) THEN
          EXIT;
        END;

        io.Str(stkDesc.module.name^);
        IF MI.FindProcedure(stkDesc, modOffs, procLen, name) THEN
          io.Ch('.');
          io.Str(name);
          io.Str(' [');
          io.Hex(modOffs);
          io.Str('H..');
          io.Hex(modOffs + procLen);
          io.Str('H)');
          io.Ln;
          Locals(stkDesc, stkDesc.sfp);
        END;
        MI.NextStackFrame(stkDesc);
      END;
    END;
  END Show;


  PROCEDURE ShowSysTrap(trap, ip, sfp : LONGINT);
  BEGIN
    IF ~trapped THEN
      trapped := TRUE;
      Show(FALSE, trap, ip, sfp, 0);
    END;
    io.Close;
    Kernel.Terminate(trap);
  END ShowSysTrap;

  PROCEDURE ShowHwdTrap(ip, sfp, cr2 : LONGINT);
  BEGIN
    IF ~trapped THEN
      trapped := TRUE;
      Show(TRUE, (cr2 DIV 4) MOD 8, ip, sfp, cr2);
    END;
    io.Close;
    Kernel.Terminate(127);
  END ShowHwdTrap;

BEGIN
  NEW(console);
  console.Ch    := Console.Ch;
  console.Str   := Console.Str;
  console.Int   := Console.Int;
  console.Hex   := Console.Hex;
  console.Ln    := Console.Ln;
  console.Set   := Console.Set;
  console.Bool  := Console.Bool;
  console.Real  := Console.Real;
  console.LReal := Console.LReal;
  console.Open  := Console.Open;
  console.Close := Console.Close;

  NEW(debugio);
  debugio.Ch    := DebugIO.Ch;
  debugio.Str   := DebugIO.Str;
  debugio.Int   := DebugIO.Int;
  debugio.Hex   := DebugIO.Hex;
  debugio.Ln    := DebugIO.Ln;
  debugio.Set   := DebugIO.Set;
  debugio.Bool  := DebugIO.Bool;
  debugio.Real  := DebugIO.Real;
  debugio.LReal := DebugIO.LReal;
  debugio.Open  := DebugIO.Open;
  debugio.Close := DebugIO.Close;
  trapped := FALSE;
  Kernel.InstallSysTrap(ShowSysTrap);
  Kernel.InstallHwdTrap(ShowHwdTrap);
END Trap.
