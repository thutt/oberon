(* SKLCGH
 *
 *   High-level code generation for SKL CPU.
 *
 *)
MODULE SKLCGH;
IMPORT
  SYSTEM,
  CGL:=SKLCGL,
  OPM:=SKLMD,
  ST:=SKLST,
  T:=SKLT,
  OPS:=SKLOS;

  CONST
    (* Types which, even when passed as non-VAR parm, are passed by
     address.  SKLTT uses this information to set the Item mode to
     Ivarpar for these.

     SKLTU needs to be adjusted accordingly for parameter address
     assignment when these change.  Assign() in this module needs to be
     adjusted also when this changes. *)
     PassedByAddress* = {ST.array, ST.record};

  CONST
    (* array element types which do not need garbage collection *)
    SimpleElemSet = {ST.bool, ST.byte, ST.char, ST.sint, ST.int, ST.lint,
                     ST.real, ST.lreal, ST.set, ST.procedure};

    MaxChar = 0FFH; (* Should be MAX(CHAR), but defect in this compiler make this give an error *)
    Kernel = "Kernel";
    MaxPointerInits = 15;

  CONST (* internally used CGL.Item modes *)
    Itos      = CGL.Imodes;   (* top of stack; pseduo-location for instruction selection *)

  TYPE
    PointerLoc = POINTER TO PointerLocDesc;
    PointerLocDesc = RECORD
      sym : ST.Symbol; (* symbol which owns the pointer *)
      offset : LONGINT; (* offset from the beginning of the symbol where the pointer exists *)
    END;

  TYPE (* Used for collecting pointers in a scope *)
    CollectPointersInfo = RECORD (ST.ProcessScopeInfo)
      nofPointers : INTEGER;
      tab : POINTER TO ARRAY OF LONGINT;
    END;

  VAR
    True, False, One : CGL.Item;

  PROCEDURE ^ Simplify(VAR x : CGL.Item; Rx : SET);
  PROCEDURE ^ Convert*(VAR x : CGL.Item; to, from: SHORTINT);
  PROCEDURE ^ Load(VAR x : CGL.Item);
    (* XXX How are LoadInto and LoadItem different? *)
  PROCEDURE ^ LoadInto*(VAR x : CGL.Item; regs : CGL.GRegSet);
  PROCEDURE ^ LoadItem(VAR x : CGL.Item; Rx : SET); (* Rx <=> register set which x can use *)
  PROCEDURE ^ Mul*(VAR x, y : CGL.Item); (* arithmetic *, set intersection *)
  PROCEDURE ^ Add*(VAR x, y : CGL.Item); (* arithmetic +, set union *)
  PROCEDURE ^ Move(VAR dest, source: CGL.Item);

  PROCEDURE CompleteItem*(n : T.Node; VAR x : CGL.Item);
    VAR sym : ST.Symbol;
  BEGIN
    IF n.class = T.Ndsgn THEN
      sym := n(T.Design).sym;
      ASSERT(sym # NIL, 151);
      CASE n.subcl OF
      | T.Dtype: (* nop *)

      | T.Dvar, T.Dpar, T.Dvarpar, T.Dmethod:
        x.sym    := sym;
        x.adr    := 0;
        x.offset := 0;
        x.methno := -1;
        x.mnolev := x.sym.mnolev;

      | T.Dconst:
        x.sym    := sym;
        x.adr    := 0;
        x.offset := 0;
        x.methno := -1;
        x.mnolev := x.sym.mnolev;
        x.val := n(T.Expr).val^;

      | T.Ddarrdesc, T.Darrdesc, T.Drecdesc:
        x.sym    := sym;
        x.adr    := 0;
        x.offset := 0;
        x.methno := -1;
        x.mnolev := x.sym.mnolev;

      | T.Dproc:
        x.sym    := sym;
        x.adr    := 0;
        x.offset := 0;
        x.methno := -1;
        x.mnolev := x.sym.mnolev;
      ELSE (* nop *)
      END;
    ELSIF n.class = T.Nexpr THEN
      IF n.subcl = T.Econst THEN
        x.offset := 0;
        x.methno := -1;
        x.val := n(T.Expr).val^;
      END;
    END;
  END CompleteItem;

  PROCEDURE MakeConstItem*(VAR x : CGL.Item; n : LONGINT; type : ST.Type);
  BEGIN
    CGL.InitItem(x);
    x.mode := CGL.Iconst;
    x.type := type;
    CASE type.form OF
    |  ST.byte, ST.bool, ST.char, ST.sint, ST.int, ST.lint:
       x.val.i0 := n;

    |  ST.set:
       x.val.set := SYSTEM.VAL(SET, n);
    ELSE OPM.internal("H", 1200);
    END;
  END MakeConstItem;

  (* Shorten integer type.
     Does not work with FP types.
     Does not perform range checks. *)
  PROCEDURE Shorten(VAR x : CGL.Item; to : ST.Type);
  BEGIN
    IF x.type # to THEN
      IF x.mode = CGL.Iconst THEN
        x.type := to;
      ELSE
        (* Once loaded in a register, the type can be updated. *)
        Load(x);
        x.type := to;
      END;
    END;
  END Shorten;

  (* widen integer type; does not work with FP types *)
  PROCEDURE Widen(VAR x : CGL.Item; to : ST.Type);
  BEGIN
    IF x.type # to THEN
      IF x.mode # CGL.Iconst THEN
        ASSERT(x.type.size < to.size);
        Load(x);
      END;
      x.type := to;
    END;
  END Widen;

  PROCEDURE StoreMem(VAR x, y : CGL.Item);
    VAR
      opc : SHORTINT;
  BEGIN
    CASE y.type.form OF
    | ST.bool, ST.byte, ST.char, ST.sint:
      opc := CGL.opcSB;

    | ST.int:
      opc := CGL.opcSH;

    | ST.lint, ST.pointer, ST.procedure, ST.set, ST.nil:
      opc := CGL.opcSW;

    | ST.real:
      opc := CGL.opcSF;

    | ST.lreal:
      opc := CGL.opcSD;
    END;
    CGL.PutStoreMem(opc, x, y);
  END StoreMem;


  PROCEDURE TemporaryReg(VAR x : CGL.Item; type : ST.Type);
  BEGIN
    CGL.InitItem(x);
    IF type.form IN ST.RealSet THEN
      CGL.GetFReg(x, {0..MAX(SET)});
    ELSE
      ASSERT(type.form IN ST.BasicSet, 200);
      CGL.GetReg(x, CGL.RegWord);
    END;
    x.type := type;
  END TemporaryReg;


  PROCEDURE MoveCoc(VAR x, y : CGL.Item); (* x = Coc(y) *)
    VAR z : CGL.Item; lab : CGL.Label;

    PROCEDURE SetBoolFromCC(VAR x, y : CGL.Item);
    BEGIN
      ASSERT((y.mode = CGL.Icoc) & (x.mode = CGL.Ireg));
      CGL.PutConditionalSet(y.cc, x, y);
    END SetBoolFromCC;

  BEGIN
    ASSERT((y.mode = CGL.Icoc) & (y.cc IN CGL.ccSet), 200);
    ASSERT(x.type.size = 1, 201); (* A condition code is a BOOLEAN *)

    IF y.cc = CGL.ccAW THEN
      Move(x, True);
    ELSIF y.cc = CGL.ccNV THEN
      Move(x, False);
    ELSIF (y.jump.true = NIL) & (y.jump.false = NIL) THEN (* no jump link *)
      z := y;
      z.mode := CGL.Ireg;
      SetBoolFromCC(z, y);
      Move(x, z);
    ELSE (* Jump links present, so set x based on cc *)
      CGL.PutJump(CGL.Inverted(y.cc), y, y.jump.false);  (* J~cond false *)
      CGL.SetLabel(y.jump.true);
      Move(x, True); (* true: *)
      lab := NIL;
      CGL.PutJump(CGL.ccAW, y, lab); (* Item argument ignored for ccAW *)
      CGL.SetLabel(y.jump.false);
      Move(x, False); (* false: *)
      CGL.SetLabel(lab);
      (* True & False types can be changed by Move() to tos); reset *)
      MakeConstItem(False, OPM.FalseVal, ST.booltyp);
      MakeConstItem(True, OPM.TrueVal, ST.booltyp);
    END;
  END MoveCoc;


  PROCEDURE LoadZero(VAR z : CGL.Item);
  BEGIN (* Load the constant '0' into a register. *)
    MakeConstItem(z, 0, ST.linttyp);
    Load(z);
  END LoadZero;


  PROCEDURE LoadOne(VAR x : CGL.Item);
    VAR zero : CGL.Item;
  BEGIN (* Load the constant '1' into a register. *)
    LoadZero(zero);
    ASSERT(x.mode = CGL.Ireg);
    CGL.PutCompare(zero, zero, x); (* Set ZF (bit 0) in x. *)
  END LoadOne;


  PROCEDURE moveF(VAR dest : CGL.Item; VAR source : CGL.Item);
    VAR
      R0, dst, src, zero : CGL.Item;
      lo, hi : LONGINT;
      opc : SHORTINT;
  BEGIN
    CGL.InitItem(R0);
    CASE dest.mode OF
    | CGL.Ivar, CGL.Ipar, CGL.Ivarpar, CGL.Ivarx,
      CGL.Iind, CGL.Iindx, CGL.Iregi, CGL.Iregix: (* Move to memory *)

      CASE source.mode OF
      |  CGL.Ivar, CGL.Ipar, CGL.Ivarpar, CGL.Ivarx, CGL.Iind,
         CGL.Iindx, CGL.Iregi, CGL.Iregix:
         Load(source);
         StoreMem(dest, source);
         CGL.Release(source);

      |  CGL.Ireg:
         StoreMem(dest, source);

      |  CGL.Iconst:
         Load(source);
         StoreMem(dest, source);
      END;

    |  CGL.Ireg:
       CASE source.mode OF
       |  CGL.Ivar, CGL.Ipar, CGL.Ivarpar, CGL.Ivarx,
          CGL.Iind, CGL.Iindx, CGL.Iregi, CGL.Iregix:
          CGL.PutLoad(dest, source);

       |  CGL.Ireg:
          LoadZero(zero);
          CGL.PutGenReg(CGL.opcADD, zero, source, dest);
       END;

    |  Itos:
       ASSERT(source.mode IN {CGL.Ivar, CGL.Ipar, CGL.Ivarpar, CGL.Ivarx,
                              CGL.Iind, CGL.Iindx, CGL.Ireg, CGL.Iregi,
                              CGL.Iregix, CGL.Iconst});

       Load(source);
       IF source.type.form = ST.real THEN
         opc := CGL.opcPUSHF;
       ELSE
         ASSERT(source.type.form = ST.lreal);
         opc := CGL.opcPUSHD;
       END;

       CGL.PutStack(opc, source);
    END;
  END moveF;


  PROCEDURE SimplifyIndirect(VAR x : CGL.Item);
    VAR
      temp : CGL.Item;
      type : ST.Type;
  BEGIN
    IF x.mode IN { CGL.Ivarpar, CGL.Iind, CGL.Iindx } THEN
      (* On SKL, indirect access to memory must be simplified to a
       * register indirect addressing mode. *)
      type := x.type;
      TemporaryReg(temp, ST.linttyp);
      x.type    := ST.linttyp;
      x.mode    := CGL.Ivar;
      CGL.PutLoad(temp, x);
      temp.mode   := CGL.Iregi;
      temp.offset := x.offset;
      temp.type   := type;
      x := temp;
    END;
  END SimplifyIndirect;


  PROCEDURE moveI(VAR dest : CGL.Item; VAR source : CGL.Item); (* move non-float types *)
    VAR
      sm   : SHORTINT;
      zero : CGL.Item;
      temp : CGL.Item;

    PROCEDURE LoadSource(am : SET; VAR s : CGL.Item);
    BEGIN
      (* am <=> allowed modes that do not require loading *)
      IF ~(s.mode IN am) THEN
        Load(s);
        sm := s.mode;
      END;
    END LoadSource;

  BEGIN
    ASSERT(dest.type.size <= SIZE(LONGINT), 1000);
    sm := source.mode;
    CASE dest.mode OF
    |  CGL.Ivar, CGL.Ipar, CGL.Ivarx: (* Simple write to memory. *)
       Load(source);
       StoreMem(dest, source);

    |  CGL.Ivarpar, CGL.Iind, CGL.Iindx: (* Indirect, Indirect-indexed. *)
       LoadSource({CGL.Ireg, CGL.Iconst, CGL.Icoc, Itos}, source);
       ASSERT(sm IN {CGL.Ireg, CGL.Iconst, CGL.Icoc, Itos}, 204);

       temp := dest;
       temp.type := ST.linttyp;
       SimplifyIndirect(temp);
       temp.mode := CGL.Iregi;

       IF sm IN {CGL.Ireg, CGL.Iconst, CGL.Ilproc, CGL.Ixproc,
                 CGL.Iiproc, CGL.Itproc} THEN
         Load(source);
         StoreMem(temp, source);
       ELSE
         ASSERT(sm = CGL.Icoc, 1024);
         MoveCoc(dest, source);
       END;

    |  CGL.Ireg:
       ASSERT(sm IN {CGL.Iadr, CGL.Ivar, CGL.Ipar, CGL.Ivarpar, CGL.Iconst,
                     CGL.Ivarx, CGL.Iind, CGL.Iindx, CGL.Ireg,
                     CGL.Icoc, CGL.Iregi, CGL.Iregix}, 206);
       LoadSource({CGL.Iadr, CGL.Ivar, CGL.Ipar, CGL.Iconst, CGL.Ivarx, CGL.Iind,
                   CGL.Iindx, CGL.Ireg, CGL.Iregi, CGL.Iregix, CGL.Icoc,
                   Itos}, source);
       IF sm IN {CGL.Iadr, CGL.Ivar, CGL.Ipar, CGL.Iconst, CGL.Ivarx, CGL.Iind,
                 CGL.Iindx, CGL.Iregi, CGL.Iregix} THEN
         CGL.PutLoad(dest, source);
       ELSIF sm = CGL.Ireg THEN
         LoadZero(zero);
         CGL.PutGenReg(CGL.opcADD, zero, source, dest);
       ELSIF sm = CGL.Icoc THEN
         MoveCoc(dest, source);
       ELSIF sm = Itos THEN
         ASSERT(dest.type.size = 4, 207);
         CGL.PutStack(CGL.opcPOP, dest);
       END;

    |  CGL.Iregi, CGL.Iregix:
       LoadSource({CGL.Ireg, CGL.Iconst, CGL.Icoc, Itos}, source);
       ASSERT(sm IN {CGL.Ireg, CGL.Iconst, CGL.Icoc}, 208);
       IF sm IN {CGL.Ireg, CGL.Iconst} THEN
         Load(source);
         StoreMem(dest, source);
       ELSE
         ASSERT(sm = CGL.Icoc);
         MoveCoc(dest, source);
       END;

    |  Itos:
       Load(source);
       CGL.PutStack(CGL.opcPUSH, source);
    END;
  END moveI;

  (* Move
   *
   *   Move 'source' to 'dest'.
   *   There are no restrictions on the mode of either item.
   *   This means that the source must often be loaded in a register first.
   *
   *)

  PROCEDURE Move(VAR dest, source : CGL.Item);
  BEGIN
    IF dest.type.form IN ST.RealSet THEN
      moveF(dest, source);
    ELSE
      moveI(dest, source);
    END;
  END Move;


  PROCEDURE SetCC(VAR x : CGL.Item; cc : SHORTINT);
  BEGIN
    ASSERT((x.mode IN {CGL.Ireg, CGL.Icoc}) OR
           ((x.mode = CGL.Iconst) & (cc IN {CGL.ccAW, CGL.ccNV})), 200);
    ASSERT(cc IN CGL.ccSet, 201);
    x.mode       := CGL.Icoc;
    x.type       := ST.booltyp;
    x.cc         := cc;
    x.jump.true  := NIL;
    x.jump.false := NIL;
  END SetCC;


  PROCEDURE AdjustSP(n: LONGINT);
    VAR
      s   : CGL.Item;
      sp  : CGL.Item;
  BEGIN
    IF n > 0 THEN (* Make space on stack; stack grows downward. *)
      n := -n;
    END;
    MakeConstItem(s, n, ST.linttyp);
    sp.mode   := CGL.Ireg;
    sp.type   := ST.linttyp;
    sp.mnolev := 0;
    sp.reg    := CGL.SP;
    CGL.PutAddConstant(sp, s, sp); (* la (Rsp, n), Rsp *)
  END AdjustSP;


  (* TakeAddress: Load address of 'x' in 'rs'.
   * rs # {} => address should be loaded into a register from that set
   * force => force a load into a register even if a fixup could
   *           be generated later (i.e.: taking address of a global)
   * force => rs # {} *)
  PROCEDURE TakeAddress*(VAR x : CGL.Item; rs : SET; force : BOOLEAN);
    VAR
      y, z, sfp, fpoffs : CGL.Item;
      zero : CGL.Item;
      offset : LONGINT;
      global : BOOLEAN;
  BEGIN
    ASSERT((x.sym # NIL) & (x.sym.mnolev <= 0) OR
           (x.mode IN {CGL.Iregi, CGL.Iregix}) OR (rs # {}));
    y := x;
    global := (x.sym # NIL) & (x.sym.mnolev <= 0); (* global object; can have a fixup *)
    x.type := ST.linttyp; (* Type of y should not be changed unless necessary,
                           * else low-level access will be thrown off
                           * (i.e. indexing in CGL) *)

    CASE x.mode OF
    |  CGL.Ivar, CGL.Ilproc, CGL.Ixproc, CGL.Iiproc:
       IF global THEN
         x.mode := CGL.Iadr;
       ELSE
         CGL.GetReg(x, rs);
         CGL.PutLoadAddress(x, y);
       END;

    |  CGL.Ipar:
       IF y.type.form = ST.dynarr THEN (* passed by address; Ivarpar *)
         y.type := ST.linttyp;
         CGL.GetReg(x, rs);
         Load(y);
         LoadZero(zero);
         CGL.PutGenReg(CGL.opcADD, zero, y, x);
       ELSE
         CGL.GetReg(x, rs);
         CGL.PutLoadAddress(x, y);
       END;

    |  CGL.Ivarpar:
       y.mode := CGL.Ipar;
       y.type := ST.linttyp;
       TemporaryReg(x, x.type);
       Load(y);
       LoadZero(zero);
       CGL.PutGenReg(CGL.opcADD, y, zero, x); (* add Ry, Rzero, Rx *)

    |  CGL.Ivarx:
       TemporaryReg(x, x.type);
       CGL.PutLoadAddress(x, y);
       CGL.Release(y);

    |  CGL.Iind:
       CGL.GetReg(x, CGL.RegWord);
       y.mode := CGL.Ivar;
       offset := y.offset;
       y.type := ST.linttyp;
       x.type := ST.linttyp;
       CGL.PutLoad(x, y);
       IF offset # 0 THEN
         y := x;
         y.mode := CGL.Iregi;
         CGL.DoubleRef(y);
         y.offset := offset;
         CGL.PutLoadAddress(x, y);
         CGL.Release(y);
       END;
       x.mode := CGL.Ireg;

    |  CGL.Iregi:(* TODO: Iregi, Iregix _ARE_ addresses.
                  *       Was this loading done for a limitation of x86 registers?
                  *)
       IF (x.offset # 0) OR ~(x.reg IN rs) OR (rs * CGL.GRegFree # {}) THEN
         IF ~(x.reg IN rs) OR (rs * CGL.GRegFree # {}) THEN
           (* If current register not appropriate or cannot
            * accomodate, get new reg *)
           CGL.GetReg(x, rs);
         ELSE
           x.mode := CGL.Ireg;
           CGL.DoubleRef(x);
         END;
         CGL.PutLoadAddress(x, y);
         CGL.Release(y);
       ELSE
         x.mode := CGL.Ireg;
       END;
       x.offset := 0;

    |  CGL.Iregix:
       IF ~(x.reg IN rs) THEN
         CGL.GetReg(x, rs);
       ELSE
         x.mode := CGL.Ireg;
         CGL.DoubleRef(x);
       END;
       CGL.PutLoadAddress(x, y); (* la (Ry+offset), Rx *)
       CGL.Release(y);
       x.offset := 0;

    |  Itos:
       x.mode := CGL.Ireg;
       x.reg  := CGL.SP;
       CGL.DoubleRef(x);
    END;
    IF force OR ~global & (rs # {}) & ((x.mode = CGL.Ireg) & ~(x.reg IN rs)) THEN
      LoadItem(x, rs);
    END;
  END TakeAddress;

  PROCEDURE MoveMemMemBlock(VAR dest, source : CGL.Item; s : LONGINT);
    VAR
      len : CGL.Item;
  BEGIN
    ASSERT(dest.mode IN {CGL.Ivar, CGL.Ipar, CGL.Ivarpar, CGL.Ivarx,
                         CGL.Iind, CGL.Iindx, CGL.Iregi, CGL.Iregix}, 740);
    ASSERT(source.mode IN {CGL.Ivar, CGL.Ipar, CGL.Ivarpar, CGL.Ivarx,
                           CGL.Iind, CGL.Iindx, CGL.Iregi, CGL.Iregix}, 741);
    (*src.type := ST.linttyp; SKLCGL uses the actual source size
     *  to calculate the proper addressing mode *)
    MakeConstItem(len, s, ST.linttyp);
    TakeAddress(source, {1}, TRUE);
    TakeAddress(dest, {2}, TRUE);
    LoadInto(len, {3});

    (* R1 = destination address,
     * R2 = source address
     * R3 = number of bytes
     *
     * R1 & R2 must be non-overlapping.
     *)
    CGL.CallCompilerHelper("Kernel", "MoveBlock");
    (* No return value. *)

    CGL.Release(len);
    CGL.Release(dest);
    CGL.Release(source);
  END MoveMemMemBlock;

  (*
  pre: defined(x) & (toType # NIL
  post: x is loaded on the FPU stack and its type is 'toType'
  x can originally be a constant or a non-constant
  *)
  PROCEDURE loadF(VAR x : CGL.Item; toType : ST.Type);
    VAR
      f : SHORTINT;

    PROCEDURE integer(VAR x : CGL.Item; toType : ST.Type);
      VAR
        y, z : CGL.Item;
        zero : CGL.Item;
    BEGIN
      LoadZero(zero);
      y := x;
      CGL.GetFReg(x, {0..MAX(SET)});
      x.type := toType;

      IF y.mode = CGL.Iconst THEN
        IF CGL.IsConstZero(y) THEN
          CGL.PutGenReg(CGL.opcADD, zero, zero, x);
        ELSE
          Load(y);
          CGL.PutGenReg(CGL.opcADD, zero, y, x);
          CGL.Release(y);
        END;
      ELSE (* non-const *)
        Load(y);
        CGL.PutGenReg(CGL.opcADD, zero, y, x);
        CGL.Release(y);
      END;
    END integer;

    PROCEDURE real(VAR x : CGL.Item; toType : ST.Type);
      VAR
        reg    : CGL.Item;
        zero   : CGL.Item;
        lo, hi : LONGINT;
    BEGIN
      LoadZero(zero);
      IF x.mode = CGL.Iconst THEN
        IF x.val.real = 0.0 THEN
          CGL.GetFReg(x, {0..MAX(SET)});
          CGL.PutGenReg(CGL.opcADD, zero, zero, x);
        ELSE
          CGL.GetFReg(reg, {0..MAX(SET)});
          reg.type := toType;
          CGL.PutLoad(reg, x);
          CGL.Release(x);
          x := reg;
        END;
      ELSE
        CGL.GetFReg(reg, {CGL.MinRegister..CGL.MaxRegister});
        reg.type := toType;
        IF x.mode = CGL.Ireg THEN
          CGL.PutGenReg(CGL.opcADD, zero, x, reg);
        ELSE
          CGL.PutLoad(reg, x);
        END;
        x := reg;
      END;
      x.type := toType;
    END real;

  BEGIN

    ASSERT(x.type.form IN ST.IntSet + ST.RealSet, 181);
    f := x.type.form;
    IF f IN ST.IntSet THEN
      integer(x, toType);
    ELSIF f IN ST.RealSet THEN
      real(x, toType);
    END;
  END loadF;


  PROCEDURE loadI(VAR x : CGL.Item); (* Load into integer register *)
    VAR
      y : CGL.Item;
      rs : SET;
  BEGIN
    IF x.mode # CGL.Ireg THEN
      ASSERT(x.mode IN {CGL.Ivar..CGL.Iconst, CGL.Icoc,
                        CGL.Ivarx..CGL.Iindx,
                        CGL.Iregi..CGL.Iregix, CGL.Iadr}, 200);
      IF CGL.IsConstZero(x) THEN
        x.mode := CGL.Ireg;
        x.reg  := 0;            (* R0 is always 0, but not actually allocated. *)
      ELSIF CGL.IsConstOne(x) THEN
        TemporaryReg(x, x.type);
        LoadOne(x);
      ELSIF x.mode = CGL.Icoc THEN
        (* A condition code is a register (x.reg) and a condition code (x.cc).
         * The register contains a TRUE/FALSE value already, as a result of a
         * comparison.  The register can be used directly.
         *)
        CGL.DoubleRef(x);
        x.mode := CGL.Ireg;
      ELSIF x.mode = CGL.Iadr THEN
        y := x;
        TemporaryReg(y, x.type);
        CGL.PutLoadAddress(y, x);
        x := y;
      ELSE
        SimplifyIndirect(x);
        y := x;
        TemporaryReg(x, x.type);
        CGL.PutLoad(x, y);
        CGL.Release(y);
      END;
    END;
  END loadI;

  PROCEDURE Load(VAR x : CGL.Item);
  BEGIN
    IF x.mode # CGL.Ireg THEN
      IF x.type.form IN ST.RealSet THEN
        loadF(x, x.type);
      ELSE
        loadI(x);
      END;
    END;
  END Load;

  PROCEDURE LoadBool(VAR x : CGL.Item);
    VAR zero, result : CGL.Item;
  BEGIN
    ASSERT(x.type.form = ST.bool);
    IF x.mode # CGL.Icoc THEN
      IF x.mode = CGL.Iconst THEN
        TemporaryReg(x, ST.booltyp); (* Icoc must be a register *)
        IF x.val.i0 = OPM.TrueVal THEN
          SetCC(x, CGL.ccAW);
        ELSE
          SetCC(x, CGL.ccNV);
        END;
      ELSE
        Load(x);
        LoadZero(zero);
        TemporaryReg(result, x.type);
        CGL.PutCompare(x, zero, result);
        SetCC(result, CGL.ccNE); (* result # 0 --> TRUE *)
        CGL.Release(x);
        x := result;
      END;
    END;
  END LoadBool;

  PROCEDURE JmpT*(VAR x : CGL.Item; VAR lab : CGL.Label);
  BEGIN
    LoadBool(x);
    CGL.JmpT(x, lab);
  END JmpT;

  PROCEDURE JmpF*(VAR x : CGL.Item; VAR lab : CGL.Label);
  BEGIN
    LoadBool(x);
    CGL.JmpF(x, lab);
  END JmpF;

  PROCEDURE Trap(n : LONGINT);
    VAR
      val : CGL.Item;
      r1  : CGL.Item;
  BEGIN
    MakeConstItem(val, n, ST.linttyp);
    CGL.InitItem(r1);
    r1.mode   := CGL.Ireg;
    r1.reg    := 1; (* R1 *)
    r1.type   := ST.linttyp;
    r1.mnolev := 0;
    Move(r1, val);
    CGL.CallCompilerHelper("Kernel", "SysTrap");
  END Trap;

  (* Simplify
   *
   *   Coerce an Item into using a different register than it is
   *   already using.
   *
   *   Rx = suitable destination registers
   *)

  PROCEDURE Simplify(VAR x : CGL.Item; Rx : SET);
    VAR
      rs : SET;
      m : SHORTINT;
      y : CGL.Item;

    PROCEDURE Reassign(VAR reg : LONGINT);
      VAR
        r0, r1 : CGL.Item;
    BEGIN
      CGL.InitItem(r0);
      TemporaryReg(r0, ST.linttyp);
      r0.mnolev := x.mnolev;

      CGL.InitItem(r1);
      r1.type   := ST.linttyp;
      r1.mnolev := x.mnolev;
      r1.mode   := CGL.Ireg;
      r1.reg    := reg;
      CGL.Release(r1);
      CGL.GetReg(r1, {reg}); (* Ensure no other Item uses this register. *)

      Move(r0, r1);
      CGL.Release(r1);
      reg := r0.reg;
    END Reassign;

  BEGIN
    rs := Rx * CGL.GRegFree;
    m  := x.mode;
    y  := x;
    IF (rs = {}) & (m IN {CGL.Ivarx, CGL.Iindx, CGL.Iregi, CGL.Iregix}) THEN
      (* No registers available; reuse something already being
       *  used by this CGL.Item. *)
      IF m IN {CGL.Ivarx, CGL.Iindx} THEN
        IF x.inxreg * Rx # {} THEN
          Reassign(x.inxreg);
        END;
      ELSIF m = CGL.Iregi THEN
        IF x.reg * Rx # {} THEN
          Reassign(x.reg);
        END;
      ELSIF m = CGL.Iregix THEN
        IF x.reg * Rx # {} THEN
          Reassign(x.reg);
        ELSIF x.inxreg * Rx # {} THEN
          Reassign(x.inxreg);
        END;
      END;
    ELSIF m IN {CGL.Ivarx, CGL.Iindx, CGL.Ireg, CGL.Iregi, CGL.Iregix} THEN
      CGL.GetReg(x, rs);
      Move(x, y);
      CGL.Release(y);
    END;
  END Simplify;

  (* Load an item into one of a specific set of registers *)
  PROCEDURE LoadItem(VAR x : CGL.Item; Rx : SET); (* Rx <=> register set which x can use *)
    VAR y : CGL.Item; s : SET;
  BEGIN
    ASSERT(~(x.type.form IN ST.RealSet), 212);
    y := x;
    CASE x.mode OF
    |  CGL.Ivar, CGL.Ipar:
       CGL.GetReg(x, Rx);
       Move(x, y);

    |  CGL.Ivarpar, CGL.Iind:
       CGL.GetReg(x, Rx);
       Move(x, y);

    |  CGL.Iconst:
       CGL.GetReg(x, Rx);
       Move(x, y);

    |  CGL.Ivarx:
       IF x.inxreg IN Rx THEN
         CGL.DoubleRef(y);
         x.mode := CGL.Ireg;
         x.reg  := x.inxreg;
         Move(x, y);
         CGL.Release(y);
       ELSE
         CGL.GetReg(x, Rx);
         Move(x, y);
         CGL.Release(y);
       END;

    |  CGL.Iindx:
       IF x.inxreg IN Rx THEN
         CGL.DoubleRef(y);
         x.mode := CGL.Ireg;
         x.reg  := x.inxreg;
         Move(x, y);
         CGL.Release(y);
       ELSE
         CGL.GetReg(x, Rx);
         Move(x, y);
         CGL.Release(y);
       END;

    |  CGL.Ireg, CGL.Iregi:
       IF ~(x.reg IN Rx) THEN
         CGL.GetReg(x, Rx);
         Move(x, y);
         CGL.Release(y);
       END;

    |  CGL.Iregix:
       s := {};
       INCL(s, SHORT(SHORT(x.reg)));
       INCL(s, SHORT(SHORT(x.inxreg)));

       IF s * Rx # s THEN
         x.mode := CGL.Ireg;
         IF x.reg IN Rx THEN
           CGL.DoubleRef(x);
           Move(x, y);
           CGL.Release(y);
         ELSIF x.inxreg IN Rx THEN
           x.reg := x.inxreg;
           CGL.DoubleRef(x);
           Move(x, y);
           CGL.Release(y);
         ELSE
           CGL.GetReg(x, Rx);
           Move(x, y);
           CGL.Release(y);
         END;
       END;

    | CGL.Iadr:
      CGL.GetReg(x, Rx);
      CGL.PutLoadAddress(x, y);

    |  Itos:
       CGL.GetReg(x, Rx);
       Move(x, y);
    END;
  END LoadItem;

  (* load x into Rx -- but remove y from Rx *)
  PROCEDURE LoadItem2(VAR x : CGL.Item; Rx : SET; VAR y : CGL.Item);
    VAR free, targ : SET;
  BEGIN
    free := CGL.AvailableGRegs();
    targ := CGL.RegWord - Rx;
    IF free * Rx = {} THEN
      CASE y.mode OF
      |  CGL.Ivarx, CGL.Iindx:
         IF y.inxreg IN Rx THEN
           Simplify(y, targ);
         END;

      |  CGL.Iregi:
         IF y.reg IN Rx THEN
           Simplify(y, targ);
         END;
      |  CGL.Iregix:
         IF (y.reg IN Rx) OR (y.inxreg IN Rx) THEN
           Simplify(y, targ);
         END;
      ELSE (* nop; we will get an error on register allocation *)
      END;
    END;
    LoadItem(x, Rx);
  END LoadItem2;

  (* CommonLoad
   *
   *  If 'common' is set in 'x', it references the same thing as 'y';
   *  load 'y' into a register.  Otherwise load 'x'.
   *
   *  XXX This function isn't very useful for SKL.
   *)
  PROCEDURE CommonLoad(VAR x, y : CGL.Item);
  BEGIN
    IF (CGL.common IN x.flags) THEN
      IF (x.mode # CGL.Ireg) & ~(y.mode IN {CGL.Iconst, CGL.Ireg}) THEN
        Load(y);
      END;
    ELSE
      Load(x);
    END;
  END CommonLoad;


  PROCEDURE CheckRange(VAR x : CGL.Item; lo, hi : LONGINT);
    VAR
      y : CGL.Item;
      result : CGL.Item;
      pass, fail : CGL.Label;
  BEGIN
    IF (OPM.RanChk IN OPM.options) & ~(x.type.form IN {ST.char, ST.byte}) THEN
      Load(x);
      ASSERT(x.mode = CGL.Ireg);
      CGL.PutSysTrap(CGL.opcTRAPRANGE, x.type.form, x);
    END;
  END CheckRange;

  PROCEDURE CheckSetRange(VAR x : CGL.Item);
    VAR
      zero, result, y : CGL.Item; fail, pass: CGL.Label;
  BEGIN
    IF (OPM.RanChk IN OPM.options) & (x.mode # CGL.Iconst) THEN
      IF x.mode # CGL.Ireg THEN
        Load(x);
      END;
      CGL.PutSysTrap(CGL.opcTRAPRANGE, x.type.form, x);
    END;
  END CheckSetRange;

  (* GetArrayDimLen
   *
   *   Set y to 'LEN(x, arr.n)' (bound is one (1) less than the length).
   *)
  PROCEDURE GetArrayDimLen(VAR x, y : CGL.Item; arr : ST.Array);
    VAR f : SHORTINT;
  BEGIN
    f := arr.form;
    ASSERT(f IN {ST.array, ST.dynarr});
    IF f = ST.dynarr THEN
      y := x;
      y.type := ST.linttyp;
      CASE x.mode OF
      |  CGL.Ivar: (* variable *)
         y.adr    := arr.lenTDOffs;
         y.offset := 0;

      |  CGL.Ivarpar, CGL.Ipar: (* [var] dynarr parm *)
         y.mode := CGL.Ivar;
         INC(y.adr, arr.lenTDOffs);

      | CGL.Iregix:
        y.mode := CGL.Iregi;
        CGL.DoubleRef(y);
        INC(y.offset, arr.lenTDOffs);

      |  CGL.Iregi, CGL.Iind, CGL.Iindx:
         (* pointing at data or a variable (which must be a pointer) *)
         CGL.DoubleRef(x);
         INC(y.offset, arr.lenTDOffs);
      END;
    ELSE
      MakeConstItem(y, arr.len, ST.linttyp);
    END;
  END GetArrayDimLen;


  (* Field: Produce the address of a record field.
   * The result must be the address of a record's field, and it
   * cannot be Iregix, because x.type will be changed to the type of
   * the referenced field by the caller of this function.  This will
   * make scaling of the index wrong during delayed code generation.
   *)
  PROCEDURE Field*(VAR x : CGL.Item; offset : LONGINT);
  BEGIN
    CASE x.mode OF
    |  CGL.Ivar:
       INC(x.adr, offset);

    |  CGL.Ipar:
       IF x.type.form = ST.dynarr THEN (* Ivarpar *)
         x.mode := CGL.Iind;
         x.offset := offset;
       ELSE
         INC(x.adr, offset);
       END;

    |  CGL.Ivarpar:
       x.mode := CGL.Iind;
       x.offset := offset;

    |  CGL.Ivarx, CGL.Iind, CGL.Iindx:
       TakeAddress(x, CGL.RegWord, TRUE);
       x.mode := CGL.Iregi;
       x.offset := offset;

    | CGL.Iregi, CGL.Iregix:
      x.offset := offset;
      TakeAddress(x, CGL.RegWord, TRUE);
      x.mode := CGL.Iregi;
    END;
  END Field;


  (* checks x for NIL pointer; NIL pointer => HALT(halt) *)
  (* pre: x <=> Ireg *)
  (* post: x is unchanged *)
  PROCEDURE OptPointerCheck(VAR x : CGL.Item; halt : SHORTINT);
    VAR
      lab : CGL.Label;
      zero, result : CGL.Item;
  BEGIN
    IF OPM.OptPtrChk IN OPM.options THEN
      ASSERT(x.mode = CGL.Ireg);
      CGL.PutSysTrap(halt, 0, x);
    END;
  END OptPointerCheck;


  PROCEDURE Deref*(VAR x : CGL.Item);
    VAR y : CGL.Item;
  BEGIN
    IF OPM.OptPtrChk IN OPM.options THEN
      Load(x);
      OptPointerCheck(x, OPM.HaltPointerCheck);
      x.mode := CGL.Iregi;
    ELSE
      CASE x.mode OF
      |  CGL.Ivar:
         x.mode := CGL.Iind;

      |  CGL.Ipar:
         IF x.type.form = ST.dynarr THEN (* Ivarpar *)
           Load(x);
           x.mode := CGL.Iregi;
           x.offset := 0;
         ELSE
           x.mode := CGL.Iind;
         END;

      |  CGL.Ivarpar:
         Load(x);
         x.mode := CGL.Iregi;
         x.offset := 0;

      |  CGL.Ivarx:
         (* 98.03.24: this cannot be transformed into an Iindx because the
          * type of the derefed data is going to be stored into the Item;
          * this will have dire consequences on the address calculation.
          * The only solution is to actually perform the deref here and
          * create an Iregi Item *)
         y := x;
         CGL.GetReg(x, CGL.RegWord);
         Move(x, y);
         x.mode := CGL.Iregi;
         CGL.Release(y);

      |  CGL.Iind:
         y := x;
         CGL.GetReg(x, CGL.RegWord);
         Move(x, y);
         x.mode := CGL.Iregi;

      |  CGL.Iindx:
         y := x;
         CGL.GetReg(x, CGL.RegWord);
         Move(x, y);
         x.mode := CGL.Iregi;
         CGL.Release(y);
      |  CGL.Iregi, CGL.Iregix:
         y := x;
         CGL.GetReg(x, CGL.RegWord);
         Move(x, y);
         x.mode := CGL.Iregi;
         CGL.Release(y);
      END;
    END;
    x.offset := 0;
  END Deref;


  PROCEDURE Index*(VAR x, index : CGL.Item); (* set x to ADR(x[index]) *)
    VAR
      len, inxreg, one : CGL.Item;
      open : BOOLEAN;
      arr : ST.Array;
      label : CGL.Label;
  BEGIN
    arr := x.type(ST.Array);
    Widen(index, ST.linttyp);
    IF arr.form = ST.array THEN
      open := FALSE;
      IF index.mode = CGL.Iconst THEN
        Field(x, index.val.i0 * arr.of.size);
        RETURN;
      END;
    ELSE
      open := TRUE;
    END;

    IF ((OPM.InxChk IN OPM.options) & (* Bounds check. *)
        ((index.mode # CGL.Iconst) OR
         (index.val.i0 # 0))) THEN
      IF open THEN
        GetArrayDimLen(x, len, arr); (* [len] = address of bounds *)
        Load(len);
        MakeConstItem(one, 1, ST.linttyp);
        CGL.PutAddConstant(len, one, len);
      ELSE
        MakeConstItem(len, arr.len, ST.linttyp);
        Load(len);
      END;
      Load(index);
      CGL.PutSysTrapArray(index, len);
      CGL.Release(len);
    END;

    CASE x.mode OF
    |  CGL.Ivar:
       IF index.mode = CGL.Iconst THEN
         INC(x.adr, index.val.i0);
       ELSE
         Load(index);
         x.mode := CGL.Ivarx;
         x.inxreg := index.reg;
       END;

    |  CGL.Ipar:
       IF x.type.form = ST.dynarr THEN (* Implied Ivarpar. *)
         IF index.mode = CGL.Iconst THEN
           x.mode := CGL.Iind;
           x.offset := index.val.i0;
         ELSE
           Load(index);
           TakeAddress(x, CGL.RegWord, TRUE);
           x.mode   := CGL.Iregix;
           x.offset := 0;
           x.inxreg := index.reg;
         END;
       ELSE
         IF index.mode = CGL.Iconst THEN
           INC(x.adr, index.val.i0);
         ELSE
           Load(index);
           x.mode   := CGL.Ivarx;
           x.inxreg := index.reg;
         END;
       END;

    |  CGL.Ivarpar:
       IF index.mode = CGL.Iconst THEN
         x.mode := CGL.Iind;
         x.offset := index.val.i0;
       ELSE
         Load(index);
         TakeAddress(x, CGL.RegWord, TRUE);
         x.mode   := CGL.Iregix;
         x.offset := 0;
         x.inxreg := index.reg;
       END;

    |  CGL.Iind:
       IF index.mode = CGL.Iconst THEN
         INC(x.offset, index.val.i0);
       ELSE
         Load(index);
         TakeAddress(x, CGL.RegWord, TRUE);
         x.mode   := CGL.Iregix;
         x.offset := 0;
         x.inxreg := index.reg;
       END;

    |  CGL.Iregi:
       IF index.mode = CGL.Iconst THEN
         INC(x.offset, index.val.i0 * x.type(ST.Array).of.size);
       ELSE
         Load(index);
         x.mode   := CGL.Iregix;
         x.inxreg := index.reg;
       END;

    |  CGL.Ivarx, CGL.Iindx, CGL.Iregix:
       (* This is a dynamic heap-based array.  The
        * length stored in the internal type descriptor is
        * LEN(x, dim) - 1.  This needs to be added back so
        * the multiplication comes out correctly.
        *)
       GetArrayDimLen(x, len, arr);
       IF open THEN
         Load(len);
         MakeConstItem(one, 1, ST.linttyp);
         CGL.PutAddConstant(len, one, len);
       END;
       (* len is now the length of the arrray. *)

       CGL.InitItem(inxreg);
       inxreg.mode := CGL.Ireg;
       inxreg.reg  := x.inxreg;
       inxreg.type := ST.linttyp;
       CGL.DoubleRef(inxreg);
       CGL.DoubleRef(len);

       Mul(inxreg, len);
       Add(inxreg, index);
       CGL.DoubleRef(inxreg);
       x.inxreg := inxreg.reg;
       CGL.Release(len);
       CGL.Release(inxreg);
    END;
  END Index;

  PROCEDURE Not*(VAR x : CGL.Item);
    VAR
      t : CGL.Label;
      zero : CGL.Item;
  BEGIN
    CASE x.mode OF
    | CGL.Icoc:
      x.cc         := CGL.Inverted(x.cc);
      t            := x.jump.true;
      x.jump.true  := x.jump.false;
      x.jump.false := t;

    | CGL.Ireg:
      MakeConstItem(zero, 0, ST.linttyp);
      Load(zero);
      CGL.PutCompare(x, zero, x);
      SetCC(x, CGL.ccEQ); (* ~(x = 0) --> TRUE *)

    | CGL.Iconst:
      IF x.val.i0 = OPM.TrueVal THEN
        x.val.i0 := OPM.FalseVal;
      ELSE
        x.val.i0 := OPM.TrueVal;
      END;
    ELSE
      MakeConstItem(zero, 0, ST.linttyp);
      Load(zero);
      Load(x);
      CGL.PutCompare(x, zero, x);
      SetCC(x, CGL.ccEQ);       (* ~(x = 0) --> TRUE *)
    END;
  END Not;

  PROCEDURE Interfere*(VAR x : CGL.Item; regs : CGL.GRegSet);

    (* if there is interference, the entire dword register must be assumed to be needed *)
    PROCEDURE uninterfere(VAR r0 : LONGINT; taken : CGL.GRegSet);
      VAR y, z : CGL.Item; r1 : LONGINT;
    BEGIN
      IF r0 IN taken THEN
        CGL.InitItem(y);
        CGL.InitItem(z);
        CGL.GetReg(y, CGL.RegWord - taken);
        y.type := ST.linttyp;
        z.mode := CGL.Ireg;
        z.reg  := r0;
        z.type := ST.linttyp;
        Move(y, z);
        r1 := r0;
        r0 := y.reg;
        y.reg := r1;
        CGL.Release(y);
      END;
    END uninterfere;

  BEGIN
    IF regs # {} THEN
      CASE x.mode OF
      |  CGL.Imethod: uninterfere(x.td.reg, regs);
      |  CGL.Ivarx, CGL.Iindx: uninterfere(x.inxreg, regs);
      |  CGL.Ireg, CGL.Iregi: uninterfere(x.reg, regs);
      |  CGL.Iregix: uninterfere(x.reg, regs); uninterfere(x.inxreg, regs);
      ELSE (* nop, no registers for Item *)
      END;
    END;
  END Interfere;

  (* LoadInto
   *
   *   Load 'x' into a register in 'regs'.
   *)
  PROCEDURE LoadInto*(VAR x : CGL.Item; regs : CGL.GRegSet);
    VAR y : CGL.Item;
  BEGIN
    IF ~(x.mode IN {CGL.Ireg, CGL.Icoc}) OR ~(x.reg IN regs) THEN
      (* 'x' is not in a register, or not in the proper register. *)
      IF ((x.mode IN {CGL.Ivarx, CGL.Iindx, CGL.Iregi, CGL.Iregix}) &
          (regs * CGL.GRegFree = {})) THEN
        (* When 'x' is using a register, and the destination register
         * is not free, simplify its mode to free up the
         * destination  register. *)
        Simplify(x, regs);
      END;
      CGL.InitItem(y);
      CGL.GetReg(y, CGL.RegWord * regs);
      y.mode := CGL.Ireg;
      y.type := x.type;
      Move(y, x);
      x := y;
    END;
  END LoadInto;


  PROCEDURE Negate*(VAR x : CGL.Item);
    VAR
      zero : CGL.Item;
  BEGIN
    IF x.mode = CGL.Iconst THEN
      CASE x.type.form OF
      |  ST.sint, ST.int, ST.lint:
         x.val.i0 := -x.val.i0;

      |  ST.set:
         x.val.set := -x.val.set;

      |  ST.real, ST.lreal:
         x.val.real := -x.val.real;
      END;
    ELSE
      MakeConstItem(zero, 0, ST.linttyp);
      Load(zero);
      Load(x);
      IF x.type.form = ST.set THEN
        (* Bitwise negate *)
        CGL.PutIntReg(CGL.opcNOR, x, zero, x);
      ELSE
        (* Arithmetic negate *)
        CGL.PutGenReg(CGL.opcSUB, zero, x, x);
      END;
    END;
  END Negate;

  PROCEDURE SetElem*(VAR x : CGL.Item);
    VAR
      y : CGL.Item;
  BEGIN
    IF x.mode = CGL.Iconst THEN
      MakeConstItem(x, ASH(1, x.val.i0), ST.settyp);
    ELSE
      y := x;
      CGL.DoubleRef(x);
      CheckRange(y, 0, OPM.MaxSet);
      Shorten(y, ST.sinttyp);
      Load(y);                  (* Load bit element to register. *)
      y.type := ST.settyp;
      CGL.PutIntReg(CGL.opcBITSET, y, y, y); (* BITSET Ry, Ry, Rx *)
      x := y;
    END;
  END SetElem;


  PROCEDURE Convert*(VAR x : CGL.Item; to, from: SHORTINT);
    VAR temp : CGL.Item;
  BEGIN (* integer to set <=> SetElem *)
    IF to # from THEN
      CASE to OF
      |  ST.char:
         Load(x);
         x.type := ST.chartyp;
         CheckRange(x, 0, MaxChar);

      | ST.sint:
        IF ~(from IN {ST.char, ST.byte}) THEN
          Shorten(x, ST.sinttyp);
        ELSE
          x.type := ST.sinttyp;
        END;
        CheckRange(x, OPM.MinSInt, OPM.MaxSInt);

      |  ST.int:
         IF from IN {ST.char, ST.sint} THEN
           Widen(x, ST.inttyp);
         ELSE
           Shorten(x, ST.inttyp);
           CheckRange(x, OPM.MinInt, OPM.MaxInt);
         END;

      |  ST.lint:
         IF from IN {ST.sint, ST.int} THEN
           Widen(x, ST.linttyp);
         ELSIF from IN ST.RealSet THEN
           Load(x);
           TemporaryReg(temp, ST.linttyp);
           Move(temp, x);
           CGL.Release(x);
           x := temp;
         END;

      |  ST.real:
         loadF(x, ST.realtyp);

      |  ST.lreal:
         loadF(x, ST.lrltyp);
      END;
    END;
  END Convert;

  PROCEDURE Relation*(VAR x : CGL.Item);
    VAR y : CGL.Item;
  BEGIN
    IF x.mode = CGL.Icoc THEN
      x.mode := CGL.Ireg;
      CGL.DoubleRef(x);
    END;
  END Relation;

  PROCEDURE Mul*(VAR x, y : CGL.Item); (* arithmetic *, set intersection *)
    VAR
      f : SHORTINT;
      dest : CGL.Item;
  BEGIN
    Load(x);
    Load(y);
    TemporaryReg(dest, x.type);
    f := x.type.form;
    IF f = ST.set THEN
      CGL.PutIntReg(CGL.opcAND, x, y, dest);
    ELSIF f IN ST.IntSet + ST.RealSet THEN
      CGL.PutGenReg(CGL.opcMUL, x, y, dest);
    END;
    x := dest;
  END Mul;

  PROCEDURE Div*(VAR x, y : CGL.Item); (* x DIV y; x is synthesized output *)
    VAR
      result : CGL.Item;
  BEGIN
    Load(x);
    Load(y);
    result := x;
    CGL.DoubleRef(result);
    CGL.PutGenReg(CGL.opcDIV, x, y, result);
    CGL.Release(y);
    CGL.Release(result);
  END Div;

  PROCEDURE Slash*(VAR x, y : CGL.Item); (* arithmetic /, set symmetric difference (xor) *)
  BEGIN
    Load(x);
    Load(y);
    CGL.DoubleRef(x);
    IF x.type.form = ST.set THEN
      CGL.PutIntReg(CGL.opcXOR, x, y, x);
    ELSE
      CGL.PutGenReg(CGL.opcDIV, x, y, x);
    END;
    CGL.Release(y);
    CGL.Release(x);
  END Slash;

  PROCEDURE Msk*(VAR x, y : CGL.Item);
  BEGIN
    y.val.i0 := SYSTEM.VAL(LONGINT, -SYSTEM.VAL(SET, y.val.i0));
    Load(x);
    Load(y);
    y.type := x.type;
    CGL.DoubleRef(x);
    CGL.PutIntReg(CGL.opcAND, x, y, x);
    CGL.Release(x);
  END Msk;

  PROCEDURE Mod*(VAR x, y : CGL.Item);
    VAR
      result : CGL.Item;
  BEGIN
    Load(x);
    Load(y);
    result := x;
    CGL.DoubleRef(result);
    CGL.PutGenReg(CGL.opcMOD, x, y, result);
    CGL.Release(y);
    CGL.Release(result);
  END Mod;

  PROCEDURE Add*(VAR x, y : CGL.Item); (* arithmetic +, set union *)
    VAR
      f    : SHORTINT;
      dest : CGL.Item;
  BEGIN
    f := x.type.form;
    IF f = ST.set THEN
      CommonLoad(x, y);
      Load(x);
      Load(y);
      dest := x;
      CGL.DoubleRef(dest);
      CGL.PutIntReg(CGL.opcOR, x, y, dest);
      CGL.Release(x);
    ELSIF f IN ST.IntSet THEN
      Load(x);
      IF (x.mode = CGL.Ireg) & (y.mode = CGL.Iconst) THEN
        CGL.PutAddConstant(x, y, x); (* Use LA to perform add. *)
      ELSE
        Load(y);
        TemporaryReg(dest, x.type);
        CGL.PutGenReg(CGL.opcADD, x, y, dest);
        CGL.Release(x);
        x := dest;
        END;
    ELSE
      ASSERT(f IN ST.RealSet);
      Load(x);
      Load(y);
      TemporaryReg(dest, x.type);
      CGL.PutGenReg(CGL.opcADD, x, y, dest);
      CGL.Release(x);
      x := dest;
    END;
    CGL.Release(y);
  END Add;

  PROCEDURE Sub*(VAR x, y : CGL.Item); (* arithmetic -, set difference *)
    VAR
      f    : SHORTINT;
      dest : CGL.Item;
      zero : CGL.Item;
      noty : CGL.Item;
      negy : CGL.Item;
  BEGIN
    Load(x);
    CGL.DoubleRef(x);
    TemporaryReg(dest, x.type);
    TemporaryReg(noty, y.type);

    f := x.type.form;
    IF f = ST.set THEN
      Load(y);
      CGL.DoubleRef(y);
      MakeConstItem(zero, 0, x.type);
      Load(zero);
      CGL.PutIntReg(CGL.opcNOR, y, zero, noty);
      CGL.PutIntReg(CGL.opcAND, x, noty, dest);
      CGL.Release(y);
    ELSIF f IN ST.IntSet THEN
      IF (x.mode = CGL.Ireg) & (y.mode = CGL.Iconst) THEN
        dest := x;
        negy := y;
        negy.val.i0 := -negy.val.i0;
        CGL.PutAddConstant(dest, negy, dest); (* Use LA to perform subtraction. *)
      ELSE
        Load(y);
        CGL.DoubleRef(y);
        CGL.PutGenReg(CGL.opcSUB, x, y, dest);
        CGL.Release(y);
      END;
    ELSE
      ASSERT(f IN ST.RealSet);
      Load(y);
      CGL.DoubleRef(y);
      CGL.PutGenReg(CGL.opcSUB, x, y, dest);
      CGL.Release(y);
    END;
    CGL.Release(x);
    CGL.Release(noty);
    x := dest;
  END Sub;

  PROCEDURE ConditionalAnd*(VAR x : CGL.Item);
  BEGIN
    LoadBool(x);
    CGL.PutJump(CGL.Inverted(x.cc), x, x.jump.false);
    CGL.FixJcc(x.jump.true);
  END ConditionalAnd;

  PROCEDURE And*(VAR x, y : CGL.Item);
  BEGIN
    LoadBool(y);
    CGL.MergeJcc(x.jump.false, y.jump.false); (* (merge output links) if y is OR operator,
                                               * then y.jump.false set, otherwise NIL *)
    CGL.JoinJcc(x.jump.true, y.jump.true);
    CGL.Release(x);
    x.reg := y.reg;
    x.cc  := y.cc;
  END And;

  PROCEDURE ConditionalOr*(VAR x : CGL.Item);
  BEGIN
    LoadBool(x);
    CGL.PutJump(x.cc, x, x.jump.true);
    CGL.FixJcc(x.jump.false);
  END ConditionalOr;

  PROCEDURE Or*(VAR x, y : CGL.Item);
  BEGIN
    LoadBool(y);
    CGL.MergeJcc(x.jump.true, y.jump.true); (* (merge output links) if y is
                                             * '&' operator, then y.jump.true
                                             *  set, otherwise NIL *)
    CGL.JoinJcc(x.jump.false, y.jump.false);
    CGL.Release(x);
    x.reg := y.reg;
    x.cc  := y.cc;
  END Or;

  PROCEDURE Compare*(VAR x, y : CGL.Item; rel : SHORTINT); (* synth: x rel y *)
    VAR Rt, R0, z  : CGL.Item; f : SHORTINT;
  BEGIN
    (* 'rel' is a CGL relational opcode for a compare instruction *)
    ASSERT(rel IN CGL.ccSet, 200);
    TemporaryReg(Rt, ST.booltyp);
    f := x.type.form;
    CASE f OF
    |  ST.byte, ST.char, ST.sint, ST.int, ST.lint, ST.set, ST.pointer, ST.procedure:
       Load(x);
       Load(y);
       (* change to unsigned comparison for char, byte and set *)
       IF f IN {ST.char, ST.byte, ST.set} THEN
         IF rel = CGL.ccLT THEN
           rel := CGL.ccLTU;
         ELSIF rel = CGL.ccLE THEN
           rel := CGL.ccLEU;
         ELSIF rel = CGL.ccGT THEN
           rel := CGL.ccGTU;
         ELSIF rel = CGL.ccGE THEN
           rel := CGL.ccGEU;
         ELSE
           ASSERT(rel IN { CGL.ccEQ, CGL.ccNE }, 201); (* nop *)
         END;
       END;
       CGL.PutCompare(x, y, Rt);

    |  ST.real, ST.lreal:
       Load(x);
       Load(y);
       CGL.PutCompare(x, y, Rt);

    |  ST.bool:
       Load(x);
       IF y.mode = CGL.Icoc THEN
         z := y;
         z.mode := CGL.Ireg;
         CGL.PutCompare(x, z, Rt);
       ELSE
         Load(y);
         CGL.PutCompare(x, y, Rt);
       END;
    ELSE (* string *)
      TakeAddress(x, CGL.RegWord, TRUE);
      TakeAddress(y, CGL.RegWord, TRUE);
      CGL.PutIntReg(CGL.opcCMPS, x, y, Rt);
    END;

    SetCC(Rt, rel);
    CGL.Release(x);
    CGL.Release(y);
    x := Rt;
  END Compare;

  PROCEDURE SetIn*(VAR bit, set : CGL.Item); (* bit IN set; bit is result *)
    VAR Rd : CGL.Item;
  BEGIN
    Load(set);
    IF bit.mode # CGL.Iconst THEN
      Load(bit);
    END;
    TemporaryReg(Rd, ST.linttyp);
    CheckSetRange(bit);
    CGL.PutBitTest(bit, set, Rd); (* post: Rd IN { 0, 1 } *)
    CGL.Release(set);
    CGL.Release(bit);
    Rd.mode := CGL.Icoc;
    Rd.cc   := CGL.ccEQ;
    bit := Rd;
  END SetIn;

  PROCEDURE SetRange*(VAR x, y : CGL.Item);
    VAR rd : CGL.Item;
  BEGIN
    CGL.InitItem(rd);
    rd.type := ST.linttyp;

    LoadItem(x, CGL.RegWord);
    IF x.mode # CGL.Iconst THEN
      CheckSetRange(x);
    END;

    LoadItem(y, CGL.RegWord);
    IF y.mode # CGL.Iconst THEN
      CheckSetRange(y);
    END;

    CGL.GetReg(rd, CGL.RegWord);
    CGL.PutIntReg(CGL.opcBITSET, x, y, rd);
    CGL.Release(x);
    CGL.Release(y);
    x := rd;
  END SetRange;

  (* var(type), var IS type
    Ensure that the current type is of the tested type.
    result := var.ExtTab[type.extlev] = type
    (The type.extlev-th entry in the extension table of var must be the same as that of type)
  *)
  PROCEDURE CompareTD(VAR var, type : CGL.Item; VAR res : CGL.Item);
    VAR
      avmt : CGL.Item;
      m    : SHORTINT;
      ExtTabIndex : LONGINT;
  BEGIN
    TemporaryReg(res, ST.linttyp);
    avmt := var;
    CGL.DoubleRef(avmt);
    IF var.type.form = ST.record THEN (* varpar *)
      ExtTabIndex := 4 * type.type(ST.Record).extlev;
      avmt.mode   := CGL.Iind;
      avmt.type   := ST.linttyp;
      avmt.adr    := SIZE(LONGINT); (* TD is pushed before parm *)
      avmt.offset := OPM.RecTDTab;
      Load(avmt);
      (* inv: avmt holds the extension table address *)
    ELSE (* pointer *)
      m := var.mode;
      ASSERT(m IN {CGL.Ivar, CGL.Ipar, CGL.Ivarpar, CGL.Iind,
                   CGL.Iindx, CGL.Iregi, CGL.Iregix});
      IF m IN {CGL.Ivar, CGL.Ipar} THEN
        IF OPM.OptPtrChk IN OPM.options THEN
          (* pointer check enabled, check pointer before deref *)
          avmt.mode := CGL.Ivar;
          Load(avmt); (* MOV Ravmt, [avmt] *)
          OptPointerCheck(avmt, OPM.HaltGuardCheck);
          avmt.mode := CGL.Iregi;
          avmt.offset := -4;
          Load(avmt);
        ELSE
          avmt.mode := CGL.Iind;
          avmt.offset := -4;
          Load(avmt); (* MOV Ravmt, [[avmt]-4] *)
        END;
        (* inv: avmt holds the TD pointer *)
      ELSIF m IN {CGL.Ivarpar} THEN (* VAR pointer *)
        avmt.mode := CGL.Iind;
        avmt.offset := 0;
        Load(avmt); (* load pointer *)
        OptPointerCheck(avmt, OPM.HaltGuardCheck);
        avmt.mode := CGL.Iregi;
        avmt.offset := -4;
        Load(avmt);
        (* inv: avmt holds the TD pointer *)
      ELSIF m IN {CGL.Iind, CGL.Iindx, CGL.Iregi, CGL.Iregix} THEN
        Load(avmt);
        OptPointerCheck(avmt, OPM.HaltGuardCheck);
        avmt.mode := CGL.Iregi;
        avmt.offset := -4;
        avmt.type := ST.linttyp;
        Load(avmt);
        (* inv: avmt holds the TD pointer *)
      END;
      avmt.mode := CGL.Iregi;
      avmt.offset := OPM.RecTDTab;
      Load(avmt);
      ExtTabIndex := 4 * type.type(ST.Record).extlev;
      (* inv: avmt holds the extension table address *)
    END;
    (* inv: avmt holds the extension table address *)

    ASSERT(avmt.mode = CGL.Ireg, 191);
    avmt.mode := CGL.Iregi;
    (* inv: avmt holds address of extension table for the tested variable *)
    (* inv: type is the type desc being checked against *)
    avmt.offset := ExtTabIndex;
    Load(avmt);
    type.type := ST.linttyp;
    Load(type);
    CGL.PutCompare(avmt, type, res); (* seq var.extension[type.extlev], TD(type), res *)
    SetCC(res, CGL.ccEQ);
  END CompareTD;

  PROCEDURE MakeVar*(VAR x : CGL.Item; sym : ST.Symbol; type : ST.Type);
  BEGIN
    CGL.InitItem(x);
    x.mode   := CGL.Ivar;
    x.adr    := 0;
    x.offset := 0;
    x.sym    := sym;
    x.type   := type
  END MakeVar;

  PROCEDURE TypeGuard*(VAR var, type : CGL.Item; explicit : BOOLEAN);
    (* var(type[td]); type <=> type descriptor *)
    VAR
      lab : CGL.Label;
      halt : INTEGER;
      tvar, td, Rt : CGL.Item;
      tdtype : ST.Type;
      result : CGL.Item;
  BEGIN
    IF explicit OR (OPM.TypChk IN OPM.options) THEN
      lab := NIL;
      IF explicit THEN
        halt := OPM.HaltEGuard;
        tdtype := type.sym(ST.SymbolTypeDesc).described;
        TakeAddress(type, CGL.RegWord, FALSE);
        type.type := tdtype;
        CompareTD(var, type, result);
      ELSE (* implicit guard only for record assignment:
            * tested variable is either a varpar or a dereferenced pointer. *)
        halt := OPM.HaltIGuard;
        MakeVar(td, type.sym, ST.linttyp);
        TakeAddress(td, {}, FALSE);
        tvar := var;
        CGL.DoubleRef(tvar);
        IF tvar.mode = CGL.Ivarpar THEN
          tvar.mode := CGL.Ivar;
          INC(tvar.adr, 4); (* TD pushed before parm *)
        ELSE
          tvar.offset := -4;
        END;
        tvar.type := ST.linttyp;
        Load(tvar);
        Load(td);
        TemporaryReg(result, ST.linttyp);
        (* inv: tvar is the type descriptor of the variable *)
        CGL.PutCompare(tvar, td, result);
        SetCC(result, CGL.ccEQ);
      END;
      CGL.PutJump(CGL.ccEQ, result, lab);
      Trap(halt);
      CGL.SetLabel(lab);
    END;
    var.type := type.type;
  END TypeGuard;

  PROCEDURE IsTest*(VAR var, type : CGL.Item); (* var IS type *)
    VAR
      result : CGL.Item;
  BEGIN
    CompareTD(var, type, result);
    SetCC(result, CGL.ccEQ);
    var := result;
  END IsTest;

  (* push dynamic array bound (not LEN()) onto the stack *)
  PROCEDURE DynArrBnd(VAR fp, ap : CGL.Item);
    VAR
      one, stk, x, y, z : CGL.Item;
      ft, at : ST.Type;
      oneless: BOOLEAN;
  BEGIN
    CGL.InitItem(stk);
    ft       := fp.type;
    at       := ap.type;
    stk.mode := Itos;
    stk.type := ST.linttyp;

     IF ft(ST.Array).of = ST.bytetyp THEN (* ARRAY OF SYSTEM.BYTE *)
       MakeConstItem(one, 1, ST.linttyp);
       Load(one);
       IF at.form # ST.dynarr THEN (* Static length. *)
         MakeConstItem(y,  at.size - 1, ST.linttyp);
       ELSE (* dynamic length *)
         GetArrayDimLen(ap, y, at(ST.Array));
         oneless := TRUE;
         at := at(ST.Array).of;
         WHILE at.form = ST.dynarr DO
           IF oneless THEN
             Load(y);
             CGL.PutGenReg(CGL.opcADD, y, one, y);
           END;
           GetArrayDimLen(ap, z, at(ST.Array));
           Load(z);
           CGL.PutGenReg(CGL.opcADD, z, one, z);
           Mul(y, z);
           oneless := FALSE;
           at := at(ST.Array).of;
         END;

         IF oneless THEN
           Load(y);
         END;

         IF at.size > 1 THEN
           MakeConstItem(z, at.size, ST.linttyp);
           Mul(y, z);
         END;

         IF oneless THEN
           IF at.size > 1 THEN
             MakeConstItem(z, at.size - 1, ST.linttyp);
             CGL.PutGenReg(CGL.opcADD, y, z, y);
           END;
         ELSE
           CGL.PutGenReg(CGL.opcSUB, y, one, y);
         END;
       END;
       Move(stk, y);
     ELSE
       WHILE ft.form = ST.dynarr DO
         IF at.form = ST.dynarr THEN
           GetArrayDimLen(ap, y, at(ST.Array));
         ELSE (* array *)
           MakeConstItem(y, at(ST.Array).len - 1, ST.linttyp);
         END;
         Move(stk, y); (* final length of the array to stack *)
         ft := ft(ST.Array).of;
         at := at(ST.Array).of;
       END;
     END;
  END DynArrBnd;

  PROCEDURE Assign*(VAR dest, source : CGL.Item);
    VAR param : BOOLEAN; t : CGL.Item; l : LONGINT; df : SHORTINT; (* destination type form *)
  BEGIN
    param := dest.mode = Itos;  (* Parameters get assigned to stack. *)
    df := dest.type.form;
    IF ((df IN {ST.byte, ST.bool, ST.char, ST.sint,
               ST.int, ST.lint, ST.set, ST.pointer}) &
        ~(source.mode IN {CGL.Ireg, CGL.Icoc, CGL.Iconst})) THEN
      Load(source);
    END;

    CASE df OF
    |  ST.bool:
       IF source.mode = CGL.Icoc THEN
         MoveCoc(dest, source);
       ELSE (* regular boolean value *)
         Move(dest, source);
       END;

    |  ST.byte:
       IF param THEN
         Widen(source, ST.linttyp);
       END;
       Move(dest, source);

    |  ST.char, ST.sint:
       IF param THEN
         Widen(source, ST.linttyp);
       END;
       Move(dest, source);

    |  ST.int:
       IF param THEN
         Widen(source, ST.linttyp);
       END;
       Move(dest, source);

    |  ST.lint, ST.real, ST.lreal, ST.set, ST.pointer:
       Move(dest, source);

    |  ST.procedure:
       IF ((dest.type # source.type) &
           (source.type # ST.niltyp) &
           (source.mode IN {CGL.Ilproc, CGL.Ixproc, CGL.Iiproc})) THEN
         TakeAddress(source, CGL.RegWord, FALSE); (* address of real procedure *)
       END;
       Move(dest, source);

    |  ST.record:
       IF param THEN
         TakeAddress(source, CGL.RegWord, FALSE);
         dest.type := ST.linttyp;
         Move(dest, source); (* see Param *)
       ELSE
         MoveMemMemBlock(dest, source, source.type.size);
      END;

    |  ST.array:
       l := dest.type.size;
       IF param THEN
         TakeAddress(source, CGL.RegWord, FALSE);
         dest.type := ST.linttyp;
         Move(dest, source); (* see Param *)
       ELSE (* copy memory block *)
         IF source.type.form = ST.string THEN
           l := source.sym(ST.SymbolConst).val.i0; (* string literal may be shorter
                                                    * than dest; copy only to end of literal *)
         END;
         MoveMemMemBlock(dest, source, l);
       END;

    |  ST.dynarr:
       ASSERT(param, 1000); (* dynamic arrays cannot be assigned to each other,
                             *  only passed as parm *)
       df := dest.type(ST.Array).of.form;
       IF (source.type.form = ST.string) & (df = ST.char) THEN

         (* Char constants already converted to string constants.
          *
          * The length of the string literal in the symbol table includes 0X.
          * But it is removed from the assignment, because '0X' isn't part of
          * the string.  Instead, the 0X is added at the destination end.
          *)
         dest.mode := Itos;
         dest.type := ST.linttyp;
         ASSERT(source.mode = CGL.Ivar, 1001);
         MakeConstItem(t, source.sym(ST.SymbolConst).val.i0 - 1, ST.linttyp);
         Move(dest, t); (* string len - 1 *)
       ELSE
         DynArrBnd(dest, source);
      END;
       TakeAddress(source, CGL.RegWord, FALSE);
       dest.type := ST.linttyp;
       Move(dest, source); (* push address *)
    END;
  END Assign;

  PROCEDURE Param*(VAR ap : CGL.Item; fp : ST.Symbol; deref : BOOLEAN) : INTEGER;
    VAR stk : CGL.Item; bytes : INTEGER;

      PROCEDURE VarParDynarr(f : ST.Symbol; VAR ap : CGL.Item);
      VAR fp : CGL.Item;
      BEGIN
        CGL.InitItem(fp);
        fp.type := f.type;
        DynArrBnd(fp, ap);
        fp.type := ST.linttyp;
        fp.mode := Itos;
        TakeAddress(ap, CGL.RegWord, FALSE);
        Move(fp, ap);
        CGL.Release(ap);
        bytes := SIZE(LONGINT);
      END VarParDynarr;

      PROCEDURE VarParRecord(f : ST.Symbol; VAR ap : CGL.Item; deref : BOOLEAN);
        VAR fp, tp : CGL.Item;
      BEGIN
        CGL.InitItem(fp);
        fp.mode := Itos;
        fp.type := ST.linttyp;
        IF ap.mode = CGL.Ivarpar THEN (* parm & dynamic TD from stack*)
          ap.mode := CGL.Ivar;
          INC(ap.adr, SIZE(LONGINT)); (* td *)
          ap.type := ST.linttyp;
          tp := ap;
          Move(fp, ap);
          ap := tp;
	  DEC(ap.adr, SIZE(LONGINT)); (* parm *)
          Move(fp, ap);
        ELSIF deref THEN (* ap := p^; address p^ & dynamic TD from heap *)
          TakeAddress(ap, CGL.RegWord, TRUE);
          ap.mode := CGL.Iregi;
          tp := ap;
          CGL.DoubleRef(tp);
          DEC(tp.offset, SIZE(LONGINT));
          Move(fp, tp);
          CGL.Release(tp); (* td *)
          ap.mode := CGL.Ireg;
          Move(fp, ap); (* address of heap block *)
          CGL.Release(ap);
        ELSE (* ap := static variable *)
          MakeVar(tp, ST.GetTD(ap.type), ST.linttyp);
          TakeAddress(tp, {}, FALSE);
	  Move(fp, tp); (* move [tos], td *)
          CGL.Release(tp);
          TakeAddress(ap, CGL.RegWord, ap.mnolev > 0);
          Move(fp, ap);
          CGL.Release(ap); (* parm *)
        END;
	bytes := 2 * SIZE(LONGINT);
      END VarParRecord;

      PROCEDURE VarParOther(fp : ST.Symbol; VAR ap : CGL.Item);
        VAR stk : CGL.Item;
      BEGIN
        CGL.InitItem(stk);
        stk.mode := Itos;
        stk.type := ST.linttyp;
        IF (fp.type  = ST.sysptrtyp) & (ap.type # ST.sysptrtyp) THEN
          (* assume pointer to <something>; use static TD *)
          MakeVar(ap, ST.GetTD(ap.type(ST.Pointer).to), ST.linttyp);
	  TakeAddress(ap, {}, FALSE); (* ap.mnolev := -to.mnolev: 97.07.21 *)
          Move(stk, ap);
        ELSE
          IF ap.mode IN {CGL.Ivarpar} THEN
            ap.mode := CGL.Ivar;
            ap.type := ST.linttyp;
          ELSE
            TakeAddress(ap, CGL.RegWord, FALSE);
          END;
          Move(stk, ap);
          CGL.Release(ap);
        END;
	bytes := SIZE(LONGINT);
      END VarParOther;

  BEGIN
    IF fp.kind = ST.varpar THEN
      CASE fp.type.form OF
      |  ST.dynarr:
         VarParDynarr(fp, ap);

      |  ST.record:
         VarParRecord(fp, ap, deref);

      ELSE
        VarParOther(fp, ap);
      END;
    ELSE
      stk      := ap;
      stk.mode := Itos;
      stk.type := fp.type;
      Assign(stk, ap);
      CGL.Release(ap);
      CASE fp.type.form OF
      | ST.array, ST.record:
        bytes := SIZE(LONGINT); (* always passed by reference; see Assign *)
      ELSE
        bytes := SHORT(fp.type.size);
      END;
      INC(bytes, (-bytes) MOD SIZE(LONGINT)); (* round to multiple of atomic stack unit *)
    END;
    RETURN bytes; (* returns number of bytes copied to the stack *)
  END Param;

  PROCEDURE LoadVMT*(VAR self, proc : CGL.Item; deref : BOOLEAN);
    (* super <=> CGL.super IN proc.flags *)
    VAR r, tag : CGL.Item; type : ST.Type;
  BEGIN
    tag := self;
    CGL.DoubleRef(self);
    type := tag.type;
    IF CGL.super IN proc.flags THEN
      IF tag.type.form = ST.pointer THEN
        type := type(ST.Pointer).to;
      END;
      MakeVar(r, ST.GetTD(type(ST.Record).ancestor), ST.linttyp);
      TakeAddress(r, CGL.RegWord, TRUE);
      proc.td.reg := r.reg;
      proc.td.mode := CGL.Iregi;
      RETURN;
    ELSIF self.type.form = ST.pointer THEN (*  bound to pointer type *)
      Deref(tag);
      DEC(tag.offset, 4);
    ELSIF deref THEN
      DEC(tag.offset, 4);
    ELSIF tag.mode = CGL.Ivarpar THEN
      tag.mode := CGL.Ivar;
      INC(tag.adr, 4);
    ELSE
      MakeVar(r, ST.GetTD(type), ST.linttyp);
      TakeAddress(r, CGL.RegWord, TRUE); (* r.mnolev := -tag.type.mno; : 97.07.21 *)
      proc.td.reg := r.reg;
      proc.td.mode := CGL.Iregi;
      RETURN;
    END;
    CGL.InitItem(r);
    CGL.GetReg(r, CGL.RegWord);
    r.type := ST.linttyp;
    tag.type := ST.linttyp;
    Move(r, tag);
    proc.td.reg := r.reg;
    proc.td.mode := CGL.Iregi;
  END LoadVMT;


  PROCEDURE Enter*(proc : ST.SymbolProc);
    VAR
      size : CGL.Item;
      sym : ST.Symbol;
      f : SHORTINT;
      varsize : LONGINT;


    PROCEDURE CopyDynArr(sym : ST.Symbol);
      VAR
        x, ptr, size, round : CGL.Item;
        temp : CGL.Item;
        zero : CGL.Item;
        one  : CGL.Item;
        elem : CGL.Item;
        four : CGL.Item;
        parm : CGL.Item;
        sp   : CGL.Item;
        loopCond : CGL.Item;
        loop : CGL.Label;
        r    : LONGINT;

      PROCEDURE DynArrSize(type : ST.Type; VAR size : CGL.Item; VAR round : LONGINT);
        VAR
          len : CGL.Item;
      BEGIN
        IF type.form = ST.dynarr THEN

          CGL.InitItem(len);
          DynArrSize(type(ST.Array).of, size, round);
          parm.type := type;
          GetArrayDimLen(parm, len, type(ST.Array));
          Load(len);

          IF (size.mode # CGL.Iconst) OR (size.val.i0 # 1) THEN
            IF (round = 4) & (size.mode = CGL.Ireg) THEN
              Load(size);
              CGL.PutGenReg(CGL.opcADD, size, one, size);  (* add Rsize, Rone, Rsize *)
            END;
            CGL.PutGenReg(CGL.opcADD, len, one, len);      (* add Rlen, Rone, Rlen *)
            round := 3; (* 3 <=> array bound + 3, 1 already added *)
            Mul(len, size);
          ELSE
            round := 4; (* 4 <=> array bound + 1 + 3 *)
          END;
          size := len;
        ELSE
          MakeConstItem(size, type.size, ST.linttyp);
        END;
      END DynArrSize;

    BEGIN
      CGL.InitItem(ptr);
      CGL.InitItem(size);
      TemporaryReg(four, ST.linttyp);               (* SIZE(LONGINT) *)
      MakeConstItem(zero, 0, ST.linttyp);
      MakeConstItem(one, 1, ST.linttyp);
      MakeConstItem(four, 4, ST.linttyp);
      Load(zero);
      Load(one);

      TemporaryReg(loopCond, ST.linttyp);

      size.mode := CGL.Ivar;
      r := 3;
      CGL.InitItem(parm);
      parm.mode := CGL.Ivar;
      parm.sym := sym;
      parm.mnolev := sym.mnolev;
      DynArrSize(sym.type, size, r);

      MakeConstItem(round, r, ST.linttyp);
      Load(round);
      Load(four);
      CGL.PutGenReg(CGL.opcADD, size, round, size); (* add Rsize, Rround, Rsize *)
      CGL.PutGenReg(CGL.opcDIV, size, four, size);   (* div Rsize, Rfour, Rsize *)

      ptr.mode   := CGL.Ivar;
      ptr.adr    := 0;
      ptr.offset := 0;
      ptr.mnolev := sym.mnolev;
      ptr.sym    := sym;
      ptr.type   := ST.linttyp;
      Load(ptr);

      ptr.mode   := CGL.Iregix;
      ptr.adr    := 0;
      ptr.offset := -SIZE(LONGINT);
      ptr.inxreg := size.reg;
      ptr.mnolev := 0; (* ptr holds address of the array data *)
      CGL.DoubleRef(size);

      loop := CGL.NewLabel();
      CGL.SetLabel(loop);
      TemporaryReg(elem, ST.linttyp);
      CGL.PutLoad(elem, ptr);
      CGL.PutStack(CGL.opcPUSH, elem); (* PUSH dword [ptr - SIZE(LONGINT) + (4*R0)];
                                        * -SIZE(LONGINT) is to offset the index
                                        * register, which holds number of words
                                        * to copy. *)
      CGL.PutGenReg(CGL.opcSUB, size, one, size);
      CGL.PutCompare(size, zero, loopCond);
      SetCC(loopCond, CGL.ccNE);
      CGL.PutJump(CGL.ccNE, loopCond, loop);


      x.mode   := CGL.Ivar;
      x.adr    := 0;
      x.offset := 0;
      x.mnolev := sym.mnolev;
      x.sym    := sym;
      x.type   := ST.linttyp;

      CGL.InitItem(sp);
      sp.mode := CGL.Ireg;
      sp.reg  := CGL.SP;
      sp.type := ST.linttyp;
      Move(x, sp);
      CGL.Release(size);
      CGL.Release(ptr);
    END CopyDynArr;

    PROCEDURE CopyParmToStack(sym : ST.Symbol);
      VAR dest, source : CGL.Item; s : LONGINT; type : ST.Type;
    BEGIN
      (* Copies 'sym' to the stack, and provides the on-stack
       * address as the procedure parameter.  This results in a
       * stack-based local copy of the non-VAR argument, but
       * treats it as a VAR argument for compiler simplicity.
       *)
      type := sym.type;
      s    := type.size;
      AdjustSP(((s + 3) DIV 4) * 4); (* Make space for the local copy. *)

      CGL.InitItem(dest);
      CGL.InitItem(source);
      dest.mode   := CGL.Iregi;
      dest.type   := ST.bytetyp;
      dest.reg    := CGL.SP;
      dest.adr    := 0;
      dest.offset := 0;
      dest.offset := 0;

      source.mode   := CGL.Ivarpar;
      source.sym    := sym;
      source.mnolev := sym.mnolev;
      source.adr    := 0;
      source.offset := 0;
      source.reg    := 0;

      MoveMemMemBlock(dest, source, s); (* move source array to stack *)

      source.mode := CGL.Ireg;
      source.type := ST.linttyp;
      source.reg  := CGL.SP;

      dest.mode   := CGL.Ivar;
      dest.type   := ST.linttyp;
      dest.sym    := sym;
      dest.mnolev := sym.mnolev;
      dest.adr    := 0;
      dest.offset := 0;
      Move(dest, source); (* Redirect argument to stack-based ocpy *)
    END CopyParmToStack;

  BEGIN
    ASSERT(proc # NIL);
    proc.adr := CGL.pc;
    IF ST.IsModule(proc) THEN
      CGL.PutOpenStackFrame(0, CGL.SFP);
    ELSE
      IF proc.kind IN { ST.lproc, ST.cproc,
                        ST.tproc, ST.xproc, ST.iproc} THEN
        varsize := proc.varsize;
        ASSERT(varsize MOD SIZE(LONGINT) = 0);
        CGL.PutOpenStackFrame(SHORT(varsize DIV SIZE(LONGINT)), CGL.SFP);
        sym := ST.FirstParm(proc.type(ST.Procedure));
        WHILE sym # NIL DO
          IF sym.kind = ST.par THEN
            f := sym.type.form;
            IF f = ST.dynarr THEN
              CopyDynArr(sym);
            ELSIF f IN PassedByAddress THEN
              CopyParmToStack(sym);
            (* ELSE nop *)
            END;
          (* ELSE nop *)
          END;
          sym := ST.NextParm(sym);
        END;
      END;
    END;
  END Enter;

  PROCEDURE Leave*(proc : ST.SymbolProc);
    VAR dsize : CGL.Item; parsize : LONGINT;

  BEGIN
    ASSERT(proc # NIL, 148);
    IF ST.IsModule(proc) THEN
      CGL.PutCloseStackFrame(0, CGL.SFP);
      CGL.PutReturn(FALSE);
    ELSE
      parsize := proc.parsize;
      ASSERT(parsize MOD SIZE(LONGINT) = 0);
      CASE proc.kind OF
      |  ST.lproc, ST.cproc:
         IF proc.mnolev > 0 THEN
           ASSERT(proc.kind # ST.cproc);
           INC(parsize, SIZE(LONGINT));
         END; (* remove static link when present *)
         (* 'parsize': number of bytes parameters occupy on the stack. *)
         CGL.PutCloseStackFrame(SHORT(parsize DIV SIZE(LONGINT)), CGL.SFP);
         CGL.PutReturn(FALSE);

      |  ST.xproc, ST.tproc:
         CGL.PutCloseStackFrame(SHORT(parsize DIV SIZE(LONGINT)), CGL.SFP);
         CGL.PutReturn(FALSE);

      |  ST.iproc:
         ASSERT(parsize = 0); (* cannot have parms, or we have to pop them
                               * at the point of the call *)
         CGL.PutReturn(TRUE);
      END;
    END;
  END Leave;

  PROCEDURE Return*(proc : ST.Symbol; VAR x : CGL.Item);
  BEGIN
    IF proc.type(ST.Procedure).result.form IN ST.RealSet THEN
      IF (x.mode # CGL.Ireg) OR (x.reg # 1) THEN
        LoadInto(x, {1});       (* Return values are in F1 *)
      END;
    ELSE
      ASSERT(x.type.size <= proc.type.size);
      IF (x.mode # CGL.Ireg) OR (x.reg # 1) THEN
        LoadInto(x, {1});       (* Return values are in R1 *)
      END;
    END;
  END Return;

  (* CRemoveParms: removes parameters from stack for a cdecl-style procedure
     pre: (bytes >= 0) & (bytes MOD 4) = 0
     pre: bytes <-> number of bytes of parameters pushed on to stack
  *)
  (* TODO: This function, and the sysflag for C funcs is unneeded *)
  PROCEDURE CRemoveParms*(bytes : INTEGER);
    VAR
      b, sp : CGL.Item;
  BEGIN
    IF bytes > 0 THEN
      sp.mode := CGL.Ireg;
      sp.type := ST.linttyp;
      sp.reg  := CGL.SP;
      MakeConstItem(b, bytes, ST.linttyp);
      Load(b);
      CGL.PutGenReg(CGL.opcADD, sp, b, sp);
    END;
  END CRemoveParms;

  (* x.type = ST.proc; all relevant info can be found from this type *)
  PROCEDURE Call*(VAR x : CGL.Item; proc : ST.SymbolProc);
    VAR
      i, n : INTEGER;
      Rx, base, R0 : CGL.Item;
      code : ST.ConstExt;
  BEGIN
    ASSERT(x.type.form = ST.procedure, 128);
    CGL.InitItem(Rx);
    CGL.InitItem(base);
    CASE x.mode OF
    |  CGL.Ilproc:
       base.mode   := CGL.Iregi;
       base.reg    := CGL.SFP;
       base.offset := 0;
       base.type   := ST.linttyp;
       base.mnolev := 1;

       IF x.mnolev > 0 THEN
         n := CGL.level - x.mnolev;
         (* note that the static base must also be removed from the stack.
          * This can either be done by the caller or by the callee.
          * This compiler has the callee remove
          * the static link as part of its parameter popping mechanism
          *)
         IF n = 0 THEN
           TemporaryReg(Rx, ST.linttyp);
           CGL.PutLoadAddress(Rx, base);
           CGL.PutStack(CGL.opcPUSH, Rx); (* push address of stack base *)
           CGL.Release(Rx);
         ELSIF n = 1 THEN
           base.mode   := CGL.Iregi;
           base.reg    := CGL.SFP;
           base.offset := 2 * SIZE(LONGINT);
           base.mnolev := x.mnolev;
           base.type   := ST.linttyp;
           Load(base);
           CGL.PutStack(CGL.opcPUSH, base); (* push static base *)
         ELSE (* Call from nested function to enclosing function. *)
           CGL.GetReg(Rx, CGL.RegWord);
           Rx.type     := ST.linttyp;
           Rx.offset   := 0;
           Rx.mnolev   := CGL.level;

           base.mode   := CGL.Iregi;
           base.reg    := CGL.SFP;
           base.offset := 8;
           base.mnolev := x.mnolev;
           base.type   := ST.linttyp;
           LoadZero(R0);

           Move(Rx, base);
           base.reg := Rx.reg;
           WHILE n > 1 DO  (* Follow the dynamic frames, loading each. *)
             Move(Rx, base);
             DEC(n);
           END;
           CGL.PutStack(CGL.opcPUSH, Rx); (* push static base *)
           CGL.Release(Rx);
         END;
       END;
       CGL.PutJAL(x);

    |  CGL.Ixproc:
       CGL.PutJAL(x);

    |  CGL.Icproc:
       (* Code procedure: Insert code directly *)
       code := proc(ST.SymbolCodeProc).code;
       i := ORD(code[0]); (* Number of bytes in code procedure *)
       n := 1;
       WHILE i > 0 DO
         CGL.PutByte(code[n]);
         INC(n);
         DEC(i);
       END;

    |  CGL.Imethod:
       ASSERT(x.td.mode = CGL.Iregi);
       Rx.mode   := CGL.Iregi;
       Rx.type   := ST.linttyp;
       Rx.reg    := x.td.reg;
       Rx.offset := CGL.TBPOffset  - 4 * x.methno;
       Load(Rx);
       CGL.PutJRAL(Rx); (* jral Rx, R31 *)
    ELSE (* procedure variable *)
      Rx := x;
      Load(Rx);
      CGL.PutJRAL(Rx);
      CGL.Release(Rx);
    END;
  END Call;

  PROCEDURE Case*(VAR x : CGL.Item; low, high : LONGINT; VAR CaseTab, else : CGL.Label);
    VAR
      y  : CGL.Item;
      Rt : CGL.Item;
  BEGIN
    TemporaryReg(Rt, ST.linttyp);
    else := NIL;
    Widen(x, ST.linttyp);
    Load(x);
    MakeConstItem(y, low, ST.linttyp);
    IF ~CGL.IsConstZero(y) THEN
      (* If the base CASE element is zero, no subtraction needed. *)
      Load(y);
      CGL.PutGenReg(CGL.opcSUB, x, y, x); (* sub Rx, low, Rx *)
    END;

    MakeConstItem(y, high - low + 1, ST.linttyp);
    Load(y);
    CGL.PutCompare(x, y, Rt);
    SetCC(Rt, CGL.ccGEU);
    CGL.PutJump(CGL.ccGEU, Rt, else);(* Out-of-bounds => ELSE *)

    CaseTab := CGL.NewCaseTable(low, high);
    CGL.CaseJump(x, CaseTab);
    CGL.SetLabel(else);
  END Case;

  PROCEDURE Finalize*(VAR type, proc : CGL.Item);
  BEGIN
    (* Assign Finalize slot in a record type descriptor.
     *
     *  proc: PROCEDURE to assign as finalizer.
     *  type: TD of RECORD type.
     *)
    type.adr  := OPM.RecFinalize;
    type.type := ST.linttyp;

    Load(type);
    type.mode   := CGL.Iregi;
    type.offset := 0;

    TakeAddress(proc, {}, FALSE);
    Load(proc);
    StoreMem(type, proc);
  END Finalize;


  PROCEDURE StdGetPutReg*(VAR reg, val : CGL.Item; get : BOOLEAN);
    VAR Rx : CGL.Item;
  BEGIN
    CGL.InitItem(Rx);
    Rx.mode := CGL.Ireg;
    Rx.reg  := reg.val.i0;
    Rx.type := val.type;
    IF get THEN
      Move(val, Rx);
    ELSE
      Move(Rx, val);
    END;
  END StdGetPutReg;

  PROCEDURE StdGetPut*(VAR addr, val : CGL.Item; get : BOOLEAN);
    VAR Rx : CGL.Item;
  BEGIN
    CGL.InitItem(Rx);
    CGL.GetReg(Rx, CGL.RegWord);
    Rx.type := addr.type;
    Move(Rx, addr);
    Rx.mode := CGL.Iregi;
    Rx.offset := 0;
    Rx.type := val.type;
    IF get THEN
      Load(Rx);
      Move(val, Rx);
    ELSE
      Move(Rx, val);
    END;
    CGL.Release(Rx);
  END StdGetPut;

  PROCEDURE StdHalt*(VAR val : CGL.Item);
  BEGIN
    Trap(val.val.i0);
  END StdHalt;

  PROCEDURE StdAssert*(VAR expr, val: CGL.Item);
    VAR pass : CGL.Label;
  BEGIN
    IF (expr.mode # CGL.Iconst) OR (expr.val.i0 # OPM.TrueVal) THEN
      IF expr.mode = CGL.Iconst THEN
        Trap(val.val.i0);
      ELSE
        pass := NIL;
        JmpT(expr, pass);
        Trap(val.val.i0);
        CGL.SetLabel(pass);
      END;
    END;
  END StdAssert;

  PROCEDURE StdNew*(VAR x : CGL.Item); (* new record *)
    VAR td : CGL.Item; tdSym : ST.Symbol;
  BEGIN
    MakeVar(td, ST.GetTD(x.type), ST.linttyp);
    TakeAddress(x, {1}, TRUE);
    TakeAddress(td, {2}, TRUE);
    CGL.CallCompilerHelper("Kernel", "NewRecord");  (* R1 = address of pointer,
                                                     * R2 = type descriptor *)
    CGL.Release(x);
    CGL.Release(td);
  END StdNew;

  PROCEDURE PushDynArrDim*(VAR nElem, elemSize : CGL.Item; type : ST.Type);
  BEGIN
    Widen(nElem, ST.linttyp);
    IF nElem.mode # CGL.Iconst THEN
      CheckRange(nElem, OPM.MinLInt, OPM.MaxLInt);
    END;
    Load(nElem);
    CGL.PutStack(CGL.opcPUSH, nElem);
  END PushDynArrDim;

  PROCEDURE StdNewStaticArray*(VAR x : CGL.Item); (* new static array *)
    VAR td : CGL.Item;
  BEGIN
    ASSERT(x.type.form = ST.pointer);
    MakeVar(td, ST.GetTD(x.type), ST.linttyp); (* GetTD sees through pointer *)
    TakeAddress(x, {1}, TRUE);
    TakeAddress(td, {2}, TRUE);
    CGL.CallCompilerHelper("Kernel", "NewStaticArray");  (* R1 = address of pointer,
                                                          * R2 = type descriptor *)
    CGL.Release(x);
    CGL.Release(td);
  END StdNewStaticArray;

  PROCEDURE StdNewDynArray*(VAR x, y : CGL.Item);
    VAR
      td, sp, r0, r1 : CGL.Item;
  BEGIN
    MakeVar(td, ST.GetTD(x.type), ST.linttyp);
    TakeAddress(x, {1}, TRUE);
    TakeAddress(td, {2}, TRUE);
    CGL.CallCompilerHelper("Kernel", "NewDynArray");  (* R1 = address of pointer,
                                                       * R2 = type descriptor *)
    (* All requested dimensions pushed on stack.
     * They are removed by Kernel.NewDynArray.
     *)

    CGL.Release(x);
    CGL.Release(y);
    CGL.Release(td);
  END StdNewDynArray;

  PROCEDURE StdSysNew*(VAR addr, size : CGL.Item);
  BEGIN
    Widen(size, ST.linttyp);
    TakeAddress(addr, {1}, TRUE);
    LoadItem2(size, {2}, addr);
    CGL.CallCompilerHelper("Kernel", "NewBlock"); (* R1 = address,
                                                   * R2 = size in bytes *)
    CGL.Release(addr);
    CGL.Release(size);
  END StdSysNew;

  PROCEDURE StdMemRW*(VAR base, index, var : CGL.Item; read : BOOLEAN);
  BEGIN
    Load(base); base.mode := CGL.Iregi;
    IF index.mode = CGL.Iconst THEN
      base.offset := index.val.i0;
    ELSE
      Load(index);
      CGL.DoubleRef(index);
      base.mode := CGL.Iregix;
      base.inxreg := index.reg;
      base.offset := 0;
      CGL.Release(index);
    END;
    base.type := var.type;
    IF read THEN
      Load(base);
      Move(var, base);
    ELSE
      Load(var);
      Move(base, var);
    END;
    CGL.Release(base);
    CGL.Release(var);
  END StdMemRW;

  PROCEDURE StdSysMove*(VAR source, dest, len : CGL.Item);
  BEGIN
    (* Registers are force-loaded via SKLTH.StdMove *)
    ASSERT((source.mode = CGL.Ireg) & (source.reg = 1), 1055);
    ASSERT((dest.mode   = CGL.Ireg) & (dest.reg   = 2), 1056);
    ASSERT((len.mode    = CGL.Ireg) & (len.reg    = 3), 1057);

    CGL.CallCompilerHelper("Kernel", "StdSysMove"); (* R1 = source;
                                                     * R2 = dest;
                                                     * R3 = LEN(dest) *)
  END StdSysMove;

  PROCEDURE StdIncDec*(VAR var, val : CGL.Item; inc : BOOLEAN);
  BEGIN
    (* This function is not used.  The INC and DEC standard procedures
     * are always turned into { T.Eplus, T.Eminus } nodes in SKLSTP.IncDec().
     *)
    OPM.NotReached("CGH.StdIncDec");
  END StdIncDec;

  PROCEDURE StdInclExcl*(VAR set, bit : CGL.Item; incl : BOOLEAN);
    VAR
      temp : CGL.Item;
  BEGIN
    temp := set;
    CGL.DoubleRef(set);
    SetElem(bit);
    Load(temp);
    Load(bit);
    IF incl THEN
      CGL.PutIntReg(CGL.opcOR, temp, bit, temp);   (* OR Rtemp, Rbit, Rtemp *)
    ELSE
      bit.type := ST.settyp;
      Negate(bit);
      CGL.PutIntReg(CGL.opcAND, temp, bit, temp);   (* AND Rtemp, Rbit, Rtemp *)
    END;
    TakeAddress(set, CGL.RegWord, FALSE);
    ASSERT(set.mode IN {CGL.Ireg, CGL.Iadr});
    IF set.mode = CGL.Ireg THEN
      set.mode   := CGL.Iregi;
      set.offset := 0;
    END;

    StoreMem(set, temp);
    CGL.Release(temp);
    CGL.Release(set);
    CGL.Release(bit);
  END StdInclExcl;

  PROCEDURE StdCopy*(VAR source, dest : CGL.Item);
    VAR
      len, cnt: CGL.Item;
      lab : CGL.Label;
  BEGIN
    IF source.type = ST.chartyp THEN (* copy character variable/constant to array *)
      TakeAddress(dest, CGL.RegWord, TRUE);
      dest.mode := CGL.Iregi;
      dest.offset := 0;
      dest.type := ST.chartyp;
      IF source.mode # CGL.Iconst THEN
        Load(source);
      END;

      Move(dest, source);
      dest.offset := 1;
      MakeConstItem(cnt, 0, ST.chartyp);
      Move(dest, cnt);
    ELSE (* copy string to array *)
      GetArrayDimLen(dest, cnt, dest.type(ST.Array));
      TakeAddress(source, {1}, TRUE);
      TakeAddress(dest, {2}, TRUE);
      CGL.InitItem(len);
      CGL.GetReg(len, {3});
      len.type := ST.linttyp;
      Move(len, cnt);
      CGL.CallCompilerHelper("Kernel", "Copy"); (* R1 = source;
                                                 * R2 = dest;
                                                 * R3 = LEN(dest) *)
    END;
  END StdCopy;

  PROCEDURE NegTest(VAR x : CGL.Item; VAR Rd : CGL.Item);
    VAR
      sign : CGL.Item;
  BEGIN
    ASSERT((x.mode = CGL.Ireg) & (x.type.size IN {1, 2, 4}));
    MakeConstItem(sign, 31, x.type);
    CGL.PutBitTest(sign, x, Rd); (* inv: Rd IN {0,1} *)
    SetCC(Rd, CGL.ccEQ); (* Bit 0 (Zero Flag) in Rd is set? *)
  END NegTest;

  PROCEDURE StdAbs*(VAR x : CGL.Item);
    VAR
      Rd   : CGL.Item;
  BEGIN
    IF x.type.form IN ST.IntSet THEN
      Load(x);
      Rd := x;
      CGL.DoubleRef(Rd);
      CGL.PutAbs(x, Rd);
      CGL.Release(Rd);
    ELSE
      Load(x);
      Rd := x;
      CGL.DoubleRef(Rd);
      CGL.PutAbs(x, Rd);
      CGL.Release(Rd);
    END;
  END StdAbs;

  PROCEDURE StdCap*(VAR x : CGL.Item);
    VAR y, Rt : CGL.Item;
  BEGIN
    MakeConstItem(y, 5FH, ST.chartyp);
    Load(x);
    Load(y);
    TemporaryReg(Rt, x.type);
    CGL.PutIntReg(CGL.opcAND, x, y, Rt);
    CGL.Release(x);
    CGL.Release(y);
    x := Rt;
  END StdCap;

  PROCEDURE StdOdd*(VAR x : CGL.Item);
    VAR
      bit : CGL.Item;
  BEGIN
    LoadZero(bit);
    Load(x);
    CGL.DoubleRef(x);
    CGL.PutBitTest(bit, x, x);
    CGL.Release(x);
    x.type := ST.booltyp;
    SetCC(x, CGL.ccEQ); (* Bit 0 set --> TRUE (ZF set) *)
  END StdOdd;

  PROCEDURE Shift(VAR var, bits : CGL.Item; opc : SHORTINT);
  BEGIN
    ASSERT(opc IN {CGL.opcASH, CGL.opcLSH, CGL.opcROT});
    Load(bits);
    Load(var);
    CGL.PutIntReg(opc, var, bits, var);
    CGL.Release(bits);
  END Shift;

  PROCEDURE Lsh*(VAR x, y : CGL.Item);
  BEGIN
    ASSERT(y.mode = CGL.Iconst);
    Shift(x, y, CGL.opcLSH);
  END Lsh;

  PROCEDURE Rot*(VAR x, y : CGL.Item);
  BEGIN
    ASSERT(y.mode = CGL.Iconst);
    Shift(x, y, CGL.opcROT);
  END Rot;

  PROCEDURE Ash*(VAR x, y : CGL.Item);
  BEGIN
    ASSERT((y.mode = CGL.Iconst));
    Shift(x, y, CGL.opcASH);
  END Ash;

  PROCEDURE StdAsh*(VAR var, bits : CGL.Item);
  BEGIN
    Widen(var, ST.linttyp);
    Load(var);
    Shift(var, bits, CGL.opcASH);
  END StdAsh;

  PROCEDURE StdLsh*(VAR var, bits : CGL.Item);
  BEGIN
    Widen(var, ST.linttyp);
    Load(var);
    Shift(var, bits, CGL.opcLSH);
  END StdLsh;

  PROCEDURE StdRot*(VAR var, bits : CGL.Item);
  BEGIN
    Widen(var, ST.linttyp);
    Load(var);
    Shift(var, bits, CGL.opcROT);
  END StdRot;

  PROCEDURE StdLen*(VAR arr, dim : CGL.Item);
    VAR
      i : LONGINT;
      t : ST.Array;
      y : CGL.Item;
      one : CGL.Item;
  BEGIN
    ASSERT(dim.mode = CGL.Iconst, 215);
    ASSERT(arr.type.form = ST.dynarr, 216);
    t := arr.type(ST.Array);
    i := dim.val.i0;
    WHILE i > 0 DO
      t := t.of(ST.Array);
      DEC(i);
    END;
    MakeConstItem(one, 1, ST.linttyp);
    GetArrayDimLen(arr, y, t);
    Load(y);
    CGL.Release(arr);
    arr := y;
    CGL.PutAddConstant(arr, one, arr);
  END StdLen;

  (* StdBit:
   *
   *  Generates a 32-bit value of the specified bit in 32-bits of memory.
   *
   *)
  PROCEDURE StdBit*(procno : SHORTINT; VAR mem, bit : CGL.Item); (* SYSTEM.BIT(mem32, [0..31]) *)
    VAR
      opc : SHORTINT;
  BEGIN
    opc := CGL.opcBTM;
    IF bit.mode # CGL.Iconst THEN
      Load(bit);
    ELSE
      (* Constant value:
       *  inv: 'bit' is in SET range.
       *  opcBTM -> opcBTMI
       *)
      INC(opc);
    END;
    Load(mem);
    CGL.PutBitTestMemory(opc, bit, mem, mem);
    SetCC(mem, CGL.ccEQ);
  END StdBit;

  PROCEDURE StdBitSetReset*(set : BOOLEAN; VAR addr, bit : CGL.Item);
    VAR
      opc : SHORTINT;
  BEGIN
    IF set THEN
      opc := CGL.opcBTMS;       (* Set bit. *)
    ELSE
      opc := CGL.opcBTMC;       (* Clear bit. *)
    END;

    IF bit.mode # CGL.Iconst THEN
      Load(bit);
    ELSE
      INC(opc);           (* Constant value:
                           *   opcBTMS -> opcBTMSI
                           *   opcBTMC -> opcBTMCI
                           *)
    END;
    Load(addr);
    CGL.PutBitTestMemory(opc, bit, addr, addr);
  END StdBitSetReset;

  PROCEDURE InitTypeDescriptor*(tdNum : LONGINT; td : ST.SymbolTypeDesc);
    VAR tf : SHORTINT; type : ST.Type;

      PROCEDURE GenFlags(kind : LONGINT) : LONGINT;
        VAR
          flagsAddr : LONGINT;
          tdescFixup : CGL.Fixup;
          tdescLabel : CGL.Label;
      BEGIN
        flagsAddr := CGL.TDGenDWord(OPM.DescFlagsValidBit + kind);
        (* fixup in TDesc segment which points to beginning of actual descriptor *)
        tdescLabel := CGL.NewLabel();
        CGL.DefineLabel(tdescLabel, CGL.segTypeDesc, flagsAddr);

        (* tdNum <=> index into TDesc segment; loader multiplies by entry size *)
        tdescFixup := CGL.NewFixup(CGL.FixAbs, CGL.segTDesc, tdNum);
        CGL.SetFixupLab(tdescFixup, tdescLabel);
        RETURN flagsAddr;
      END GenFlags;

      PROCEDURE RecordTD(type : ST.Type);
        VAR
          t0 : LONGINT;
          i : LONGINT;
          nameFixup, blksizeFixup, exttabFixup : CGL.Fixup;
          exttabLab, nameLab : CGL.Label;
          ptrTab : ARRAY OPM.RecMaxPtrs OF LONGINT;
          nofPtr : INTEGER;
          meth : ST.Symbol;

        PROCEDURE GenAncestorTable(rec : ST.Record);
          VAR t0 : LONGINT;
        BEGIN
          IF rec # NIL THEN
            GenAncestorTable(rec.ancestor);
            ST.UseTD(rec);
            t0 := CGL.TDGenSym(ST.GetTD(rec));
            IF exttabLab = NIL THEN
              exttabLab := CGL.NewLabel(); (* address of extension table *)
              CGL.DefineLabel(exttabLab, CGL.segTypeDesc, t0);
            END;
          END;
        END GenAncestorTable;

        PROCEDURE GenExtensionTable(rec : ST.Record);
          VAR i : LONGINT;
        BEGIN
          CGL.Align(CGL.segTypeDesc, 4);
          exttabLab := NIL;
          GenAncestorTable(rec);
        END GenExtensionTable;

      BEGIN
        nameLab := CGL.NewLabel();
        nofPtr := 0;
        CGL.FindPtrs(type, 0, ptrTab, nofPtr);
        IF type.sym # NIL THEN
          t0 := CGL.TDGenString(type.sym.name^);
        ELSE
          t0 := CGL.TDGenString('');
        END;

        CGL.DefineLabel(nameLab, CGL.segTypeDesc, t0); (* a label at the name of the type *)
        GenExtensionTable(type(ST.Record));

        i := type(ST.Record).nofmeth;
        CGL.TDAlign(td.adr, i);
        WHILE i >= 1 DO (* method table *)
          DEC(i);
          meth := ST.FindMethodByNumber(type(ST.Record), i);
          INCL(meth.flags, ST.used);
          t0 := CGL.TDGenSym(meth);
        END;

        t0 := GenFlags(OPM.DescFlagsRecord); (* start of type descriptor *)
        t0 := CGL.TDGenDWord(0);  (* pointer to extension table *)
        exttabFixup := CGL.NewFixup(CGL.FixAbs, CGL.segTypeDesc, t0);
        CGL.SetFixupLab(exttabFixup , exttabLab); (* extension table *)

        t0 := CGL.TDGenDWord(type(ST.Record).extlev);
        t0 := CGL.TDGenDWord(type.size);
        (* allocation block size: 97.07.11: deprecated field. do not use value *)


        t0 := CGL.TDGenDWord(0);
        blksizeFixup := CGL.NewRecordSizeFixup(t0, type.size);

        t0 := CGL.TDGenDWord(nofPtr);
        t0 := CGL.TDGenDWord(0);  (* pointer to type name *)
        nameFixup := CGL.NewFixup(CGL.FixAbs, CGL.segTypeDesc, t0);
        CGL.SetFixupLab(nameFixup, nameLab); (* type name *)
        t0 := CGL.TDGenDWord(0); (* module descriptor pointer; managed by loader module *)
        t0 := CGL.TDGenDWord(0); (* finalization procedure; 97.05.18: not implemented yet *)
        i := 0;
        WHILE i < nofPtr DO
          t0 := CGL.TDGenDWord(ptrTab[i]);
          INC(i);
        END;
        (* n + 1th pointer offset should be negative; see Project Oberon on GC *)
        t0 := CGL.TDGenDWord(-(OPM.RecPtrTab + SIZE(LONGINT) * nofPtr));
      END RecordTD;

      PROCEDURE DynArrTD(type : ST.Type); (* type <=>  type described by the descriptor *)
        VAR
          eltype, arrtype : ST.Type;
          tf : SHORTINT;
          nofDim, tdAdr, t0 : LONGINT;
      BEGIN
        eltype := type(ST.Array).of;
        WHILE eltype.form = ST.dynarr DO
          eltype := eltype(ST.Array).of;
        END;
        tf := eltype.form;
        CGL.TDAlign(td.adr, 0);

        IF tf IN SimpleElemSet THEN
          t0 := GenFlags(OPM.DescFlagsDynArray0);
          t0 := CGL.TDGenDWord(tf);  (* type form of element *)
          t0 := CGL.TDGenDWord(type(ST.Array).len + 1); (* nofDim *)
          t0 := CGL.TDGenDWord(eltype.size); (* element size *)
        ELSIF tf = ST.pointer THEN
          t0 := GenFlags(OPM.DescFlagsDynArray1);
          t0 := CGL.TDGenDWord(0);  (* reserved for GC *)
          t0 := CGL.TDGenDWord(type(ST.Array).len + 1); (* nofDim *)
          t0 := CGL.TDGenDWord(eltype.size); (* element size *)
        ELSIF tf = ST.record THEN
          t0 := GenFlags(OPM.DescFlagsDynArray2);
          t0 := CGL.TDGenSym(ST.GetTD(eltype)); (* address of record TD *)
          t0 := CGL.TDGenDWord(type(ST.Array).len + 1); (* nofDim *)
          t0 := CGL.TDGenDWord(eltype.size); (* element size *)
        ELSE
          ASSERT(tf = ST.array);
          arrtype := eltype;
          WHILE arrtype.form = ST.array DO
            arrtype := arrtype(ST.Array).of;
          END;
          IF arrtype.form IN SimpleElemSet THEN
            td.adr := GenFlags(OPM.DescFlagsDynArray3);
          ELSIF arrtype.form = ST.pointer THEN
            td.adr := GenFlags(OPM.DescFlagsDynArray4);
          ELSE
            ASSERT(arrtype.form = ST.record);
            td.adr := GenFlags(OPM.DescFlagsDynArray5);
          END;

          arrtype := eltype;
          WHILE arrtype.form = ST.array DO
            arrtype := arrtype(ST.Array).of;
          END;
          tf := arrtype.form;

          IF tf IN SimpleElemSet THEN
            t0 := CGL.TDGenDWord(tf);
          ELSIF tf = ST.pointer THEN
            t0 := CGL.TDGenDWord(0); (* reserved for GC (q.cnt) *)
          ELSIF tf = ST.record THEN
            t0 := CGL.TDGenSym(ST.GetTD(arrtype)); (* type descriptor of final element (q.cnt) *)
          END;

          t0 := CGL.TDGenDWord(type(ST.Array).len + 1); (* nofDim (dynamic array) *)
          t0 := CGL.TDGenDWord(eltype.size); (* element size *)

          arrtype := eltype; nofDim := 0;
          WHILE arrtype.form = ST.array DO
            INC(nofDim);
            arrtype := arrtype(ST.Array).of;
          END;
          t0 := CGL.TDGenDWord(nofDim); (* number of static array dimensions *)

          arrtype := eltype;
          WHILE arrtype.form = ST.array DO
            t0 := CGL.TDGenDWord(arrtype(ST.Array).len); (* LEN(arr, nofDim) *)
            arrtype := arrtype(ST.Array).of;
          END;
        END;
      END DynArrTD;

      PROCEDURE ArrayTD(type : ST.Type);
        VAR t0, nofDim : LONGINT; tf : SHORTINT; elType : ST.Type;
      BEGIN
        elType := type(ST.Array).of;
        WHILE elType.form = ST.array DO
          elType := elType(ST.Array).of;
        END;
        CGL.TDAlign(td.adr, 0);
        tf := elType.form;
        IF tf IN SimpleElemSet THEN
          t0 := GenFlags(OPM.DescFlagsStatArr0);
        ELSIF tf = ST.pointer THEN
          t0 := GenFlags(OPM.DescFlagsStatArr1);
        ELSE
          ASSERT(tf = ST.record);
          t0 := GenFlags(OPM.DescFlagsStatArr2);
        END;

        elType := type(ST.Array).of;
        nofDim := 1;
        WHILE elType.form = ST.array DO
          INC(nofDim);
          elType := elType(ST.Array).of;
        END;

        tf := elType.form;
        IF tf IN SimpleElemSet THEN
          t0 := CGL.TDGenDWord(tf);
        ELSIF tf = ST.pointer THEN
          t0 := CGL.TDGenDWord(0); (* reserved *)
        ELSE
          t0 := CGL.TDGenSym(ST.GetTD(elType)); (* pointer to record TD  *)
        END;

        t0 := CGL.TDGenDWord(elType.size); (* element size in bytes *)
        t0 := CGL.TDGenDWord(nofDim); (* number of static array dimensions *)
        WHILE type.form = ST.array DO
          t0 := CGL.TDGenDWord(type(ST.Array).len);
          type := type(ST.Array).of;
        END;
      END ArrayTD;

  BEGIN
    type := td.described;
    tf := type.form;
    ASSERT(tf IN {ST.record, ST.dynarr, ST.array});
    IF tf = ST.record THEN
      RecordTD(type);
    ELSIF tf = ST.dynarr THEN
      DynArrTD(type);
    ELSE
      ArrayTD(type);
    END;
  END InitTypeDescriptor;

  PROCEDURE InitImportedUnit*(VAR x : CGL.Item);
  BEGIN
    ASSERT(x.mode = CGL.Ixproc);
    CGL.PutJAL(x);              (* JAL x *)
  END InitImportedUnit;


  PROCEDURE CollectPointers(VAR info : ST.ProcessScopeInfo);
  BEGIN
    IF info.sym.kind = ST.var THEN
      CGL.FindPtrs(info.sym.type, info.sym.adr,
                   info(CollectPointersInfo).tab^,
                   info(CollectPointersInfo).nofPointers);
    END;
  END CollectPointers;


  PROCEDURE InitPointersGlobal*(scope : ST.SymbolScope);
    VAR info : CollectPointersInfo;
        ptr, zero : CGL.Item;
  BEGIN
    CGL.InitItem(ptr);
    LoadZero(zero);
    info.nofPointers := 0;
    NEW(info.tab, OPM.MaxGlobalPointers);
    ST.ProcessScope(scope, CollectPointers, info);
    IF info.nofPointers > 0 THEN
      CGL.GetReg(ptr, CGL.RegWord);
      ptr.mode := CGL.Ireg;
      ptr.type := ST.linttyp;
      CGL.GetSegAddress(CGL.segData, ptr);
      ptr.mode := CGL.Iregi;

      WHILE info.nofPointers > 0 DO
        DEC(info.nofPointers);
        ptr.offset := info.tab[info.nofPointers];
        StoreMem(ptr, zero);
      END;
      CGL.Release(ptr);
    END;
  END InitPointersGlobal;

  PROCEDURE InitPointersLocal*(proc : ST.SymbolProc);
    CONST MaxLocalPointerInits = 15;
    VAR
      sp, fp, bytes, zero : CGL.Item;
      info : CollectPointersInfo;

    PROCEDURE BlockClear(bytes : LONGINT);
      VAR
        count : CGL.Item;
        ptr   : CGL.Item;
        fp    : CGL.Item;
    BEGIN
      CGL.InitItem(fp);
      fp.mode   := CGL.Iregi; (* Local Frame Pointer *)
      fp.type   := ST.linttyp;
      fp.mnolev := 0;
      fp.reg    := CGL.SFP;
      fp.offset := -bytes;

      TemporaryReg(ptr, ST.linttyp);
      MakeConstItem(count, bytes, ST.linttyp);
      LoadInto(count, {2});
      CGL.PutLoadAddress(ptr, fp);
      LoadInto(ptr, {1});
      CGL.CallCompilerHelper("Kernel", "InitMemory");
    END BlockClear;

  BEGIN
    LoadZero(zero);
    CGL.InitItem(sp);
    sp.mode   := CGL.Ireg;
    sp.type   := ST.linttyp;
    sp.mnolev := proc.mnolev;
    sp.reg    := CGL.SP;

    info.nofPointers := 0;
    NEW(info.tab, MaxLocalPointerInits);
    ST.ProcessScope(proc.scope, CollectPointers, info);
    IF info.nofPointers < MaxLocalPointerInits THEN
      CGL.InitItem(fp);
      fp.mode   := CGL.Iregi;
      fp.type   := ST.linttyp;
      fp.mnolev := proc.mnolev;
      fp.reg    := CGL.SFP;
      WHILE info.nofPointers > 0 DO
        DEC(info.nofPointers);
        fp.offset := info.tab[info.nofPointers];
        StoreMem(fp, zero);
      END;
    ELSE
      BlockClear(proc.varsize); (* Too many pointers, zero all local variable space. *)
    END;
  END InitPointersLocal;

  PROCEDURE ModuleBegin*;
  BEGIN
    (* True & False should only be used with BOOLEANs, and thus their type should be booltyp *)
    MakeConstItem(False, OPM.FalseVal, ST.booltyp);
    MakeConstItem(True, OPM.TrueVal, ST.booltyp);
    MakeConstItem(One, 1, ST.sinttyp); (* XXX remove?? *)
  END ModuleBegin;

  PROCEDURE ModuleEnd*;
  BEGIN ASSERT(False.type.form = ST.bool, 1075); ASSERT(True.type.form = ST.bool, 1076);
  END ModuleEnd;

END SKLCGH.
