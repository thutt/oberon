MODULE Trap;
  IMPORT SYSTEM, Kernel, IO:=DebugIO, Console;
  (* after bootstrapping is complete, Trap should be loaded after Modules 97.08.11 *)

  CONST
    HaltDivide = Kernel.HaltDivide;
    HaltDebug = Kernel.HaltDebug;
    HaltInvalidOpCode = Kernel.HaltInvalidOpCode;
    HaltIntegerOverflow = Kernel.HaltIntegerOverflow;
    HaltUserBreak = Kernel.HaltUserBreak;
    HaltStackOverflow = Kernel.HaltStackOverflow;
    HaltAV = Kernel.HaltAV;
    HaltFPU = Kernel.HaltFPU;
    HaltAssert = Kernel.HaltAssert;
    HaltRange = Kernel.HaltRange;
    HaltArray = Kernel.HaltArray;
    HaltIGuard = Kernel.HaltIGuard;
    HaltEGuard = Kernel.HaltEGuard;
    HaltCase = Kernel.HaltCase;
    HaltFunc = Kernel.HaltFunc;
    HaltWith = Kernel.HaltWith;
    HaltGuardCheck = Kernel.HaltGuardCheck;
    HaltPointerCheck = Kernel.HaltPointerCheck;
    HaltFileIO = Kernel.HaltFileIO;
    
    assert = 0; range = 1; array = 2; iguard = 3; eguard = 4; case = 5; func = 6; with = 7; user = 8;
    nofStrings = 9;

  CONST (* must match LMST *)
    tfundef = 0; tfbool = 1; tfbyte = 2; tfchar = 3; tfsint = 4; tfint = 5; tflint = 6;
    tfreal = 7; tflreal = 8; tfset = 9; tfstring = 10; tfnil = 11; tfvoid = 12; tfpointer = 13;
    tfprocedure = 14; tfarray = 15; tfdynarr = 16; tfrecord = 17;
    nofTypes = 18;

  CONST (* must match LMST *)
    skanon = 0; skvar = 1; skpar = 2; skvarpar = 3; skconst = 4; skstdproc = 5; skfwdproc = 6; sklproc = 7;
    skxproc = 8; skcproc = 9; skiproc = 10; sktproc = 11; skfield = 12; sktype = 13; skmodule = 14;
    skscope = 15; skdarrdesc = 16; skarrdesc = 17; skrecdesc = 18;
    sknofSymbols = 19;

  VAR
    trapped : BOOLEAN;

  PROCEDURE - INT3 0CCH;

  PROCEDURE GetTrappedModule(eip : LONGINT) : Kernel.Module;
    VAR mod : Kernel.Module; adr, len : LONGINT;
  BEGIN
    mod := SYSTEM.VAL(Kernel.Module, Kernel.mlist);
    LOOP
      IF mod = NIL THEN EXIT; END;
      IF mod.code # NIL THEN adr := SYSTEM.ADR(mod.code[0]); len := LEN(mod.code^);
        IF (adr <= eip) & (eip < adr + len) THEN EXIT; END;
      END;
      mod := mod.next;
    END;
    RETURN mod;
  END GetTrappedModule;

  PROCEDURE NextCh(VAR (* R/O *) refs : ARRAY OF CHAR; VAR refIndex : LONGINT; VAR ch : CHAR);
  BEGIN IF refIndex < LEN(refs) THEN ch := refs[refIndex]; INC(refIndex); ELSE ch := 0X; END;
  END NextCh;

  PROCEDURE ReadNum(VAR (* R/O *) refs : ARRAY OF CHAR; VAR refIndex : LONGINT; VAR x: LONGINT);
    VAR ch : CHAR; n: INTEGER; y: LONGINT;
  BEGIN n := 0; y := 0;
    NextCh(refs, refIndex, ch);
    WHILE ch >= 80X DO
      INC(y, SYSTEM.LSH(LONG(ORD(ch)) - 128, n)); INC(n, 7); NextCh(refs, refIndex, ch);
    END;
    x := ASH(SYSTEM.LSH(LONG(ORD(ch)), 25), n-25) + y;
  END ReadNum;

  PROCEDURE ReadName(VAR (* R/O *) refs : ARRAY OF CHAR; VAR refIndex : LONGINT; p : BOOLEAN);
    VAR len : LONGINT; ch : CHAR;
  BEGIN ReadNum(refs, refIndex, len);
    WHILE len > 0 DO DEC(len); NextCh(refs, refIndex, ch);
      IF p THEN IO.Ch(ch); END;
    END;
  END ReadName;
      
  PROCEDURE Locals(VAR (* R/O *) refs : ARRAY OF CHAR; VAR refIndex : LONGINT; base: LONGINT);
    VAR
      adr, val: LONGINT;
      sval : SHORTINT;
      typeform, ch, symkind: CHAR;
      ival, i: INTEGER;
      rval: REAL;
      lrval: LONGREAL;
      set : SET;
  BEGIN
    IO.Ln; NextCh(refs, refIndex, symkind);
    WHILE (refIndex < LEN(refs)) & (symkind < 97X) DO
      NextCh(refs, refIndex, typeform); ReadNum(refs, refIndex, adr);
      
      IO.Str('   '); ReadName(refs, refIndex, TRUE);
      IO.Str('['); IO.Int(adr, 1); IO.Str(']');
      IO.Str(' = ');
      INC(adr, base);
      
      IF ORD(symkind) = skvarpar THEN SYSTEM.GET(adr, adr); (* indirect *) END;
      CASE ORD(typeform) OF
      |  tfbool:
        SYSTEM.GET(adr, sval);
        IF sval = 0 THEN IO.Str('FALSE');
        ELSE IO.Str('TRUE');
        END;
      |  tfbyte, tfchar:
        SYSTEM.GET(adr, ch);
        IF (' ' <= ch) & (ch <= '~') THEN IO.Ch(ch);
        ELSE IO.Hex(ORD(ch)); IO.Ch('X');
        END;
      |  tfsint: SYSTEM.GET(adr, sval); IO.Int(sval, 3);
      |  tfint:  SYSTEM.GET(adr, ival); IO.Int(ival, 3);
      |  tflint: SYSTEM.GET(adr, val); IO.Int(val, 3);
      |  tfreal: SYSTEM.GET(adr, rval); IO.Real(rval, 14);
      |  tflreal: SYSTEM.GET(adr, lrval); IO.LReal(lrval, 21);
      |  tfset: SYSTEM.GET(adr, set); IO.Set(set);
      |  tfpointer: SYSTEM.GET(adr, val); IO.Hex(val); IO.Ch('H');
      |  tfarray, tfdynarr:
        IF ORD(symkind) = skpar THEN SYSTEM.GET(adr, adr); (* indirect *) END;
        i := 0; IO.Ch(22X);
        LOOP SYSTEM.GET(adr, ch);
          IF (ch < " ") OR (ch >= 90X) OR (i = 32) THEN EXIT; END ;
          IO.Ch(ch); INC(i); INC(adr);
        END;
        IO.Ch(22X);
      ELSE IO.Str('Invalid form found: '); IO.Int(ORD(typeform), 1);
      END;
      IO.Ln; NextCh(refs, refIndex, symkind);
    END;
  END Locals;

  PROCEDURE ShowTrap(trap, eip, ebp : LONGINT);
    VAR mod, curmod : Kernel.Module; ch : CHAR; refIndex, len, procAddr, procLen, dummy, modOffs : LONGINT;

  BEGIN
    IF ~trapped THEN
      Console.Ln; Console.Str('abnormal program termination');
      IO.Str('TRAP code='); IO.Int(trap, 1); IO.Str(' (');
      CASE trap OF
      |  HaltDivide: IO.Str('divide by zero');
      |  HaltDebug: IO.Str('debugger');
      |  HaltInvalidOpCode: IO.Str('invalid opcode');
      |  HaltIntegerOverflow: IO.Str('integer overflow');
      |  HaltUserBreak: IO.Str('user break');
      |  HaltStackOverflow: IO.Str('stack overflow');
      |  HaltAV: IO.Str('access violation');
      |  HaltFPU: IO.Str('FPU error');
      |  HaltAssert: IO.Str('assertion failure');
      |  HaltRange: IO.Str('invalid integer range');
      |  HaltArray: IO.Str('array index');
      |  HaltIGuard: IO.Str('implicit type guard');
      |  HaltEGuard: IO.Str('explicit type guard');
      |  HaltCase: IO.Str('invalid case in CASE');
      |  HaltFunc: IO.Str('function without return');
      |  HaltWith: IO.Str('invalid case in WITH');
      |  HaltGuardCheck: IO.Str('NIL pointer used in type guard');
      |  HaltPointerCheck: IO.Str('NIL pointer dereferenced');
      |  HaltFileIO: IO.Str('Files.ReadBytes/Files.WriteBytes: LEN(a) < n');
      ELSE IO.Str('user defined');
      END;
      Console.Ln;
      
      IO.Ch(')'); IO.Ln; IO.Str('     eip='); IO.Hex(eip);
      mod := GetTrappedModule(eip);
      IF mod # NIL THEN IO.Str(' (module offset='); IO.Hex(eip - SYSTEM.ADR(mod.code^)); IO.Ch(')'); END;
      IO.Str(' ebp='); IO.Hex(ebp); IO.Ln;
  
      LOOP
        mod := GetTrappedModule(eip);
        IF (mod = NIL) OR (mod.refs = NIL) THEN EXIT; END;
        IO.Str(mod.name^); refIndex := 0; len := LEN(mod.refs^);
        LOOP
          IF refIndex >= len THEN EXIT; END;
          NextCh(mod.refs^, refIndex, ch);

          IF ch = 97X THEN (* start proc *)
            ReadNum(mod.refs^, refIndex, procAddr); ReadNum(mod.refs^, refIndex, procLen);
            modOffs := procAddr; INC(procAddr, SYSTEM.ADR(mod.code[0]));
            IF (procAddr <= eip) & (eip < procAddr + procLen) THEN EXIT END;
            ReadName(mod.refs^, refIndex, FALSE);
          ELSIF ch < 97X THEN (* skip object *)
            NextCh(mod.refs^, refIndex, ch); ReadNum(mod.refs^, refIndex, dummy);
            ReadName(mod.refs^, refIndex, FALSE); modOffs := 0; procLen := 0;
          END;
        END;
        IF refIndex < len THEN IO.Ch('.'); ReadName(mod.refs^, refIndex, TRUE);
           IO.Str(' ['); IO.Hex(modOffs); IO.Str('H..'); IO.Hex(modOffs + procLen); IO.Str('H)');
           Locals(mod.refs^, refIndex, ebp);
        END;
        SYSTEM.MEMR(ebp, 4, eip); SYSTEM.GET(ebp, ebp);
        IF ebp >= Kernel.StackOrg THEN EXIT; END;
      END;
      Kernel.Terminate(trap);
    END;
  END ShowTrap;

BEGIN
  trapped := FALSE;
  Kernel.InstallTrap(ShowTrap);
END Trap.

