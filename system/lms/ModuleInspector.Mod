(* Originally written by ETH Zurich.
 * Portions Copyright (c) 2021 Logic Magicians Software
 *
 *  This module facilitates inspecting modules and stack frames
 *  that are active.  It is useful for producing stack traces
 *  when a program fails, and for finding pointers on the stack
 *  for garbage collection.
 *
 *  It interfaces with the 'refs' information produced by the
 *  Oberon compiler.
 *)
MODULE ModuleInspector;
IMPORT SYSTEM, Kernel;

CONST
  MaxNameLen* = 24;             (* Must match LMST.
                                 * 23 characters + 0X.
                                 *)

CONST (* Must match LMST. *)
  tfundef* = 0;
  tfbool* = 1;
  tfbyte* = 2;
  tfchar* = 3;
  tfsint* = 4;
  tfint* = 5;
  tflint* = 6;
  tfreal* = 7;
  tflreal* = 8;
  tfset* = 9;
  tfstring* = 10;
  tfnil* = 11;
  tfvoid* = 12;
  tfpointer* = 13;
  tfprocedure* = 14;
  tfarray* = 15;
  tfdynarr* = 16;
  tfrecord* = 17;
  nofTypes* = 18;

CONST (* Must match LMST. *)
  skanon* = 0;
  skvar* = 1;
  skpar* = 2;
  skvarpar* = 3;
  skconst* = 4;
  skstdproc* = 5;
  skfwdproc* = 6;
  sklproc* = 7;
  skxproc* = 8;
  skcproc* = 9;
  skiproc* = 10;
  sktproc* = 11;
  skfield* = 12;
  sktype* = 13;
  skmodule* = 14;
  skscope* = 15;
  skdarrdesc* = 16;
  skarrdesc* = 17;
  skrecdesc* = 18;
  sknofSymbols* = 19;

TYPE
  Name* = ARRAY MaxNameLen OF CHAR;
  ModuleDesc* = RECORD
    module-   : Kernel.Module;
    refs      : Kernel.ReferenceBlock;
    refsLen   : LONGINT;
    refIndex  : LONGINT;
    ch*       : CHAR;
    refEOF-   : BOOLEAN;
  END;

