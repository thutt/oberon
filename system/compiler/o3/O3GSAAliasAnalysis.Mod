MODULE O3GSAAliasAnalysis;
  IMPORT
    Console,
    Types,
    Config:=O3Config,
    Symtab:=O3Symtab,
    GSAData := O3GSAData,
    GSAOpcode := O3GSAOpcode;

  CONST (* Diagnostic output control *)
    dfProgress = 0;
    diagnostics = {};

  TYPE
    AliasKind = SHORTINT;

  TYPE
    NonLocalArray = POINTER TO ARRAY OF GSAData.Usable;

  TYPE
    Worklist = POINTER TO WorklistDesc;
    WorklistDesc = RECORD
      r       : GSAData.Region;
      alias   : SHORTINT;
      lAccess : GSAData.Instruction;
      rAccess : GSAData.Instruction;
      next    : Worklist;
    END;


  VAR
    aliasKind: ARRAY 3 OF ARRAY 5 OF CHAR;


  PROCEDURE WUsable(d : GSAData.Usable);
    VAR
      t : Types.Type;
      n : Types.Name;
  BEGIN
    t := Types.TypeOf(d);
    Types.NameOf(t, n);
    Config.LogWStr(n^);
  END WUsable;


  PROCEDURE FindAddress(i : GSAData.Instruction) : GSAData.Instruction;
    VAR
      opr : GSAData.Operand;
      adr : GSAData.Instruction;
  BEGIN
    ASSERT(i.class IN {GSAOpcode.Mupdate, GSAOpcode.Maccess});
    CASE i.subcl OF
    | GSAOpcode.Mfield:
      opr := GSAData.OperandNth(1, i);
      adr := opr.def(GSAData.Instruction); (* Computed address. *)
      RETURN adr;

    | GSAOpcode.Melement:
      opr := GSAData.OperandNth(1, i);
      adr := opr.def(GSAData.Instruction); (* Computed address. *)
      RETURN adr;

    | GSAOpcode.Mderef:
      opr := GSAData.OperandNth(1, i);
      adr := opr.def(GSAData.Instruction); (* Computed address. *)
      RETURN adr;

    | GSAOpcode.Mnonlocal:
      opr := GSAData.OperandNth(1, i);
      adr := opr.def(GSAData.Instruction); (* Computed address. *)
      RETURN adr;

    | GSAOpcode.Mvarparm:
      opr := GSAData.OperandNth(1, i);
      adr := opr.def(GSAData.Instruction); (* Computed address. *)
      RETURN adr;

    (* ELSE malformed instruction. *)
    END;
  END FindAddress;

  (* SameAddress:
   *
   *   Returns TRUE iff 'l' and 'r' refer to the same
   *   '{Mmemory, Madr}' instruction.
   *)

  PROCEDURE SameAddress(l, r : GSAData.Instruction) : BOOLEAN;
    VAR
      lo, ro : GSAData.Operand; (* Address of things being accessed. *)
      li, ri : GSAData.Instruction;
  BEGIN
    li := FindAddress(l);
    lo := GSAData.OperandNth(0, li);

    ri := FindAddress(r);
    ro := GSAData.OperandNth(0, ri);
    RETURN (li = ri) OR (lo.def = ro.def);
  END SameAddress;

  (* pre : level <=> lexical scope currently being analyzed *)
  (* pre : (o # NIL) & defined(o^) *)
  PROCEDURE IsNonLocalAccess(level : INTEGER; d : GSAData.Usable) : BOOLEAN;

    PROCEDURE MemoryAccess(level : INTEGER; i : GSAData.Instruction) : BOOLEAN;
      VAR
        op : GSAData.Operand;
    BEGIN
      ASSERT(i.class IN {GSAOpcode.Maccess, GSAOpcode.Mupdate});
      IF i.subcl IN {GSAOpcode.Mfield, GSAOpcode.Melement} THEN
        (* Is record or array access is non-local?
         * First operand: Instruction -> non-local.
         * First operand: ~Instruction -> direct variable access
         *)
        op := GSAData.OperandNth(0, i);
        RETURN op.def IS GSAData.Instruction;
      ELSE (* All other opcodes are always non-local. *)
        RETURN TRUE;
      END;
    END MemoryAccess;

  BEGIN
    WITH d:GSAData.Const DO
      RETURN FALSE;

    | d:GSAData.Type DO (* type descriptors are R/O *)
      RETURN FALSE;

    | d:GSAData.Symbol DO (* symbol access; scoping level not important because
                           * all non-local access handled through access/update
                           * instructions. *)
      RETURN FALSE;

    | d:GSAData.Temporary DO (* The compiler will not generate aliasing
                              * code using temporary variables.
                              *)
      RETURN FALSE;

    | d:GSAData.Addressable DO
      HALT(1026);               (* subsumed by Type & Symbol *)

    | d:GSAData.Instruction DO (* Certain instructions can produce non-local
                                * access characteristics. *)
      CASE d.class OF
      | GSAOpcode.Maccess, GSAOpcode.Mupdate:
        RETURN MemoryAccess(level, d);

      | GSAOpcode.Mmemory:
        RETURN d.subcl IN {GSAOpcode.Marraycopy, GSAOpcode.Mrecordcopy};

      | GSAOpcode.Hget, GSAOpcode.Hput,
        GSAOpcode.Hmemr, GSAOpcode.Hmemw,
        GSAOpcode.Gsystem:
        RETURN TRUE;

      ELSE
        RETURN FALSE;
      END;
    | d:GSAData.Result DO
      RETURN FALSE; (* results are not data references *)

    (* ELSE the type defintion of the `def' field has been changed or
     * extended (i.e. it has not been covered by this WITH statement) *)
    END;
  END IsNonLocalAccess;

  PROCEDURE GatherNonLocalUse(r : GSAData.Region) : NonLocalArray;
    TYPE
      NonLocalList = POINTER TO NonLocalListDesc;
      NonLocalListDesc = RECORD (* Groups of 16 GSAData.Usable. *)
        next : NonLocalList;
        object : ARRAY 16 OF GSAData.Usable;
      END;

    VAR
      retval : NonLocalArray;
      list : NonLocalList;
      curi : INTEGER; (* (Ai: 0 <= i < curi: valid(list.object[curi]))
                       * (for first element on list - all other elements
                       * on the list have their arrays filled with valid
                       * data)
                       *)
      nofElement : INTEGER; (* total number of non-local elements *)

    (* IMPROVE(thutt): Making a hash table out of this would improve the runtime
     * for large procedures
     *)
    PROCEDURE ExistsOnList(l : NonLocalList; d : GSAData.Usable) : BOOLEAN;
      VAR
        i : INTEGER;
        e : GSAData.Usable;
        t0, t1 : GSAData.Temporary;
        done : BOOLEAN;
    BEGIN
      LOOP
        IF l = NIL THEN
          RETURN FALSE;
        ELSE
          i := 0;
          done := FALSE;
          WHILE (i < LEN(l.object)) & (l.object[i] # NIL) DO
            e := l.object[i];
            INC(i);

            IF (d IS GSAData.Symbol) & (e IS GSAData.Symbol) THEN
               done := d(GSAData.Symbol).sym = e(GSAData.Symbol).sym;
            ELSIF (d IS GSAData.Temporary) & (e IS GSAData.Temporary) THEN
              t0 := d(GSAData.Temporary);
              t1 := e(GSAData.Temporary);
              done := (t0.kind = t1.kind) &
                      (t0.num = t1.num) &
                      ((t0.kind # GSAData.tfArrayLength) OR
                       (t0.dim = t1.dim));
            ELSIF (d IS GSAData.Instruction) & (e IS GSAData.Instruction) THEN
              done := d = e;
            (* ELSE nop *)
            END;
            IF done THEN
              RETURN TRUE;
            END;
          END;
        END;
        l := l.next;
      END;
    END ExistsOnList;

    PROCEDURE AddNode(v : GSAData.Usable);
      VAR
        n : NonLocalList;
        i : INTEGER;
    BEGIN
      ASSERT(v # NIL);
      IF ~ExistsOnList(list, v) THEN
        IF curi >= LEN(list.object) THEN (* current element full -> create new one *)
          NEW(n);
          i := LEN(n.object);
          REPEAT
            DEC(i);
            n.object[i] := NIL;
          UNTIL i = 0;
          n.next := list;
          list := n;
          curi := 0;
        END;
        list.object[curi] := v;
        INC(curi);
        INC(nofElement);
      END;
    END AddNode;

    (* traverse: traverses all instruction in `r', maintaining information
     *           about non-local access during the traversal
     *
     * pre : r # NIL & (r is the dummy head of an instruction list)
     * pre : level <=> lexical scoping level of the procedure containing `r'
     * post: `list' will be updated according to the number of
     *       non-local references detected.
     *)
    PROCEDURE traverse(r : GSAData.Region; level : INTEGER);
      VAR
        i : GSAData.Instruction;
        o : GSAData.Operand;
        rgn : GSAData.Region;
    BEGIN
      i := r.instructions.finst;
      WHILE i # r.instructions DO
       IF ~(i IS GSAData.Region) THEN
          (* Non-local access is established, in the general case, by
           * examining the operands of each instruction.  If the
           * operand boils down to a non-local access, then it must
           * be added to the accumulated data. Region operands are ignored.
           *
           * $exit operands are important to put on the list
           * because they are `obvious' non-locally-accessed data.
           *
           * $enter operands probably do not `need' to be on the list,
           * but it is a simplification which should be harmless.
           *)
          o := i.operands.fop;
          WHILE o # i.operands DO
            IF IsNonLocalAccess(level, o.def) THEN
              AddNode(o.def);
            END;
            o := o.fop;
          END;
        END;
        i := i.finst;
      END;

      rgn := r.regions.freg;
      WHILE rgn # r.regions DO
        traverse(rgn, level);
        rgn := rgn.freg;
      END;
    END traverse;

  BEGIN
    list := NIL;
    curi := LEN(list.object); (* Simulate a full element at startup. *)
    nofElement := 0;
    retval := NIL;

    ASSERT(r IS GSAData.GlobalRegion); (* AA assumes a whole procedure *)

    (* Procedure level is one-less than the level of all
     * identifiers declared in that scope.  Since AA uses
     * the scoping level of the identifiers it is more
     * convenient to use the nesting level of the identifiers
     * (rather than the procedure itself) when traversing
     * instructions.
     *)
    traverse(r, r(GSAData.GlobalRegion).proc.mnolev + 1);

    (* If at least one non-local use was found, copy
     * the inconvenient linked-list-array into a linear array
     * - the LEN() of which will be the number of elements.
     *)
    IF nofElement > 0 THEN
      NEW(retval, nofElement);
      ASSERT(list # NIL);
      ASSERT(curi > 0);
      ASSERT(curi <= LEN(list.object));
      REPEAT
        WHILE curi > 0 DO
          DEC(curi);
          DEC(nofElement);
          retval[nofElement] := list.object[curi];
        END;
        list := list.next;
        curi := LEN(list.object);
      UNTIL list = NIL;

      ASSERT(nofElement = 0);
    END;
    RETURN retval;
  END GatherNonLocalUse;

  (* Alias: result IN { GSAOpcode.Pnoalias,
   *                    GSAOpcode.Pmayalias,
   *                    GSAOpcode.Pdoesalias }
   *        if 'l' can alias 'r'.
   *
   * 'l' is an instruction that {updates, accesses} non-local data.
   * 'r' is an instruction that {updates, accesses} non-local data.
   *
   *  1. 'l' is integral type
   *     a. 'r' must be identical type
   *     b. possible aliasing methods of access:
   *        'l' is non-local, 'r' is varparm
   *        'l' is varparm, 'r' is non-local
   *        'l' is varparm, 'r' is varparm
   *
   *  2. 'l' is array type
   *     a. 'r' must be indentical type
   *     b. possible aliasing methods of access:
   *        'l' is non-local, 'r' is varparm
   *        'l' is varparm, 'r' is non-local
   *        'l' is varparm, 'r' is varparm
   *
   *  3. 'l' is pointer type
   *     a. 'r' must be indentical type     -or-
   *        'r' must be an extension of 'l' -or-
   *        'l' must be an extension of 'r'
   *     b. possible aliasing methods of access:
   *        'l' is non-local, 'r' is varparm
   *        'l' is varparm, 'r' is non-local
   *        'l' is varparm, 'r' is varparm
   *
   *  4. 'l' is record type
   *     The compiler does not handle record types as a single
   *     entity (as it does with integral types).  Consequently,
   *     there can be no aliasing of records.
   *
   *  5. 'l' is an array type
   *     The compiler does not handle array types as a single
   *     entity (as it does with integral types).  Consequently,
   *     there can be no aliasing of arrays.
   *
   *  Since each Instruction passed to this function is an $update or
   *  $access instruction, it is already known to be access of non-local
   *  data.
   *)
  PROCEDURE Alias(l, r : GSAData.Instruction) : SHORTINT;
    CONST
      integral = Symtab.NumSet + {Symtab.bool, Symtab.byte, Symtab.char,
                                  Symtab.set, Symtab.procedure};
  BEGIN
    ASSERT((l.class IN {GSAOpcode.Mupdate, GSAOpcode.Maccess}) &
           (l.subcl IN {GSAOpcode.Mfield, GSAOpcode.Melement,
                        GSAOpcode.Mderef, GSAOpcode.Mnonlocal,
                        GSAOpcode.Mvarparm}), 1024);
    ASSERT((r.class IN {GSAOpcode.Mupdate, GSAOpcode.Maccess}) &
           (r.subcl IN {GSAOpcode.Mfield, GSAOpcode.Melement,
                        GSAOpcode.Mderef, GSAOpcode.Mnonlocal,
                        GSAOpcode.Mvarparm}), 1025);

    IF SameAddress(l, r) THEN
      RETURN GSAOpcode.Pdoesalias;
    ELSIF (l.type.form IN integral) &
          (l.type.form = r.type.form) THEN
      RETURN GSAOpcode.Pmayalias;
    ELSIF l.type.form = Symtab.pointer THEN
      IF (l.type = r.type)              OR
         Symtab.Extends(l.type, r.type) OR
         Symtab.Extends(r.type, l.type) THEN
        RETURN GSAOpcode.Pmayalias;
      END;
    END;
    RETURN GSAOpcode.Pnoalias;
  END Alias;


  PROCEDURE Aliases(r       : GSAData.Region;
                    alias   : SHORTINT;
                    lAccess : GSAData.Instruction;
                    rAccess : GSAData.Instruction) : BOOLEAN;
  BEGIN
  END Aliases;

  (* AddAliases
   *
   *  Adds two alias pseudo-instructions, one for 'lAccess'
   *  and one for 'rAccess' if not already added.
   *)


  PROCEDURE InsertAliases(w : Worklist);
    VAR
      lAdr   : GSAData.Operand;
      rAdr   : GSAData.Operand;
      lDef   : GSAData.Usable;
      rDef   : GSAData.Usable;
      linst  : GSAData.Instruction;
      rinst  : GSAData.Instruction;
      lAlias : BOOLEAN;
      rAlias : BOOLEAN;
(*
      r       : GSAData.Region;
      alias   : SHORTINT;
      lAccess : GSAData.Instruction;
      rAccess : GSAData.Instruction) : BOOLEAN;
*)
    PROCEDURE GetDef(x : GSAData.Operand) : GSAData.Usable;
      VAR
        def     : GSAData.Usable;
        operand : GSAData.Operand;
    BEGIN
      (* If the definition is already a $mayalias, fetch the
       * actual address computation from the first operand.
       *
       * This process can result in duplicate $mayalias instructions
       * being added that have no uses, but they will be collected
       * during dead code removal.
       *)
      def := x.def;
      IF def(GSAData.Instruction).class = GSAOpcode.Palias THEN
        operand := GSAData.OperandNth(0, def(GSAData.Instruction));
        def := operand.def;
      END;
      ASSERT(def IS GSAData.Instruction);
      RETURN def;
    END GetDef;

  BEGIN
    lAdr   := GSAData.OperandNth(1, w.lAccess); (* computed address *)
    rAdr   := GSAData.OperandNth(1, w.rAccess); (* computed address *)
    lAlias := lAdr.def(GSAData.Instruction).class = GSAOpcode.Palias;
    rAlias := rAdr.def(GSAData.Instruction).class = GSAOpcode.Palias;
    IF ~lAlias OR ~rAlias THEN
      (* Only when the definition of an alias is NOT an alias
       * instruction should an alias instruction be inserted.
       * If the left definition is an alias, then the right
       * side must also be an alias.
       *)
      lDef := GetDef(lAdr);
      rDef := GetDef(rAdr);

      IF ~lAlias THEN
        linst := GSAData.NewInstruction(GSAOpcode.Palias, w.alias,
                                        lAdr.type, lAdr.pos);
        GSAData.OperandAppend(linst, lDef); (* $mayalias <lDef>, <rDef> *)
        GSAData.OperandAppend(linst, rDef);
        GSAData.OperandInsertBefore(w.lAccess, lAdr,
                                    linst); (* Replace second argument. *)
        GSAData.OperandDelete(lAdr);
        GSAData.InstructionAppend(w.r, linst);
        GSAData.InstructionReposition(w.lAccess, linst);
      END;

      IF ~rAlias THEN
        rinst := GSAData.NewInstruction(GSAOpcode.Palias, w.alias,
                                        rAdr.type, rAdr.pos);
        GSAData.OperandAppend(rinst, rDef); (* $mayalias <rDef>, <lDef> *)
        GSAData.OperandAppend(rinst, lDef);
        GSAData.OperandInsertBefore(w.rAccess, rAdr,
                                    rinst); (* Replace second argument. *)
        GSAData.OperandDelete(rAdr);
        GSAData.InstructionAppend(w.r, rinst);
        GSAData.InstructionReposition(w.rAccess, rinst);
      END;
    END;
  END InsertAliases;

  PROCEDURE AddWorklist(head    : Worklist;
                        r       : GSAData.Region;
                        alias   : SHORTINT;
                        lAccess : GSAData.Instruction;
                        rAccess : GSAData.Instruction);
    VAR
      wl : Worklist;
  BEGIN
    NEW(wl);
    wl.r       := r;
    wl.alias   := alias;
    wl.lAccess := lAccess;
    wl.rAccess := rAccess;
    wl.next    := head.next;
    head.next  := wl;           (* head is a dummy header. *)
  END AddWorklist;

  (* CheckForAliases: Look for aliases in the region
   * pre: (r # NIL) & defined(r^)
   * pre: (nla # NIL)
   *
   * nla: unordered array of objects which were accessed non-locally
   *      and which may be affected by any of the non-local-effect
   *      writes on the $exit instruction.
   *)
  PROCEDURE CheckForAliases(r : GSAData.GlobalRegion; nla : NonLocalArray);
    VAR
      lIdx     : INTEGER;
      rIdx     : INTEGER;
      lAccess  : GSAData.Instruction; (* Instruction updating memory. *)
      rAccess  : GSAData.Instruction; (* Instruction may alias 'lAccess'. *)
      inst     : GSAData.Instruction;
      sym      : GSAData.Addressable;
      alias    : SHORTINT;
      worklist : Worklist;
  BEGIN
    ASSERT(nla # NIL, 1024);
    NEW(worklist);              (* dummy head *)
    worklist.next := NIL;

    IF dfProgress IN diagnostics THEN
      Config.LogWStr('nla length=');
      Config.LogWNum(LEN(nla^), 3);
      Config.LogWLn;
    END;
    lIdx := 0;

    lIdx := 0;
    WHILE lIdx < LEN(nla^) DO
      IF nla[lIdx] # NIL THEN
        lAccess := nla[lIdx](GSAData.Instruction);
      ELSE
        lAccess := NIL;
      END;
      IF (lAccess # NIL) &
         (lAccess.class IN {GSAOpcode.Mupdate, GSAOpcode.Maccess}) THEN
        rIdx := lIdx + 1;
        WHILE rIdx < LEN(nla^) DO
          IF nla[rIdx] # NIL THEN
            rAccess := nla[rIdx](GSAData.Instruction);
            alias := MAX(SHORTINT);
            IF rAccess.class IN {GSAOpcode.Mupdate, GSAOpcode.Maccess} THEN
              alias := Alias(lAccess, rAccess);
            END;

            IF alias IN { GSAOpcode.Pmayalias } THEN
              AddWorklist(worklist, r, alias, lAccess, rAccess);
            END;
          END;
          INC(rIdx);
        END;
        IF dfProgress IN diagnostics THEN
          Config.LogWLn;
        END;
      END;
      INC(lIdx);
    END;

    worklist := worklist.next;
    WHILE worklist # NIL DO
      InsertAliases(worklist);
      worklist := worklist.next;
    END;
  END CheckForAliases;

  (* Alias Analysis (AA) is designed to detect occurrences of use &
   * assignment of non-local memory (var parameters, non-local
   * variables, global variables, heap variables) where one
   * memory location can actually refer (aliases) to another
   * memory location.
   *
   * To prevent stale values from being used, AA inserts code
   * to ensure that aliased values are updated properly.
   *
   * To accomplish this, the compiler will generate an address
   * test for potentially aliased data -- if the addresses are
   * the same, the data is aliased and special precautions must
   * be taken to ensure the aliased data contains the same value.
   *
   * Value numbering is used to detect and remove congruent values
   * from the IR prior to searching for aliases - this reduces
   * the checking required when locating `non-local memory access'
   * to a pointer check (instead of comparing instruction operands).
   *)
  PROCEDURE Perform*(r : GSAData.GlobalRegion);
    VAR
      nla : NonLocalArray; (* non-local access *)
  BEGIN
    ASSERT(r IS GSAData.GlobalRegion);
    IF dfProgress IN diagnostics THEN
      Config.LogWStr('Performing AA: ');
      Config.LogWStr(r(GSAData.GlobalRegion).proc.name^);
      Config.LogWLn;
    END;

    (* First step is to create an array of objects which are accessed
     * in a non-local manner:
     *  - global
     *  - non-local
     *  - var-parm
     *
     * This array will be used to determine which assignments to non-
     * local variables actually affect the non-local variables which are
     * used as rvalues.
     *)
    nla := GatherNonLocalUse(r);

    (* Full analysis only needs to be done if non-local rvalues are actually used *)
    IF nla # NIL THEN
      CheckForAliases(r, nla);
    END;
  END Perform;

BEGIN
  ASSERT((GSAOpcode.Pnoalias + 1 = GSAOpcode.Pmayalias) &
         (GSAOpcode.Pmayalias + 1 = GSAOpcode.Pdoesalias));
  COPY("NONE", aliasKind[0]);
  COPY("MAY ", aliasKind[1]);
  COPY("DOES", aliasKind[2]);
END O3GSAAliasAnalysis.