TYPE
  (*  A typical stack will have this form.
   *  This is the stack on entry to Kernel.SysTrap for CTAssertTrap.Mod.
   *
   *  trace: Kernel.0830H: ENTER  R29, 7H [R29: 40fffd8H -> 40fffd0H, R30: 40fffd8H -> 40fffb4H]
   *  cpu: pc : Kernel.0834H  (4102184H)
   *  cpu: R0 : 00000000H  R1 : 00000008H  R2 : 040fffc0H  R3 : 00000018H
   *  cpu: R4 : 00100000H  R5 : 04100020H  R6 : 04128f30H  R7 : 00000000H
   *  cpu: R8 : 00000000H  R9 : 00000000H  R10: 00000000H  R11: 00000000H
   *  cpu: R12: 00000000H  R13: 00000000H  R14: 00000000H  R15: 00000000H
   *  cpu: R16: 00000000H  R17: 00000000H  R18: 00000001H  R19: 04109a50H
   *  cpu: R20: 00000001H  R21: 74736554H  R22: 0412d6c0H  R23: 00000004H
   *  cpu: R24: 00000004H  R25: 00000000H  R26: 00000000H  R27: 040fffc4H
   *  cpu: R28: 040fffc4H  R29: 040fffd0H  R30: 040fffb4H  R31: 0412edd0H
   *  cpu:
   *  cpu: Stack [4000010H..4100010H) [17H words]
   *  cpu:   40fffb4H [SP+000H] :       <uninitialized local var>
   *  cpu:   40fffb8H [SP+004H] :       <uninitialized local var>
   *  cpu:   40fffbcH [SP+008H] :       <uninitialized local var>
   *  cpu:   40fffc0H [SP+00cH] :       <uninitialized local var>
   *  cpu:   40fffc4H [SP+010H] :       <uninitialized local var>
   *  cpu:   40fffc8H [SP+014H] :       <uninitialized local var>
   *  cpu:   40fffccH [SP+018H] :       <uninitialized local var>
   *  cpu:   40fffd0H [SP+01cH] : (SFP) 40fffd8H
   *  cpu:   40fffd4H [SP+020H] :       CTAssertTrap.0030H
   *  cpu:   40fffd8H [SP+024H] : (SFP) 40ffff4H
   *  cpu:   40fffdcH [SP+028H] :       Modules.02b0H
   *  cpu:   40fffe0H [SP+02cH] :       412d6c0H
   *  cpu:   40fffe4H [SP+030H] :       412d690H
   *  cpu:   40fffe8H [SP+034H] :       CTAssertTrap.000cH
   *  cpu:   40fffecH [SP+038H] :       412ec70H
   *  cpu:   40ffff0H [SP+03cH] :       1999999H
   *  cpu:   40ffff4H [SP+040H] : (SFP) 40ffffcH
   *  cpu:   40ffff8H [SP+044H] :       Modules.0054H
   *  cpu:   40ffffcH [SP+048H] : (SFP) 4100008H
   *  cpu:   4100000H [SP+04cH] :       Kernel.0284H
   *  cpu:   4100004H [SP+050H] :       <uninitialized local var>
   *  cpu:   4100008H [SP+054H] : (SFP) 4100010H
   *  cpu:   410000cH [SP+058H] :       deadbeefH
   *
   *  SFP is the value in R29.  The value on the stack at (SFP) is
   *  the next stack frame.  Immediately above the (SFP) will be the
   *  return address of the open function on the stack.  When the SFP
   *  value is above the stack origin, the stack traversal is complete.
   *)
  StackDesc* = RECORD (ModuleDesc)
    sfp- : Kernel.ADDRESS;               (* Stack Frame Pointer *)
    ip-  : Kernel.ADDRESS;               (* Return address on stack. *)
    EOS- : BOOLEAN;                      (* Termination: End Of Stack. *)
  END;

TYPE
  LocalDesc* = RECORD
    typeform- : CHAR;           (* Compiler symbol table 'type form'. *)
    offset-   : LONGINT;        (* Stack frame pointer offset. *)

    (* Values read from stack *)
    bval-     : BOOLEAN;
    sval-     : SHORTINT;
    ch-       : CHAR;
    ival-     : INTEGER;
    lval-     : LONGINT;
    rval-     : REAL;
    lrval-    : LONGREAL;
    set-      : SET;
    pointer-  : Kernel.ADDRESS;
    name-     : Name;             (* Local variable name. *)
    string-   : ARRAY 32 OF CHAR; (* Must match SKLCGL.GenRefs() *)
  END;

TYPE
  GarbageCollectDesc = RECORD
    base  : Kernel.ADDRESS;
    sfp   : Kernel.ADDRESS;     (* Stack frame pointer for function. *)
    stack : StackDesc;
  END;

VAR
  gcDesc : GarbageCollectDesc;


PROCEDURE NextCh*(VAR desc : ModuleDesc);
BEGIN
  desc.refEOF := desc.refIndex >= desc.refsLen;
  IF ~desc.refEOF THEN
    desc.ch := desc.refs[desc.refIndex];
    INC(desc.refIndex);
  ELSE
    desc.ch := 0X;
  END;
END NextCh;


PROCEDURE ReadNum*(VAR handle : ModuleDesc;
                   VAR x      : LONGINT);
  VAR
    n  : INTEGER;
    y  : LONGINT;
BEGIN
  n := 0;
  y := 0;
  NextCh(handle);
  WHILE handle.ch >= 80X DO
    INC(y, SYSTEM.LSH(LONG(ORD(handle.ch)) - 128, n));
    INC(n, 7);
    NextCh(handle);
  END;
  x := ASH(SYSTEM.LSH(LONG(ORD(handle.ch)), 25), n - 25) + y;
END ReadNum;


PROCEDURE ReadName*(VAR handle : ModuleDesc;
                    VAR name   : Name);
  VAR
    len : LONGINT;
    i   : LONGINT;
BEGIN
  ReadNum(handle, len);
  ASSERT(len < MaxNameLen);   (* '<'; need space for 0X. *)
  i := 0;
  WHILE i < len DO
    NextCh(handle);
    name[i] := handle.ch;
    INC(i);
  END;
  name[i] := 0X;
END ReadName;


PROCEDURE GetModule*(ip : Kernel.ADDRESS; VAR desc : ModuleDesc);
  VAR
    mod : Kernel.Module;
    adr, len : LONGINT;
BEGIN
  mod := SYSTEM.VAL(Kernel.Module, Kernel.mlist);
  LOOP
    IF mod = NIL THEN
      EXIT;
    END;
    IF mod.code # NIL THEN
      adr := SYSTEM.ADR(mod.code[0]);
      len := LEN(mod.code^);
      IF (adr <= ip) & (ip < adr + len) THEN
        EXIT;
      END;
    END;
    mod := mod.next;
  END;
  desc.module := mod;

  IF (mod # NIL) & (mod.refs # NIL) THEN
    desc.refs     := mod.refs;
    desc.refsLen  := LEN(mod.refs^);
    desc.ch       := 0X;
    desc.refIndex := 0;
    desc.refEOF   := FALSE;
  END
END GetModule;


PROCEDURE ReadFrame(sfp : LONGINT; VAR desc : StackDesc);
BEGIN
  SYSTEM.GET(sfp, desc.sfp);
  SYSTEM.MEMR(sfp, SIZE(Kernel.ADDRESS), desc.ip);
END ReadFrame;

PROCEDURE OpenStack*(sfp : LONGINT; VAR desc : StackDesc);
BEGIN
  desc.EOS := FALSE;
  ReadFrame(sfp, desc);
  GetModule(desc.ip, desc);
END OpenStack;


PROCEDURE NextStackFrame*(VAR desc : StackDesc);
  VAR
    sfp : Kernel.ADDRESS;
BEGIN
  ReadFrame(desc.sfp, desc);
  desc.EOS := desc.sfp >= Kernel.stack.end;
  IF ~desc.EOS THEN
    GetModule(desc.ip, desc);
  END;
END NextStackFrame;


PROCEDURE FindProcedure*(VAR desc     : StackDesc;
                         VAR procAddr : Kernel.ADDRESS; (* Module-relative address *)
                         VAR procLen  : LONGINT;
                         VAR name     : Name) : BOOLEAN;
  VAR
    lname   : Name;
    dummy   : LONGINT;
    addr    : Kernel.ADDRESS;
    len     : LONGINT;
BEGIN
  LOOP
    IF desc.refEOF THEN
      RETURN FALSE;
    END;
    NextCh(desc);

    IF desc.ch = 97X THEN (* start proc *)
      ReadNum(desc, addr);
      ReadNum(desc, len);
      ReadName(desc, name);
      procAddr := addr;
      procLen  := len;
      INC(addr, SYSTEM.ADR(desc.module.code[0]));
      IF (addr <= desc.ip) & (desc.ip < addr + len) THEN
        RETURN TRUE;
      END;
    ELSIF desc.ch < 97X THEN (* skip object *)
      NextCh(desc);
      ReadNum(desc, dummy);
      ReadName(desc, lname);
    END;
  END;
  RETURN FALSE;
END FindProcedure;


PROCEDURE NextLocal*(VAR desc  : ModuleDesc;
                     VAR local : LocalDesc;
                         base  : LONGINT) : BOOLEAN;
  VAR
    adr      : LONGINT;
    i        : INTEGER;
    ch       : CHAR;
    symkind  : CHAR;
BEGIN
  NextCh(desc); (* Get 'symkind' *)
  symkind := desc.ch;

  IF ~desc.refEOF & (desc.ch < 97X) THEN
    NextCh(desc); (* Get 'typeform' *)
    local.typeform := desc.ch;
    ReadNum(desc, adr);
    local.offset := adr;        (* SFP offset. *)
    ReadName(desc, local.name);

    INC(adr, base);

    IF ORD(symkind) = skvarpar THEN
      SYSTEM.GET(adr, adr); (* indirect *)
    END;

    CASE ORD(local.typeform) OF
    | tfbool:
      SYSTEM.GET(adr, local.bval);

    | tfbyte, tfchar:
      SYSTEM.GET(adr, local.ch);

    | tfsint:
      SYSTEM.GET(adr, local.sval);

    | tfint:
      SYSTEM.GET(adr, local.ival);

    | tflint:
      SYSTEM.GET(adr, local.lval);

    | tfreal:
      SYSTEM.GET(adr, local.rval);

    | tflreal:
      SYSTEM.GET(adr, local.lrval);

    | tfset:
      SYSTEM.GET(adr, local.set);

    | tfpointer:
      SYSTEM.GET(adr, local.pointer);

    | tfarray, tfdynarr:
      (* Only character arrays less than 32 characters. See SKLCGL.GenRefs() *)
      IF ORD(symkind) = skpar THEN
        SYSTEM.GET(adr, adr); (* indirect *)
      END;

      i := 0;
      LOOP
        SYSTEM.GET(adr, ch);
        IF (ch < " ") OR (ch >= 90X) OR (i = LEN(local.string) - 1) THEN
          local.string[i] := 0X;
          EXIT;
        END ;
        local.string[i] := ch;
        INC(i);
        INC(adr);
      END;
    ELSE
      RETURN FALSE;             (* Invalid 'typeform'. *)
    END;
    RETURN TRUE;
  ELSE
    RETURN FALSE;
  END;
END NextLocal;


PROCEDURE GCFindFunction(ip, sfp : Kernel.ADDRESS) : BOOLEAN;
  VAR
    addr  : LONGINT;
    len   : LONGINT;
    name  : Name;
BEGIN
  GetModule(ip, gcDesc.stack);

  IF gcDesc.stack.module # NIL THEN
    (* Found a module.  Next, find the function. *)
    OpenStack(sfp, gcDesc.stack);
    gcDesc.sfp := sfp;

    (* The Oberon compiler creates module's initialization block as a
     * standalone function with the same name as the module.  The global
     * pointers are initialized in this function, and the compiler cheats
     * and treats their addresses as stack variables so that the generated
     * code can easily initialize them to NIL with a register holding the
     * base of the in-memory data section (this can be seen by disassembling
     * a module with global pointers).
     *
     * Therefore, module initialization functions must be skipped.
     *)
    IF FindProcedure(gcDesc.stack, addr, len, name) &
       (name # gcDesc.stack.module.name^) THEN
      RETURN TRUE;
    END;
  END;
  RETURN FALSE;
END GCFindFunction;

PROCEDURE GCNextPointer(VAR addr : Kernel.ADDRESS) : BOOLEAN;
  VAR
    local : LocalDesc;
BEGIN
  WHILE NextLocal(gcDesc.stack, local, gcDesc.stack.sfp) DO
    IF ORD(local.typeform) = tfpointer THEN
      Kernel.VMSVCTracing(FALSE);
      addr := local.pointer;
      Kernel.VMSVCTracing(FALSE);
      RETURN TRUE;
    END;
  END;
  RETURN FALSE;
END GCNextPointer;


PROCEDURE ConfigureKernel;
BEGIN
  Kernel.SetGCStackInfo(GCFindFunction, GCNextPointer);
END ConfigureKernel;


BEGIN
  ConfigureKernel;
END ModuleInspector.
