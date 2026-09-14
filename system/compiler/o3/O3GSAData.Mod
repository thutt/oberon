MODULE O3GSAData;
IMPORT
  SYSTEM, (* diagnostic only *)
  Types, (* diagnostic info only *)
  Config := O3Config,
  Symtab := O3Symtab,
  GSAOpcode := O3GSAOpcode;

CONST
  UndefInfoData* = MIN(INTEGER);         (* Undefined Info field. *)
  UndefDFO*      = MIN(INTEGER);         (* Undefined instruction number. *)

CONST (* Register information *)
  UndefVReg*     = MIN(INTEGER);         (* Undefined virtual register number. *)

CONST  (* see `SymLocation.kind' *)
  slSymbol* = MIN(INTEGER);
  slAddress* = slSymbol + 1;
(*
    symLocTypeTag* = -1;
    symLocLength0* = 0;                    (* all attributes >= 0
                                            * indicate an array length of
                                            * that dimension *)
*)

CONST (* Result.attrib: used to mark specific features of instructions *)
  raLive* = 0;                (* instruction is always live and cannot
                               * be removed as dead code.
                               * (for example, code in module initialization)
                               *)
  raUniqueResult* = 1;         (* Instruction always produces
                                * unique result. *)
  raMaxGlobalAttribute* = (MAX(SET) + 1) DIV 2;

CONST (* temporary variable kind *)
  tfRegular* = 0;
  tfExit* = 1; (* $exit *)
  tfReturnFlag* = 2; (* $return-flag *)
  tfReturnValue* = 3; (* $return-value *)
  tfArrayLength* = 4; (* array length parameter; dimension denoted
                       * by Temporary.dim; owner by definedIn  *)
  tfRecordTag* = 5; (* record typetag parameter; owner is definedIn *)
  tfDynFrame* = 6; (* dynamic frame pointer for nested procedures *)
  tfMemory* = 7;   (* all memory used by the program *)
  tfNonLocalMem* = 8; (* nonlocal memory used by the current procedure *)


TYPE
  Name* = Symtab.SymbolName;

  Info* = POINTER TO InfoDesc;
  Node* = POINTER TO NodeDesc;
  Operand* = POINTER TO OperandDesc;
  Instruction* = POINTER TO InstructionDesc;
  Region* = POINTER TO RegionDesc;
  Merge* = POINTER TO MergeDesc;
  Guard* = POINTER TO GuardDesc;
  Gate* = POINTER TO GateDesc;
  GlobalRegion* = POINTER TO GlobalRegionDesc;  (* greg *)
  Usable* = POINTER TO UsableDesc;
  Location* = POINTER TO LocationDesc;
  Addressable* = POINTER TO AddressableDesc;
  Symbol* = POINTER TO SymbolDesc;
  Type* = POINTER TO TypeDesc;
  SymLocation* = POINTER TO SymLocationDesc;

  Generic* = RECORD
    a*, b*, c*, d* : LONGINT;
  END;

  InfoDesc* = RECORD
    pos* : LONGINT;          (* source file position
                              * inv: (pos >= 0) OR (pos = UndefInfoData)
                              *)
    ref* : LONGINT;          (* node number
                              * inv: (ref >= 0) OR (ref = UndefInfoData)
                              *)
    reg* : LONGINT;          (* global region number
                              * inv: (reg >= 0) OR (reg = UndefInfoData)
                              *
                              * The region number for all nodes in a procedure
                              * will be the same.
                              *)
    dfo* : INTEGER;          (* depth first order:
                              * inv: (dfo >= 0) OR (dfo = UndefInfoData)
                              *
                              * Mutable value that represents the order of the item
                              * in a depth-first traversal of the GlobalRegion.
                              *
                              * Recompute using RegionNumber().
                              * Invalid after any changes, such as adding, removing or
                              * reordering instructions, to the region are performed.
                              *)
  END;

  NodeDesc* = RECORD (InfoDesc)
    type- : Symtab.Type;      (* inv: type # NIL
                               * Type is used as the semantic type of the node,
                               * when such semantic information is required.
                               * Generally it is derived from the AST, but the
                               * BE will also supply its own type (normally an
                               * ordinal type) when creating nodes not based
                               * from the AST.
                               *)

    info* : Info;              (* inv: (info = NIL) OR defined(info^)
                                *
                                * The info field is a volatile field
                                * which is meant to be used by individual
                                * improvements; it is intended that this
                                * field is to be considered highly volatile
                                * and it should not be expected to be
                                * unperturbed at the end of any improvement
                                * unless the improvement states such.
                                *)
  END;

CONST
  VRegUndef*   = MIN(SHORTINT);
  VRegNone     = VRegUndef + 1; (* No registerrs used. *)
  VRegInteger* = 0;             (* VirtualReg.ireg is valid. *)
  VRegReal*    = 1;             (* VirtualReg.rreg is valid. *)
    
TYPE
  VirtualReg* = RECORD
    rkind- : SHORTINT; (* kind IN { VRegUndef, VregNone, VRegInteger,
                        *           VRegReal } *)
    ireg-  : INTEGER;  (* A integer virtual register number.
                        * inv: UndefVReg  - invalid value *)
    rreg-  : INTEGER;  (* A real virtual register number.
                        * inv: UndefVReg  - invalid value *)
  END;

TYPE
  (* UsableDesc is mainly useful through inheiritance.
   * Not much can be said about its properties without
   * considering its position in the type heirarchy.
   *)
  UsableDesc* = RECORD (NodeDesc)
    uses- : Operand; (* circular list of places where an operand is used
                      * inv: (uses # NIL) &
                      *      (uses references a doubly-linked circular
                      *       list chained by `buses', `fuses')
                      *
                      * This list has a dummy head, which has the nice
                      * effect of vastly simplifying list traversal, but it
                      * also has the effect of having the possiblity of having
                      * only a single node on the list - and that single node
                      * is not meant to be processed in the looping constructs.
                      *)
    vreg- : VirtualReg;
  END;

  (* Used to describe locations of defintion - for example, Symbols *)
  LocationDesc* = RECORD (InfoDesc)
(*
    locdef- : Instruction; (* instruction which owns the
                            * value at this location *)
 *)
  END;

  (* OperandDesc: describes an operand of an instruction
   * Operands for instructions reside on two (2) lists:
   * the `operand' list and the `uses' list.
   *
   * The `operand' list is associated with an instruction.
   * The `uses' list is associated with the `use' of the value
   * of an operand (where it was computed and other locations where
   * that computed value is used.
   *)
  OperandDesc* = RECORD (NodeDesc)
    bop- : Operand;       (* previous operand
                           * inv: (bop # NIL)
                           *
                           * Implements the `previous' pointer in a
                           * doubly-linked circular list
                           *)

    fop- : Operand;       (* next operand
                           * inv: (fop # NIL)
                           *
                           * Implements the `next' pointer in a
                           * doubly-linked circular list
                           *)

    buses- : Operand;     (* previous use of this value
                           * inv: (buses # NIL)
                           *
                           * Implements the `previous' pointer in a
                           * doubly-linked circular list
                           *)

    fuses- : Operand;     (* next use of this value
                           * inv: (fuses # NIL)
                           *
                           * Implements the `next' pointer in a
                           * doubly-linked circular list
                           *)


    owner- : Instruction; (* instruction which owns this operand
                           * inv: owner # NIL
                           *)

    def* : Usable;        (* definitions for this operand
                           * inv: def # NIL
                           *)
    location- : Location; (* `location' of this operand *)
    opnum- : INTEGER;     (* operand number:
                           * inv: valid directly after `RegionNumber()'
                           *)
  END;

  (* AddressableDesc: the base of the hierarchy which describes things
   *                  which are `addressable', such as Symbol, Constant
   *                  and type descriptors.
   *
   * This record constitutes a special entity; special in the respect
   * that it can complicate the code improvement algorithms with
   * unecessary special cases - all because the hierarchy extended from
   * AddressableDesc is not of the same lineage as a Result.  This is
   * important because the improvement algorithms work from the
   * assumption that an Instruction produces a Result, and these
   * Instruction/Result pairs are used to establish code scheduling,
   * code live-ness, and many other details.
   *
   * Consider, for example, DCE: placing an Addressable into an
   * instruction as an operand or Result effectively breaks the
   * def/uses chain and prevents easy marking of the definition of an
   * operand as `live'.
   *
   * While it could be argued that this rule does really apply to
   * the hierarchy extended from Const, this approach is not going to
   * be examined further because some constants may actually end up in
   * memory - in which case they truly are addressable values (LONGREAL
   * constants) - the rule, therefore is this:
   *
   * o When used as an lvalue, the Addressable object (Symbol,
   *   Temporary, Const) will be used (placed into the `Result.lhs'
   *   field.
   *
   * o When used as an rvalue, an Addressable must be rendered into a
   *   Result.  This will happen naturally through the use of the
   *   `Addressable.currvalue' field in all cases except the first
   *   rvalue use of an Addressable prior to its being set (this should
   *   only occur on uninitialized local variables (module variables are
   *   modeled through the $enter instruction result list)
   *)
  AddressableDesc* = RECORD (UsableDesc)
    faddr- : Addressable; (* forwards link
                           * circular doubly-linked list w/ dummy head
                           *)
    baddr- : Addressable; (* backwards link
                           * circular doubly-linked list w/ dummy head
                           *)

    (* FIXME: DCE requires currvalue to be R/W (`IS' test).  It should be R/O *)
    currvalue* : Usable; (* current value of the addressable object
                          * inv: currvalue = NIL -> value not assigned
                          * inv: currvalue # NIL -> value has been assigned
                          *                         to this item
                          *
                          * Temporaries, Types and Constants will have their
                          * `currvalue' field set to point to the themselves.
                          *)
    definedIn- : Symtab.Symbol; (* lexical scope in which this object is defined
                                 * inv: definedIn # NIL
                                 * variables, procedures,
                                 *    constants -> Symtab.SymbolScope
                                 * fields, methods -> Symtab.Symbol
                                 *                    which defined it
                                 * type descriptors -> Symtab.SymbolTypeDesc
                                 * imported modules -> Symtab.Symbol
                                 *                     of imported module
                                 * tempoarray length parameters ->
                                 *    Symtab.Symbol which owns the length
                                 * temporary dynamic frame pointers ->
                                 *    Symtab.Symbol which receives
                                 *    the frame pointer
                                 *)
  END;

  (* SymbolDesc *)
  SymbolDesc* = RECORD (AddressableDesc)
    sym- : Symtab.Symbol;
  END;

  Temporary* = POINTER TO TemporaryDesc; (* compiler-generated temporary *)
  TemporaryDesc* = RECORD (SymbolDesc)
    kind- : SHORTINT; (* tf<identifier> *)
    num- : INTEGER; (* generated temporary number.  inv: num >= 0 *)
    dim- : INTEGER; (* inv: kind = tfArrayLength -> dimension for array *)
  END;

  TypeDesc* = RECORD (AddressableDesc)
    (* uses type field from UsableDesc *)
  END;

  Const* = POINTER TO ConstDesc;
  ConstDesc* = RECORD (AddressableDesc)
    bcon- : Const; (* `previous' link for doubly-linked circular list
                    *)

    fcon- : Const; (* `next' link for doubly-linked circular list
                    *)
  END;

  ConstInt* = POINTER TO ConstIntDesc;
  ConstIntDesc* = RECORD (ConstDesc)
    val- : LONGINT;
  END;

  ConstIntRange* = POINTER TO ConstIntRangeDesc;
  ConstIntRangeDesc* = RECORD (ConstDesc)
    lo-, hi- : LONGINT;
  END;

  ConstSet* = POINTER TO ConstSetDesc;
  ConstSetDesc* = RECORD (ConstDesc)
    val- : SET;
  END;

  ConstBool* = POINTER TO ConstBoolDesc;
  ConstBoolDesc* = RECORD (ConstDesc)
    val- : BOOLEAN;
  END;

  ConstReal* = POINTER TO ConstRealDesc;
  ConstRealDesc* = RECORD (ConstDesc)
    val- : REAL;
  END;

  ConstLReal* = POINTER TO ConstLRealDesc;
  ConstLRealDesc* = RECORD (ConstDesc)
    val- : LONGREAL;
  END;

  ConstString* = POINTER TO ConstStringDesc;
  ConstStringDesc* = RECORD (ConstDesc)
    val- : Symtab.ConstExt;
  END;

  SymLocationDesc* = RECORD (LocationDesc)
    kind- : INTEGER; (* See 'sl'-prefixed constants *)
    var-: Addressable;
  END;

  (* Result: describes the `result' of an instruction
   * A single instruction can produce more than one Result - for
   * example, a divide instruction may produce both the
   * divide & modulus results.  These results are linked into a
   * doubly-linked circular list through the Results record.
   *
   * The linked list formed by `bres' and `fres' have the semantics
   * that `fres' is pointing at, `bres' away from, the
   * instruction which produced the result.
   *
   * The instructions are numbered from 0, monotonically increasing along
   * the `bres' pointer.
   *
   * eg:   Result<--bres|Result|fres-->Instruction
   *)
  Result* = POINTER TO ResultDesc;
  ResultDesc* = RECORD (UsableDesc)
    bres- : Result; (* previous result
                     * inv: (bres # NIL)
                     *
                     * Implements the `previous' link in a doubly-linked
                     * circular list.  The list has a dummy head.
                     *)

    fres- : Result; (* next result
                     * inv: (fres # NIL)
                     *
                     * Implements the `next' link in a doubly-linked
                     * circular list.  The list has a dummy head.
                     *)

    owner- : Instruction; (* instruction which owns this result
                           * inv: owner # NIL
                           *)
    location- : Location; (* location of this result
                           * inv: ???
                           *)

    lhs- : Addressable; (* left-hand-side of assignment
                         * inv: (lhs = NIL) OR defined(lhs^)
                         *
                         * only meant to be used by GSA dumping routines.
                         * DO NOT ASSUME THIS FIELD IS AVAILABLE
                         * FOR IMPROVEMENT ALGORITHM USE
                         *)

    resnum- : INTEGER; (* Ordinal number of result in instruction results. *)
    attrib* : SET; (* general purpose attributes
                    * elements 00..(MAX(SET) + 1) DIV 2
                    *          are reserved for global use
                    * elements (MAX(SET) + 1) DIV 2 + 1..MAX(SET)
                    *          are volatile between cia
                    *)
  END;

  (* InstructionDesc: implementation of GSA instruction
   * An instruction is the main mechanism through which work
   * occurs in the GSA framework.
   *
   * In general, an instruction performs some action and synthesizes
   * one or more results.  The results are kept in a doubly-linked
   * circular list, the instruction itself is kept as part of this list.
   * [An instruction such as DIV can produce multiple results - one for
   *  DIV and one for the MOD result.  Functions can also synthesize
   *  multiple results.]
   *
   * The instructions are, themselves, also kept on another doubly-linked
   * circular list of instructions contained in a Region.
   *
   * The instructions can also be kept on yet another list when performing
   * code improvement (such as scheduling).
   *)
  InstructionDesc* = RECORD (ResultDesc)
    results- : Result; (* list of results produced by Instruction
                        * inv: results # NIL
                        *
                        * Implements a doubly-linked list through Result.fres
                        * and Result.bres.  The instruction itself will be
                        * kept as the first entry on this list.  Other results
                        * will be placed following (using fres) the
                        * Instruction - the order of results is dependant upon
                        * the instruction which produces the multi-results.
                        *
                        * This list has a dummy head, which has the nice
                        * effect of vastly simplifying list traversal.
                        *)

    binst- : Instruction; (* previous Instruction in the current region
                           * inv: binst # NIL
                           *
                           * Implements the `previous' link of a doubly-linked
                           * list.
                           *)

    finst- : Instruction; (* next Instruction in the current region
                           * inv: (finst # NIL)
                           *
                           * Implements the `next' link of a doubly-linked
                           * list.
                           *)

    iplink* : Instruction; (* Improvement Algorithm 'previous'
                            * inv: (iplink = NIL) OR defined(iplink^)
                            *
                            * Implements the `previous' link of a doubly-linked
                            * list.  This field is used only by code improvement
                            * algorithms.  It should be considered volatile
                            * between improvement algorithms; algorithms which
                            * have other equirements must state them.
                            *
                            * This is exported R/W,  since the implementation
                            * is dependent upon the improvement algorithm.
                            *
                            * It is named differently to separate it entirely
                            * from the set of internally-managed links.
                            *)

    inlink* : Instruction; (* Improvement Algorithm 'next'
                            * inv: (inlink = NIL) OR defined(inlink^)
                            *
                            * Implements the `next' link of a doubly-linked
                            * list.  This field is used only by code improvement
                            * algorithms.  It should be considered volatile
                            * between improvement algorithms; algorithms
                            * which have other
                            * requirements must state them.
                            *
                            * This is exported R/W,  since the implementation
                            * is dependent upon the improvement algorithm.
                            *
                            * It is named differently to separate it entirely
                            * from the set of internally-managed links.
                            *)

    operands- : Operand;  (* doubly-linked circular list of Instruction operands
                           * inv: (operands # NIL)
                           *
                           * When not NIL, this references a doubly-linked
                           * circular list of Instruction operands;
                           * linked through 'fop' and 'bop'.
                           *
                           * This list has a dummy head, which has the nice
                           * effect of vastly simplifying list traversal.
                           *)

    region- : Region; (* region contianing this instruction
                       * inv: region = NIL -> global region
                       * inv: region # NIL -> nested region
                       *)

    generic* : Generic; (* generic field; unclaimed
                         * volatile (between improvements)
                         *
                         * This field can be used for any purpose, but it is
                         * considered to be volatile between improvements
                         * (assuming an improvment is implemented in a
                         * single module and references no external functions
                         * which are themselves improvements.
                         *)



    rangeL-, rangeH- : INTEGER; (* dominance ranges; set by RegionNumber() *)
    class-, subcl- : SHORTINT; (* instruction class & subclass *)
  END;

  (* GateDesc: phi node for user-defined symbols &
   *           compiler-generated temporaries
   *)
  GateDesc* = RECORD (InstructionDesc)
    var- : Addressable; (* variable controlled by the gate
                         * inv: (var # NIL)
                         * inv: (var IS Symbol) OR (var IS Temporary)
                         *)
    original- : Usable; (* original value of 'var' outside the gate
                         * inv: original # NIL
                         *)
  END;

  (* RegionDesc: Describes a 'region'
   * Regions, in addition to participating in all the linking of
   * a normal Instruction, form a doubly-linked circular list.
   *
   * A region conveniently contains a reference to the list of
   * nested regions within it, providing easy processing of
   * nested regions.
   *)
  RegionDesc* = RECORD (InstructionDesc)
    breg- : Region; (* previous Region
                     * inv: (breg # NIL)
                     *
                     * Implements 'previous' link of doubly-linked
                     * circular list
                     *)

    freg- : Region; (* next Region
                     * inv: (freg # NIL)
                     *
                     * Implements 'next' link of doubly-linked
                     * circular list
                     *)

    instructions- : Instruction;  (* list of Instructions contained
                                   * inv:    (instructions = NIL)
                                   *      OR defined(instructions^)
                                   *
                                   * Implements a doubly-linked circular list
                                   * through Instruction.finst
                                   * and Instruction.binst
                                   *
                                   * This list has a dummy head, which has the
                                   * nice effect of vastly simplifying list
                                   * traversal.
                                   *)

    regions- : Region; (* list of Regions contained
                        * inv: (regions = NIL) or defined(regions^)
                        *
                        * Implements a doubly-linked circular list through
                        * Region.freg and Region.breg
                        *
                        * This list has a dummy head, which has the nice
                        * effect of vastly simplifying list traversal.
                        *)

    merge- : Merge; (* Holds currently open merge region
                     * inv: (merge = NIL) OR defined(merge^)
                     *
                     * This field is initialized during the GSA
                     * conversion process; it holds the currently
                     * open Merge region so that merged assignments
                     * can be easily placed into it.  Following the
                     * conversion process, it holds the merge region
                     * associated with a guard.
                     *)
  END;

  (* Case: Special region for CASE statements *)
  Case* = POINTER TO CaseDesc;
  CaseDesc* = RECORD (RegionDesc) END;

  GuardDesc* = RECORD (RegionDesc) END;
  MergeDesc* = RECORD (RegionDesc) END;

  CondMerge* = POINTER TO CondMergeDesc;
  CondMergeDesc* = RECORD (MergeDesc)
    true-, false- : Region;
  END;

  (* GlobalRegionDesc: implementation of global regions
   * A global region is a region designated for a procedure; it
   * is like other regions except that it has more information associated
   * with it.
   *)
  GlobalRegionDesc* = RECORD (RegionDesc) (* greg *)
    proc- : Symtab.SymbolProc; (* program symbol which the greg represents
                                * inv: (proc # NIL) & (proc IS Symtab.SymbolProc)
                                *)

    enter- : Region; (* $enter
                      * inv: (enter = NIL) OR defined(enter^)
                      *
                      * The enter instruction models specific aspects
                      * of the procedure (such as which objects are
                      * passed to the function) and providing quick access
                      * to this instruction through the global region
                      * simplifies some specifics of GSA generation.
                      *)

    exit- : Region;  (* $exit instruction
                      * inv: (exit = NIL) OR defined(exit^)
                      *
                      * The exit instruction models specific aspects
                      * of the procedure and providing quick
                      * access to this instruction through
                      * the global region simplifies some specifics
                      * of GSA generation.
                      *
                      * The $exit instruction has, as operands, all
                      * instructions that have (potentially) non-local effect.
                      * For example: assignments to non-local or
                      * global variables,
                      * procedure/function calls.  Adding procedure calls as
                      * operands prevents them from being removed by the
                      * dead code
                      * eliminator (which functions like a mark and sweep GC).
                      *)

    constants- : Const; (* list of constants used in this procedure
                         * inv: (consts = NIL) OR defined(consts^)
                         *
                         * Implements a doubly-linked circular list
                         * through 'Const.fcon' and 'Const.bcon'.
                         *
                         * This value is mirrored by the module variable
                         * 'constants' during the duration of this procedure.
                         * The previous contents of 'constants' are copied to
                         * GlobalRegion.prevconsts at procedure entry.
                         *)

    addressables- : Addressable;
  END;

  (* BEData is used to associate a Symtab.Symbol with
   * a GSA node.  It is set into the Symbol.Symbol.bedata
   * field.
   *)
  BEData* = POINTER TO BEDataDesc; (* backend symbol data *)
  BEDataDesc* = RECORD (Symtab.BEDataDesc)
    (* The node created for a symbol will be stored
     * with the symbol so that the same node can be
     * returned each time a symbol is referenced
     *)
    node- : Addressable; (* inv: (node IS Symbol) OR (node IS Temporary) *)
  END;

  TYPE
    Item* = RECORD
      type* : Symtab.Type;
      node* : Usable;
    END;

    TempAttributes* = RECORD
      nofTemps : INTEGER;
    END;

VAR
  nofTemps : INTEGER;
  nofNodes : LONGINT;

  (** Forward Declarations *)
PROCEDURE ^ NewOperand*(pos : LONGINT; type : Symtab.Type) : Operand;
PROCEDURE ^ NewResult*(inst : Instruction;
                       type : Symtab.Type; pos : LONGINT) : Result;
PROCEDURE ^ NewRegion*(pos : LONGINT) : Region;
PROCEDURE ^ NewRegionEnter*(pos : LONGINT) : Region;
PROCEDURE ^ NewRegionExit*(pos : LONGINT) : Region;
PROCEDURE ^ NewInstruction*(class, subcl : SHORTINT;
                            type: Symtab.Type;
                            pos: LONGINT): Instruction;
PROCEDURE ^ NewSymLocation*(kind : INTEGER;
                            var: Addressable;
                            pos : LONGINT): SymLocation;
PROCEDURE ^ NewGate(subcl : SHORTINT; merge: Merge; var: Addressable): Gate;
PROCEDURE ^ OperandAppend*(inst : Instruction;
                           arg : Usable); (* was just Operand() *)
PROCEDURE ^ InstructionSetRegion*(x : Instruction; r : Region);
PROCEDURE ^ OperandReplace*(opnd: Operand; arg: Usable);
PROCEDURE ^ InstructionAppend*(region : Region; inst : Instruction);
PROCEDURE ^ InstructionPrepend*(region : Region; inst : Instruction);
PROCEDURE ^ MergeCommit*(x : Merge; r : Region);
PROCEDURE ^ MergeReset*(x : Merge);
PROCEDURE ^ OperandNth*(nth: INTEGER; inst: Instruction): Operand;
PROCEDURE ^ ConstGetInt*(r : Region;
                         val : LONGINT;
                         type : Symtab.Type;
                         pos : LONGINT) : Const;

(** Diagnostic info *)
PROCEDURE DiagNodeName*(lab : ARRAY OF CHAR; n : Node);
  VAR
    t : Types.Type;
    name : Types.Name;
BEGIN
  t := Types.TypeOf(n);
  Types.NameOf(t, name);
  Config.LogWLn;
  Config.LogWStr(lab);
  Config.LogWStr(': node ');
  Config.LogWHex(SYSTEM.VAL(LONGINT, n));
  Config.LogWStr(' name =<');
  Config.LogWStr(name^);
  Config.LogWStr('>');
END DiagNodeName;

(** Addressable List Management *)
PROCEDURE AddAddressable(greg : GlobalRegion; x : Addressable);
BEGIN
  x.faddr := greg.addressables.faddr;
  x.baddr := greg.addressables;
  greg.addressables.faddr.baddr := x;
  greg.addressables.faddr := x;
END AddAddressable;

(** Initializers *)
PROCEDURE InitInfo(x : Info; pos : LONGINT);
BEGIN
  x.ref := UndefInfoData;
  x.reg := UndefInfoData;
  x.pos := pos;
  x.dfo := UndefDFO;
END InitInfo;

PROCEDURE InitNode(x : Node; t : Symtab.Type; pos : LONGINT);
BEGIN
  InitInfo(x, pos);
  x.type := t;
  x.info := NIL;
END InitNode;

PROCEDURE InvalidateVReg(x : Usable);
BEGIN
  x.vreg.rkind := VRegUndef;
  x.vreg.ireg := UndefVReg;
  x.vreg.rreg := UndefVReg;
END InvalidateVReg;

PROCEDURE InitUsable(x : Usable; t : Symtab.Type; pos : LONGINT);
  VAR
    d : Operand;
BEGIN
  InitNode(x, t, pos);
  d := NewOperand(UndefInfoData, Symtab.undftyp);
  d.fuses := d;
  d.buses := d;
  x.uses := d;
  InvalidateVReg(x);
END InitUsable;

PROCEDURE InitAddressable(x : Addressable;
                          owner : Symtab.Symbol;
                          pos : LONGINT);
BEGIN
  InitUsable(x, Symtab.undftyp, pos);
  x.definedIn := owner;
  x.currvalue := NIL;
END InitAddressable;

PROCEDURE InitSymbol(x : Symbol; sym, owner : Symtab.Symbol; pos : LONGINT);
BEGIN
  InitAddressable(x, owner, pos);
  x.sym := sym;
  x.type := sym.type;
  x.pos := pos;
END InitSymbol;

PROCEDURE InitTemporary(x     : Temporary;
                        kind  : SHORTINT;
                        type  : Symtab.Type;
                        sym   : Symtab.Symbol;
                        owner : Symtab.Symbol;
                        pos   : LONGINT);
BEGIN
  InitSymbol(x, sym, owner, pos);
  x.currvalue := x;
  x.kind := kind;
  x.num := nofTemps;
  x.dim := MIN(INTEGER);
  x.type := type;
END InitTemporary;

PROCEDURE InitType(x : Type;
                   type : Symtab.Type;
                   owner : Symtab.Symbol;
                   pos : LONGINT);
BEGIN
  InitAddressable(x, owner, pos);
  x.type := type;
  x.currvalue := x;
END InitType;

PROCEDURE InitOperand(x : Operand; pos : LONGINT; type : Symtab.Type);
BEGIN
  InitNode(x, type, pos);
  x.def := NIL;
  x.location := NIL;
  x.bop := NIL;
  x.fop := NIL;
  x.buses := NIL;
  x.fuses := NIL;
  x.owner := NIL;
  x.opnum := 0;
END InitOperand;

PROCEDURE InitResult(x : Result;
                     owner : Instruction;
                     type : Symtab.Type;
                     pos : LONGINT);
BEGIN
  InitUsable(x, type, pos);
  x.bres := NIL;
  x.fres := NIL;
  x.owner := owner;
  x.location := NIL;
  x.lhs := NIL;
  x.attrib := {};
  x.resnum := 0;
END InitResult;

PROCEDURE InitInstruction(x : Instruction; type: Symtab.Type; pos: LONGINT);
  VAR
    r : Result;
    op : Operand;
BEGIN
  op := NewOperand(UndefInfoData, Symtab.undftyp); (* dummy head *)
  op.fop := op;
  op.bop := op;
  op.owner := x;

  (* The following Operand fields are not supposed to be NIL but
   * since this is a dummy head, it should not be processed in the
   * course of improvement algorithms.  Consequently, I have set
   * these fields to illegal values - if they are accessed in an
   * algorigthm, they will, of course, produce a NIL-pointer-accessed
   * exception.
   *)
  op.fuses := NIL;
  op.buses := NIL;
  op.def := NIL;

  r := NewResult(x, Symtab.undftyp, UndefInfoData);
  (* dummy head *)
  r.fres := x;
  r.bres := x;
  (* first result is the instruction itself *)

  InitResult(x, x, type, pos);
  x.region := NIL;
  x.finst := NIL;
  x.binst := NIL;
  x.pos := pos;
  x.rangeL := 0;
  x.rangeH := MIN(INTEGER);
  x.class := GSAOpcode.UndefClass;
  x.subcl := GSAOpcode.UndefSubclass;
  x.fres := r;
  x.bres := r;
  x.operands := op;
  x.results := r;
  x.iplink := NIL;
  x.inlink := NIL;
END InitInstruction;

PROCEDURE InitRegion(class, subcl : SHORTINT; x : Region; pos : LONGINT);
  VAR
    i : Instruction;
    r : Region;
BEGIN
  (* Create a new instruction to be used as the dummy list header
   * for the 'instructions' field.  This dummy header actually
   * violates some of the invariants for the Instruction object,
   * but as this record should never actually participate in any
   * improvement algorithm, it will be harmless - accessing these
   * illegal fields will cause a runtime error.
   *)
  i := NewInstruction(GSAOpcode.UndefClass,
                      GSAOpcode.UndefSubclass,
                      Symtab.undftyp,
                      UndefInfoData);
  i.finst := i;
  i.binst := i;
  i.results := NIL;
  i.operands := NIL;
  i.region := x;

  (* Create a new region to be used as the dummy list header
   * for the 'regions' field.  This dummy header actually
   * violates some of the invariants for the Region object,
   * but as this record should never actually participate in any
   * improvement algorithm, it will be harmless - accessing these
   * illegal fields will cause a runtime error.
   *
   * It's not possible to use 'r := NewRegion(...)' to create 'r'
   * because that would end up producing an uncontrolled recursion.
   *)
  NEW(r);
  InitInstruction(r, Symtab.undftyp, UndefInfoData);
  r.breg := r;
  r.freg := r;
  r.instructions := NIL;
  r.regions := NIL;
  r.merge := NIL;

  InitInstruction(x, Symtab.undftyp, pos);
  x.class := class;
  x.subcl := subcl;
  x.breg := NIL;
  x.freg := NIL;
  x.instructions := i;
  x.regions := r;
  x.merge := NIL;
END InitRegion;

PROCEDURE InitCase(r : Case; pos : LONGINT);
BEGIN
  InitRegion(GSAOpcode.Mregion, GSAOpcode.Mcasereg, r, pos);
END InitCase;

PROCEDURE InitGlobalRegion(x : GlobalRegion;
                           proc : Symtab.SymbolProc;
                           pos : LONGINT);
BEGIN
  InitRegion(GSAOpcode.Mregion, GSAOpcode.Mgreg, x, pos);
  x.proc := proc;
  x.enter := NewRegionEnter(pos);
  x.exit := NewRegionExit(pos);

  (* These settings are overwritten when the instructions are put
   * into the global region, but they are needed for fixing up loop
   * merges before the insertion occurs
   *)
  x.enter.region := x;
  x.exit.region := x;
  NEW(x.addressables);
  NEW(x.constants);
  (* dummy list heads *)
  x.addressables.baddr := x.addressables;
  x.addressables.faddr := x.addressables;
  x.constants.bcon := x.constants;
  x.constants.fcon := x.constants;
END InitGlobalRegion;

PROCEDURE InitGuard(x : Guard; cond: Usable;
                    class, subcl : SHORTINT;
                    pos: LONGINT);
BEGIN
  InitRegion(class, subcl, x, pos);
  OperandAppend(x, cond);
END InitGuard;

PROCEDURE InitMerge(m : Merge; subcl : SHORTINT; pos : LONGINT);
BEGIN
  InitRegion(GSAOpcode.Gmerge, subcl, m, pos);
END InitMerge;

PROCEDURE InitCondMerge(m : CondMerge; pos : LONGINT);
BEGIN
  InitMerge(m, GSAOpcode.Gcond, pos);
  m.true := NIL;
  m.false := NIL;
END InitCondMerge;

PROCEDURE InitGate(x : Gate;
                   class, subcl : SHORTINT;
                   type : Symtab.Type;
                   var : Addressable;
                   oldval : Usable;
                   pos : LONGINT);
BEGIN
  InitInstruction(x, type, pos);
  x.var := var;
  x.original := oldval;
  x.class := class;
  x.subcl := subcl;
END InitGate;

PROCEDURE InitLocation(x : Location; pos : LONGINT);
BEGIN
  InitInfo(x, pos);
END InitLocation;

PROCEDURE InitSymLocation(x : SymLocation;
                          kind : INTEGER;
                          var : Addressable;
                          pos : LONGINT);
BEGIN
  InitLocation(x, pos);
  x.kind := kind;
  x.var := var;
END InitSymLocation;

PROCEDURE InitConst(x : Const; pos : LONGINT);
BEGIN
  InitAddressable(x, NIL, pos);
  x.bcon := NIL;
  x.fcon := NIL;
  x.currvalue := x;
END InitConst;

PROCEDURE InitConstIntRange(x : ConstIntRange; pos : LONGINT);
BEGIN
  InitConst(x, pos);
  x.lo := 0;
  x.hi := 0;
END InitConstIntRange;

PROCEDURE InitConstInt(x : ConstInt; pos : LONGINT);
BEGIN
  InitConst(x, pos);
  x.val := 0;
END InitConstInt;

PROCEDURE InitConstBool(x : ConstBool; pos : LONGINT);
BEGIN
  InitConst(x, pos);
  x.val := FALSE;
END InitConstBool;

PROCEDURE InitConstSet(x : ConstSet; pos : LONGINT);
BEGIN
  InitConst(x, pos);
  x.val := {};
END InitConstSet;

PROCEDURE InitConstReal(x : ConstReal; pos : LONGINT);
BEGIN
  InitConst(x, pos);
  x.val := 0.0;
END InitConstReal;

PROCEDURE InitConstLReal(x : ConstLReal; pos : LONGINT);
BEGIN
  InitConst(x, pos);
  x.val := 0.0E0;
END InitConstLReal;

PROCEDURE InitConstString(x : ConstString; pos : LONGINT);
BEGIN
  InitConst(x, pos);
  NEW(x.val);
END InitConstString;

PROCEDURE InitBEData(x : BEData);
BEGIN
END InitBEData;

PROCEDURE InitItem*(VAR x : Item);
BEGIN
  x.type := Symtab.undftyp;
  x.node := NIL;
END InitItem;

(** doubly-linked cirucular list initialization *)

PROCEDURE CheckOperands(VAR x : Operand);
BEGIN
  ASSERT(FALSE);
END CheckOperands;

PROCEDURE CheckRegions(VAR x : Region);
BEGIN
  ASSERT(FALSE);
END CheckRegions;

PROCEDURE CheckInstructions(VAR x : Instruction);
BEGIN
 (* create dummy header if one does not exist *)
  ASSERT(FALSE);
END CheckInstructions;

(** Basic Functions *)

PROCEDURE GlobalRegionClose*(reg : GlobalRegion);
BEGIN
  InstructionPrepend(reg, reg.enter);
  InstructionAppend(reg, reg.exit);
END GlobalRegionClose;

(* IsResult: indicates if the input is a $result variable *)
(* pre: (x # NIL) & defined(x^) *)
(* post: TRUE -> x IS $result *)
(* post: FALSE -> ~(x IS $result) *)
PROCEDURE IsResult*(x : Addressable) : BOOLEAN;
BEGIN
  RETURN (x IS Temporary) & (x(Temporary).kind = tfReturnValue);
END IsResult;

PROCEDURE SymbolIsGlobal(sym : Symtab.Symbol) : BOOLEAN;
BEGIN
  RETURN sym.mnolev = 0;
END SymbolIsGlobal;

(* Create information for dominance tests 'Dominates' and 'DominatesNR'.
    Creating and moving regions within 'greg' invalidates the information.
*)

(* RegionNumber: sets 'dfo' of Instructions and 'opnum' of Operands in 'r' *)
PROCEDURE RegionNumber*(region : Region);

  PROCEDURE dominance(region : Region);
    VAR
      counter: INTEGER;

    PROCEDURE traverse(inst, i : Instruction; VAR c : INTEGER);
    BEGIN
      IF i # inst THEN
        i.rangeL := c;
        InvalidateVReg(inst);
        traverse(inst, i.finst, c);
        IF i IS Region THEN
          traverse(i(Region).instructions, i(Region).instructions.finst, c);
        END;
        i.rangeH := c;
        INC(c);
      END;
    END traverse;

  BEGIN
    counter := MIN(INTEGER);
    region.rangeL := counter;
    traverse(region.instructions, region.instructions.finst, counter);
    region.rangeH := counter;
  END dominance;

  PROCEDURE dfo(r : Region);
    VAR
      dfoRoot  : INTEGER;

    PROCEDURE traverse(r : Region; VAR dfo : INTEGER);
      VAR
        inst : Instruction;
        op   : Operand;
        rgn  : Region;
        res  : Result;
        k    : INTEGER;
    BEGIN
      r.dfo := dfo; (* Starting number for region. *)
      INC(dfo);

      inst := r.instructions.finst;
      WHILE inst # r.instructions DO
        IF inst IS Region THEN
          traverse(inst(Region), dfo);
        ELSE
          inst.dfo := dfo;
          INC(dfo);
        END;

        (* Number operands of 'i'. *)
        op := inst.operands.fop;
        k := 0;
        WHILE op # inst.operands DO
          op.opnum := k;
          INC(k);

(*
          IF op.def IS Result THEN
            op.def.dfo := dfo;  (* Addressable not always created
                                 * by instruction. *)
            INC(dfo);
          END;
*)

          op := op.fop;
        END;

        res := inst.results.fres;
        k   := 0;
        WHILE res # inst.results DO
          INC(k);
          res.resnum := k;
          res := res.fres;
        END;

        inst := inst.finst;
      END;
    END traverse;

  BEGIN
    dfoRoot := 0;
    traverse(r, dfoRoot);
  END dfo;

BEGIN
  dominance(region); (* Deliberately clears vreg. *)
  dfo(region);
END RegionNumber;


PROCEDURE AssignRegisters*(r         : Region;
                           VAR nInst : INTEGER;
                           VAR vreg  : VirtualReg);

  PROCEDURE SetVReg(u : Usable; integer : BOOLEAN; regno : INTEGER);
  BEGIN
    IF integer THEN
      u.vreg.rkind := VRegInteger;
      u.vreg.ireg := regno;
    ELSE
      u.vreg.rkind := VRegReal;
      u.vreg.rreg := regno;
    END;
  END SetVReg;

  PROCEDURE AddVReg(u : Usable; VAR vreg : VirtualReg);
    VAR
      f : SHORTINT;
  BEGIN
    f := u.type.form;
    IF f IN Symtab.RealSet THEN
      SetVReg(u, FALSE, vreg.rreg);
      INC(vreg.rreg);
    ELSE
(*
      ASSERT(f IN Symtab.BasicSet, 1024);
XXX this is not always true.  Why is a register being scheduled?
XXX or, make sure it has a proper type!
*)
      SetVReg(u, TRUE, vreg.ireg);
      INC(vreg.ireg);
    END;
  END AddVReg;

  PROCEDURE ComputeRegUsage(inst     : Instruction;
                            VAR vreg : VirtualReg);
    VAR
      op : Operand;
  BEGIN
    CASE inst.class OF
    | GSAOpcode.Maccess, GSAOpcode.Mupdate:
      AddVReg(inst, vreg);

    | GSAOpcode.Mmemory:
      CASE inst.subcl OF
      | GSAOpcode.Madr:
        (* No registers needed to compute the address of an object.
           If the address is used (SYSTEM.ADR, Var parms), then that
           will take a register; this is not handled at this point and
           will need modification. *)

      | GSAOpcode.Minitialize:
        (* Uses R0 to initialize fields.  May use stack pointer. *)
        SetVReg(inst, TRUE, 0); (* Use R0 for constant 0. *)

      | GSAOpcode.Mdynarrlen,
        GSAOpcode.Mnewarray,
        GSAOpcode.Mnewdynarray,
        GSAOpcode.Mnewrecord:
        (* Calls Kernel helper functions that returns the result in R1. *)
        ASSERT(Config.RegisterReturn - { 1 } = { });
        SetVReg(inst, TRUE, 1);

      | GSAOpcode.Marraycopy,
        GSAOpcode.Mrecordcopy,
        GSAOpcode.Mstringcopy:
        (* This calls a Kernel helper function.
         * No registers needed. *)

      | GSAOpcode.Mheaptag,
        GSAOpcode.Mtbpadr:
        (* Requires a register to load the heap tag or the
           address of the type bound procedure. *)
        AddVReg(inst, vreg);
      END;

    | GSAOpcode.Mregion:
      (* A Region doesn't use any registers. *)

    | GSAOpcode.Abegin..GSAOpcode.Aend - 1, (* Arithmetic *)
      GSAOpcode.Lbegin..GSAOpcode.Lend - 1, (* Logical *)
      GSAOpcode.Cbegin..GSAOpcode.Cend - 1, (* Compare *)
      GSAOpcode.Sbegin..GSAOpcode.Send - 1: (* Shift *)
      AddVReg(inst, vreg);

    | GSAOpcode.Gmisc:
      CASE inst.subcl OF
      | GSAOpcode.Gcall:    (* $call *)
        op := OperandNth(0, inst); (* Procedure symbol *)
        IF op.def.type # Symtab.niltyp THEN
        (* It's a function call.  R1 holds the return value. *)
          ASSERT(Config.RegisterReturn - { 1 } = { });
          SetVReg(inst, TRUE, 1);
        END;

      | GSAOpcode.Gcopy:    (* $copy *)
        (* Copy instructions are created only during transformation to
           GSA form, and then they are removed.  No registers needed. *)

      | GSAOpcode.Gcap:     (* CAP(ch) *)
        AddVReg(inst, vreg);
      END;

    | GSAOpcode.Gsystem:
      CASE inst.subcl OF
      | GSAOpcode.Gbit:
        AddVReg(inst, vreg);

      | GSAOpcode.Gnewblock,
        GSAOpcode.Gcondcode:
        (* These instructions call a Kernel helper and return
           a result in R1. *)
        ASSERT(Config.RegisterReturn - { 1 } = { });
        SetVReg(inst, TRUE, 1);

      | GSAOpcode.Gmove,
        GSAOpcode.Gresetbit,
        GSAOpcode.Gsetbit,
        GSAOpcode.Gfinalize:
        (* These instructions produce no result. *)
      END;

    | GSAOpcode.Gguard,     (* Guards produce no result. *)
      GSAOpcode.Gmerge:     (* Merges produce no result. *)

    | GSAOpcode.Gtypedesc:
      AddVReg(inst, vreg);

    | GSAOpcode.Hget,       (* Read from memory. *)
      GSAOpcode.Hmemr:      (* Read from memory. *)
      AddVReg(inst, vreg);

    | GSAOpcode.Hput,       (* Write to memmory. *)
      GSAOpcode.Hmemw:      (* Read from memory. *)
      (* These instructions do not produce a result. *)

    | GSAOpcode.Hgetreg,    (* Read register. *)
      GSAOpcode.Hputreg:    (* Write to register. *)
      (* These instructions are assigned a register when
       * the GSA is created. *)
      ASSERT(inst.vreg.rkind = VRegInteger);

    | GSAOpcode.Tbegin..GSAOpcode.Tend - 1: (* Traps *)
      (* Traps produce no output; use no registers. *)

    | GSAOpcode.Pbegin..GSAOpcode.Pend - 1: (* Pseudo *)
    END;
  END ComputeRegUsage;

  PROCEDURE traverse(r           : Region;
                     VAR nofInst : INTEGER;
                     VAR vreg    : VirtualReg);
    VAR
      inst : Instruction;
      op   : Operand;
      rgn  : Region;
      res  : Result;
      k    : INTEGER;
  BEGIN
    inst := r.instructions.finst;
    WHILE inst # r.instructions DO
      ASSERT(inst.vreg.rkind = VRegUndef, 1024);
      ComputeRegUsage(inst, vreg);

      IF inst IS Region THEN
        traverse(inst(Region), nofInst, vreg);
      END;

      INC(nofInst);

      (* Number operands of 'inst'. *)
      op := inst.operands.fop;
      k := 0;
      WHILE op # inst.operands DO
        op.opnum := k;
        IF op.def.vreg.rkind = VRegUndef THEN
          AddVReg(op.def, vreg);
        END;
        INC(k);
        op := op.fop;
      END;

      k   := 0;
      res := inst.results.fres; (* Bypass dummy head. *)
      ASSERT(res = inst, 1025);
      WHILE res # inst.results DO
        res.resnum := k;
        INC(k);
        IF ~(res IS Instruction) & (res.vreg.rkind = VRegUndef) THEN
          AddVReg(res, vreg);
(*
          IF res IS Instruction THEN
            ComputeRegUsage(res(Instruction), vreg);
          END;
 *)
        END;
        res := res.fres;
      END;

      inst := inst.finst;
    END;
  END traverse;

BEGIN
  vreg.rkind := VRegUndef;
  vreg.ireg := Config.RegisterCount;
  vreg.rreg := Config.RegisterCount;
  nInst     := 1;              (* Include 'r' in count. *)
  traverse(r, nInst, vreg);
END AssignRegisters;


(* TRUE, iff 'x = y' or 'y' is directly or indirectly nested in 'x'. *)
(* pre: Dominance information has been created by running
 *     'RegionNumber' and hasn't been invalidated in the meantime.
 *
 * TRUE -> x dominates y
 *)
PROCEDURE Dominates* (x, y: Instruction): BOOLEAN;
BEGIN
  RETURN (x.rangeL <= y.rangeH) & (y.rangeH <= x.rangeH);
END Dominates;

(* TRUE, iff 'y' is directly or indirectly nested in 'x',
 * but not if 'x = y'. *)
(* pre: Dominance information has been created by running
 * 'RegionNumber' and hasn't been invalidated in the meantime.
 * TRUE -> x dominates y & x # y
 *)
PROCEDURE DominatesNR* (x, y: Instruction): BOOLEAN;
BEGIN
  RETURN (x.rangeL <= y.rangeH) & (y.rangeH < x.rangeH);
END DominatesNR;

PROCEDURE SymbolSetNode*(x : Symtab.Symbol; n : Addressable);
BEGIN
  ASSERT((n IS Symbol) OR (n IS Temporary));
x.bedata(BEData).node := n;
END SymbolSetNode;

(* MergeOperandNumber: returns ordinal position of an
 *                     operand, 'r' of a Merge, 'm'
 *)
(* pre: m # NIL & defined(m^) *)
(* pre: r # NIL & defined(r^) *)
(* post: result < 0 -> r not an operand of 'm' *)
(* post: result >= 0 -> r is the result-th operand of 'm' *)
PROCEDURE MergeOperandNumber(m : Merge; r : Region) : INTEGER;
  VAR
    res : INTEGER;
    op : Operand;
BEGIN
  res := -1;
  op := m.operands.fop;
  WHILE (op # m.operands) & (op.def(Instruction).region # r) DO
    op := op.fop;
    INC(res);
  END;
  RETURN res;
END MergeOperandNumber;

(* MergeOpenControlRegion: appends 'r' to operands of 'm' and
 *                       sets it as the region of 'm'
 *)
(* pre: (m # NIL) & defined(m^) *)
(* pre: (r # NIL) & defined(r^) *)
(* pre: 'r' should not be an operand of 'm' *)
(* post: r will be an operand of 'm' *)
(* inv: The 'm' may or may not be in 'r' *)
PROCEDURE MergeOpenControlRegion*(m : Merge; r : Region);
BEGIN
  OperandAppend(m, r);
END MergeOpenControlRegion;

PROCEDURE MergeLoopFix(m : Merge; g : Gate; x : Usable);
  VAR
    u, n : Operand;
BEGIN
  u := x.uses.fuses;
  WHILE u # x.uses DO
    n := u.fuses;
    IF ~(u.owner IS Gate) & Dominates(m, u.owner.region) THEN
      OperandReplace(u, g);
    END;
    u := n;
  END;
END MergeLoopFix;

(* UseInsert: Adds a use, 'x', of 'arg'.
 * 'arg' is a usable value which is being placed as an
 * operand of some instruction.
 *
 * The new use will be inserted at the head of the use list.
 *
 * post: x.def = arg
 * post: arg.uses.fuses = x
 *)
PROCEDURE UseInsert*(x: Operand; arg: Usable);
BEGIN
  x.def := arg;
  (* prepend use, bypassing dummy head *)
  x.fuses := arg.uses.fuses;
  x.buses := arg.uses;
  arg.uses.fuses.buses := x;
  arg.uses.fuses := x;
END UseInsert;

(* UseDelete: Delete 'use' of operand 'x'
 * inv: x # NIL
 *
 * The operand 'x' is no longer being used, so it
 * should be removed from the use-list of 'x.def'.
 *
 * The dummy head cannot be removed, even if it is
 * the only element on the list - due to list processing
 * semantics (see UseReplace()).
 *)
PROCEDURE UseDelete*(x : Operand);
BEGIN
  (* unlink *)
  x.buses.fuses := x.fuses;
  x.fuses.buses := x.buses;
  x.fuses := NIL;
  x.buses := NIL;
END UseDelete;

(* Replaces all uses of 'x' with 'y'. *)
(*   pre: ~((x IS Symbol) OR (x IS Type)) *)
(* if 'x' is Symbol or Type,
 * then operands that may not be used as value
 * (eg, adr operand, access operand) may be replaced,
 * nuking their instructions *)
PROCEDURE UseReplace*(x, y: Usable);
  VAR
    u, n : Operand;
BEGIN
  u := x.uses.fuses;
  WHILE u # x.uses DO
    n := u.fuses;
    UseDelete(u);
    UseInsert(u, y);
    u := n;
  END;
END UseReplace;

PROCEDURE UseReplaceInRegion*(r : Region; x, y: Usable);
  VAR
    u, n : Operand;
BEGIN
  u := x.uses.fuses;
  WHILE u # x.uses DO
    n := u.fuses;
    IF u.owner.region = r THEN
      UseDelete(u);
      UseInsert(u, y);
    END;
    u := n;
  END;
END UseReplaceInRegion;

(* Replace 'used' in 'operand' with 'replacement'
 *)
PROCEDURE UseReplaceInOperand*(used : Usable;
                               operand : Operand;
                               replacement: Usable);
  VAR
    u, n : Operand;
BEGIN
(*
  u := x.uses.fuses;
  WHILE u # x.uses DO
    n := u.fuses;
    IF u.owner.region = r THEN
      UseDelete(u);
      UseInsert(u, y);
    END;
    u := n;
  END;
*)
END UseReplaceInOperand;

(* Set the 'opnum' field of 'op' to correspond to the actual operand number *)
PROCEDURE OperandNumber(op : Operand);
BEGIN
  IF op.bop = op.owner.operands THEN
    op.opnum := 0;
  ELSE
    op.opnum := op.bop.opnum + 1;
  END;
END OperandNumber;

(* OperandInsertBefore: adds 'arg' as an operand immediately prior to 'op' *)
(* pre: op must be an operand of 'inst' *)
PROCEDURE OperandInsertBefore*(inst : Instruction;
                               op : Operand;
                               arg : Usable);
  VAR
    x : Operand;
BEGIN
  x := NewOperand(arg.pos, arg.type);
  x.owner := inst;
  UseInsert(x, arg);

  (* link operand in to instruction *)
  x.fop := op;
  x.bop := op.bop;
  op.bop.fop := x;
  op.bop := x;
OperandNumber(x);
END OperandInsertBefore;

(* Adds 'arg' to the end of 'instr's operand list. *)
(* pre: arg # NIL *)
PROCEDURE OperandAppend*(inst : Instruction; arg : Usable);
  VAR
    x : Operand;
BEGIN
  x := NewOperand(arg.pos, arg.type);
  x.owner := inst;
  UseInsert(x, arg);
  (* link operand in to instruction *)
  x.fop := inst.operands;
  x.bop := inst.operands.bop;
  inst.operands.bop.fop := x;
  inst.operands.bop := x;
  OperandNumber(x);
END OperandAppend;

(* Adds 'arg' to the beginning of 'instr's operand list. *)
(* pre: arg # NIL *)
PROCEDURE OperandPrepend*(inst : Instruction; arg : Usable);
  VAR
    x : Operand;
BEGIN
  x := NewOperand(arg.pos, arg.type);
  x.owner := inst;
  UseInsert(x, arg);

  (* link operand in to instruction *)
  x.fop := inst.operands.fop;
  x.bop := inst.operands;
  inst.operands.fop := x;
  inst.operands.fop.bop := x;
  OperandNumber(x);
END OperandPrepend;

(* Adds 'arg' to the end of 'instr's operand list, but only if 'instr#arg' and
   'instr' doesn't have an argument with the value 'arg' already.  The new
   operands locations is set to 'loc'.
*)
(* pre: arg # NIL *)
PROCEDURE OperandUnique*(inst : Instruction; arg : Usable; loc : Location);
  VAR
    x : Operand;
BEGIN
  x := inst.operands.fop;
  WHILE (x # inst.operands) & (x # arg) DO
    x := x.fop;
  END;
  IF x # arg THEN (* inv: x = inst.operands *)
    OperandAppend(inst, arg); (* inv: inst is now at the end
                               * of the operand list *)
    inst.operands.bop.location := loc;
  END;
END OperandUnique;

(* Removes the operand 'x' from the list of x.owner operands. *)
PROCEDURE OperandDelete*(x : Operand);
BEGIN
  UseDelete(x);
  x.bop.fop := x.fop;
  x.fop.bop := x.bop;
  x.fop := NIL;
  x.bop := NIL;
  x.owner := NIL;
END OperandDelete;

PROCEDURE OperandDeleteAll(inst : Instruction);
  VAR
    x, n : Operand;
BEGIN
  x := inst.operands.fop;
  WHILE x # inst.operands DO
    n := x.fop;
    OperandDelete(x);
    x := n;
  END;
  (* inv: inst.operands still contains the dummy list head *)
END OperandDeleteAll;

PROCEDURE OperandReplace*(opnd: Operand; arg: Usable);
BEGIN
  UseDelete(opnd);
  UseInsert(opnd, arg);
END OperandReplace;

PROCEDURE ResultAppend*(inst : Instruction;
                        loc : Location;
                        type : Symtab.Type) : Result;
  VAR
    res : Result;
BEGIN
  res := NewResult(inst, type, inst.pos);
  res.location := loc;
  (* link the result *) res.fres := inst.results;
  res.bres := inst.results.bres;
  (* insert tail *) inst.results.bres.fres := res;
  inst.results.bres := res;
  RETURN res;
END ResultAppend;

(* Removes 'res' from its instruction's result list. *)
(*   pre: ~(res IS Instruction)  *)
PROCEDURE ResultDelete*(res: Result);
BEGIN
  ASSERT(~(res IS Instruction));
  res.fres.bres := res.bres;
  res.bres.fres := res.fres;
  res.bres := NIL;
  res.fres := NIL;
END ResultDelete;

(* change an 'access' instruction into an 'update' instruction *)
PROCEDURE InstructionAccToUpd*(inst : Instruction);
BEGIN
  ASSERT(inst.class = GSAOpcode.Maccess);
  inst.class := GSAOpcode.Mupdate;
END InstructionAccToUpd;

(* set owning region of 'x' to 'r' *)
(* pre: x # NIL & defined(x^) *)
(* pre: r # NIL & defined(r^) *)
PROCEDURE InstructionSetRegion*(x : Instruction; r : Region);
BEGIN
  x.region := r;
END InstructionSetRegion;

(* Prepends 'inst' to list of instructions of 'region'.  *)
(* If 'inst IS Region', then it's also inserted into the list of
 * nested regions.  *)
PROCEDURE InstructionPrepend*(region : Region; inst : Instruction);
BEGIN
  inst.region := region;
  inst.finst := region.instructions.finst;
  inst.binst := region.instructions;
  region.instructions.finst.binst := inst;
  region.instructions.finst := inst;

  WITH inst:Region DO  (* prepend region to list of regions *)
    inst.freg := region.regions.freg;
    inst.breg := region.regions;
    region.regions.freg.breg := inst;
    region.regions.freg := inst;
  ELSE (* nop *)
  END;
END InstructionPrepend;

(* Appends 'inst' to list of instructions of 'region'.  *)
(* If 'inst IS Region', then it's also inserted into the list of
 * nested regions.  *)
PROCEDURE InstructionAppend*(region : Region; inst : Instruction);
BEGIN
  inst.region := region;
  inst.finst := region.instructions;
  inst.binst := region.instructions.binst;
  region.instructions.binst.finst := inst;
  region.instructions.binst := inst;

  WITH inst:Region DO  (* prepend region to list of regions *)
    inst.freg := region.regions.freg;
    inst.breg := region.regions;
    region.regions.freg.breg := inst;
    region.regions.freg := inst;
  ELSE (* nop *)
  END;
END InstructionAppend;

(* Reverses the instruction list in 'region'.  *)
PROCEDURE InstructionReverse*(region: Region);
  VAR
    i, t : Instruction;
BEGIN
  i := region.instructions;
  REPEAT
    IF (i IS Region) THEN
      InstructionReverse(i(Region));
    END;
    t := i.finst;
    i.finst := i.binst;
    i.binst := t;
    i := t;
  UNTIL i = region.instructions;
END InstructionReverse;

(* Remove 'inst' from the list of instructions *)
PROCEDURE InstructionsRemoveFrom(inst : Instruction);
BEGIN
  inst.binst.finst := inst.finst;
  inst.finst.binst := inst.binst;
  inst.binst := NIL;
  inst.finst := NIL;
END InstructionsRemoveFrom;

(* remove 'r' from region list *)
PROCEDURE RemoveFromRegions(r : Region);
BEGIN
  r.breg.freg := r.freg;
  r.freg.breg := r.breg;
  r.freg := NIL;
  r.breg := NIL;
END RemoveFromRegions;

PROCEDURE RegionSetMerge*(r : Region; m : Merge);
BEGIN
  r.merge := m;
END RegionSetMerge;

PROCEDURE RegionFindGlobal*(n : Node) : GlobalRegion;
  VAR
    region : Region;
BEGIN
  WITH n:Operand DO
    region := n.owner.region;
  | n:Region DO
    region := n;
  | n:Instruction DO
    region := n.region;
  | n:Result DO
    region := n.owner.region;
  END;
  (* inv: global regions are not contained in another region *)
  WHILE (region.region # NIL) DO
    region := region.region;
  END;
  RETURN region(GlobalRegion);
END RegionFindGlobal;

(* Removes 'instr' from list of instructions of 'instr.region'.
 * If 'instr IS Region', then it's also removed from the list
 * of nested regions after its local instructions have been
 * deleted.  All operands are removed.
*)
PROCEDURE InstructionDelete*(inst : Instruction);
  VAR
    next : Instruction;
    r : Region;
    greg : GlobalRegion;

  PROCEDURE DeleteAllInstructions(r : Region);
    VAR
      i, n: Instruction;
  BEGIN
    i := r.instructions.finst;
    WHILE i # r.instructions DO
      n := i.finst;
      InstructionDelete(i);
      i := n;
    END;
  END DeleteAllInstructions;

BEGIN
  r := inst.region;
  (* if deleting enter or exit instruction: clear greg reference *)
  IF (inst.class = GSAOpcode.Mregion) &
     (inst.subcl IN {GSAOpcode.Menter, GSAOpcode.Mexit}) THEN
    greg := RegionFindGlobal(r);
    IF inst.subcl = GSAOpcode.Menter THEN
      greg.enter := NIL;
    ELSE
      greg.exit := NIL;
    END;
  END;

  (* get rid of operands and remove them from use lists *)
  OperandDeleteAll(inst);

  (* if not a global region... *)
  IF r # NIL THEN
    InstructionsRemoveFrom(inst);
  END;

  (* remove all instructions in the region 'instr' *)
  IF (inst IS Region) THEN
    WITH inst:Region DO
      DeleteAllInstructions(inst);
      IF r # NIL THEN (* remove this instruction from all regions *)
        RemoveFromRegions(inst);
      END;
    ELSE (* nop *)
    END;
  END;
END InstructionDelete;

PROCEDURE InstructionMove*(to : Region; inst : Instruction);
BEGIN
  InstructionsRemoveFrom(inst);
  IF (inst IS Region) THEN
    RemoveFromRegions(inst(Region));
  END;
  inst.region := NIL;
  InstructionAppend(to, inst);
END InstructionMove;

(* Moves an instruction within the same region.  Does not damage any
 * other data structure invariants other than moving the position of
 * the instruction. This is used by instruction scheduling
 *)
PROCEDURE InstructionReposition*(after, instr: Instruction);
BEGIN
  (* unlink instruction *)
  instr.finst.binst := instr.binst;
  instr.binst.finst := instr.finst;
  (* link to new position *)
  instr.binst := after;
  instr.finst := after.finst;
  after.finst.binst := instr;
  after.finst := instr;
END InstructionReposition;

PROCEDURE InstructionsMove*(from, to: Region);
  VAR
    inst : Instruction;
BEGIN
  inst := from.instructions.finst;
  WHILE inst # from.instructions DO
    InstructionMove(to, inst);
    inst := from.instructions.finst;
  END;
END InstructionsMove;


(*
(* Moves list of results starting at 'res.results' to the end of
*  the result list of 'to'. *)
(* pre: res.results # NIL *)

PROCEDURE ResultMoveList*(res : Result; to : Instruction);
BEGIN
  ASSERT(res.results # NIL);
  { CheckResults(to.results); (2000.09.15: removed function) }
  res.results.fres.bres := to.results.bres;
  res.results.bres.fres := to.results;

  to.results.bres.fres := res.results.fres;
  to.results.bres := res.results.bres;

  res := res.results.fres; (* switch ownership *)
  WHILE res # to.results DO
    res.owner := to;
    res := res.fres;
  END;
END ResultMoveList;
*)

(*
(* Move 'res' to the end of the result list.  *)
PROCEDURE ResultMoveToEnd*(res: Result);
  VAR
    prev: Result;
BEGIN
  ASSERT(res.bres # NIL, 1024);
  ASSERT(res.fres # NIL, 1025);
  (* unlink *)
  res.bres.fres := res.fres;
  res.fres.bres := res.bres;

  (* link *)
  ASSERT(res.owner.results # NIL, 1026);
  res.fres := res.owner.results;
  res.bres := res.owner.results.bres;
  res.owner.bres.fres := res;
  res.owner.bres := res;
END ResultMoveToEnd;
*)

(* Move 'opnd' to the end of the operand list.  *)
PROCEDURE OperandMoveToEnd*(op : Operand);
BEGIN
  ASSERT(op.bop # NIL, 1024);
  ASSERT(op.fop # NIL, 1025);
  (* unlink *)
  op.bop.fop := op.fop;
  op.fop.bop := op.bop;

  (* link *)
  op.fop := op.owner.operands;
  op.bop := op.owner.operands.bop;
  op.owner.operands.bop := op;
  op.owner.operands.bop.fop := op;
END OperandMoveToEnd;

PROCEDURE ResultTransferList*(prevRes: Result;
                              VAR saved: Result;
                              restore: BOOLEAN);
BEGIN
  ASSERT(FALSE);
END ResultTransferList;

PROCEDURE OperandTransferList*(prevOpnd: Operand;
                               VAR saved: Operand;
                               restore: BOOLEAN);
BEGIN
  ASSERT(FALSE); (* FIXME: incomplete implementation *)
END OperandTransferList;

(* Locates result of given symbolic location.  *)
PROCEDURE ResultFind*(inst : Instruction;
                      var: Addressable;
                      kind : INTEGER) : Result;
  VAR
    res : Result;
BEGIN
  res := inst.results.bres;
  WHILE (res # inst.results) &
        ((res.location = NIL) OR
         (res.location(SymLocation).var # var) OR
         (res.location(SymLocation).kind # kind)) DO
    res := res.bres;
  END;

  IF res = inst.results THEN
    RETURN NIL;
  ELSE
    RETURN res;
  END;
END ResultFind;

(* pre: NumberOfResults(inst) > 0 *)
PROCEDURE ResultLast*(inst : Instruction) : Result;
BEGIN
  RETURN inst.results.bres;
END ResultLast;

(* Sets the symbolic location op to 'obj'.  *)
(* pre: op # NIL & defined(op^) *)
(* pre: obj # NIL & defined(obj^) *)
PROCEDURE ResultSetSymLocation*(res : Result;
                                obj : Addressable;
                                kind : INTEGER);
  VAR
    s : SymLocation;
BEGIN
  s := NewSymLocation(kind, obj, obj.pos);
  res.location := s;
END ResultSetSymLocation;

(* Locates operand of given symbolic location.  *)
PROCEDURE OperandFind*(inst : Instruction;
                       var : Addressable;
                       kind : INTEGER) : Operand;
  VAR
    op : Operand;
BEGIN
  op := inst.operands.fop;
  WHILE (op # inst.operands) & ((op.location = NIL)
                             OR (op.location(SymLocation).var # var)
                             OR (op.location(SymLocation).kind # kind)) DO
    op := op.fop;
  END;

  IF op = inst.operands THEN
    RETURN NIL;
  ELSE
    RETURN op;
  END;
END OperandFind;

PROCEDURE OperandFirst*(inst : Instruction) : Operand;
BEGIN
  RETURN inst.operands.fop;
END OperandFirst;

(* pre: NumberOfOperands(inst) > 0 *)
PROCEDURE OperandLast*(inst : Instruction) : Operand;
BEGIN
  RETURN inst.operands.bop;
END OperandLast;

PROCEDURE OperandNext*(inst : Instruction) : Operand;
BEGIN
  HALT(1024); (* not implemented, yet. *)
END OperandNext;

PROCEDURE OperandPrev*(inst : Instruction) : Operand;
BEGIN
  HALT(1024); (* not implemented, yet. *)
END OperandPrev;

(* Sets the symbolic location op to 'obj'.  *)
(* pre: op # NIL & defined(op^) *)
(* pre: obj # NIL & defined(obj^) *)
PROCEDURE OperandSetSymLocation*(op : Operand;
                                 obj : Addressable;
                                 kind : INTEGER);
  VAR
    s : SymLocation;
BEGIN
  s := NewSymLocation(kind, obj, obj.pos);
  op.location := s;
END OperandSetSymLocation;

(* Retrieves the type of the given operand.  *)
PROCEDURE OperandType*(op : Operand) : Symtab.Type;
BEGIN
  RETURN op.type;
END OperandType;

(* Returns the position of the first operand of 'inst' that has 'arg' as
   argument.  Result is -1 if no such operand exists.  The first operand has
   the index 0.
*)
PROCEDURE ArgumentIndex*(inst : Instruction; arg: Usable) : INTEGER;
  VAR
    i: INTEGER;
    op : Operand;
BEGIN
  i := 0;
  op := inst.operands.fop;
  WHILE (op # inst.operands) & (op.def # arg) DO
    op := op.fop;
    INC(i);
  END;
  IF op = inst.operands THEN
    RETURN -1;
  ELSE
    RETURN i;
  END;
END ArgumentIndex;

(* Returns the position of 'opnd' in its instruction's operand list.  *)
(* The first operand has the index 0.  *)
(* pre: NumberOfOperands(op.owner) > 0 *)
PROCEDURE OperandIndex*(op : Operand) : INTEGER;
  VAR
    i : INTEGER;
    x : Operand;
BEGIN
  i := 0;
  x := op.owner.operands.fop;
  WHILE (x # op.owner.operands) & (x # op) DO
    INC(i);
    x := x.fop;
  END;
  ASSERT(x # op.owner.operands, 1025); (* x must be on the list *)
  RETURN i;
END OperandIndex;

(* Returns the 'nth' operand of 'instr'. *)
(* pre: 0 <= nth < Number of operands of 'instr'.  *)
PROCEDURE OperandNth*(nth: INTEGER; inst: Instruction): Operand;
  VAR
    op : Operand;
BEGIN
  op := inst.operands.fop;
  WHILE (op # inst.operands) & (nth # 0) DO
    op := op.fop;
    DEC(nth);
  END;
  IF (op # inst.operands) & (nth = 0) THEN
    RETURN op;
  ELSE
    RETURN NIL;
  END;
END OperandNth;

(* Returns the argument of the 'nth' operand of 'instr'. *)
(*   pre : 0 <= nth
 *   pre : inst # NIL
 *   post: result = NIL -> nth > Number of operands of 'instr'
 *   post: result # NIL -> defined(result^)
 *)
PROCEDURE ArgumentNth*(nth : INTEGER; inst : Instruction) : Usable;
  VAR
    op : Operand;
BEGIN
  op := inst.operands.fop;
  WHILE (op # inst.operands) & (nth # 0) DO
    op := op.fop;
    DEC(nth);
  END;
  IF (op # inst.operands) & (nth = 0) THEN
    RETURN op.def;
  ELSE
    RETURN NIL;
  END;
END ArgumentNth;

(* Returns the 'nth' result of 'instr'. *)
(*   pre : 0 <= nth
 *   pre : inst # NIL
 *   post: result = NIL -> nth > NumOfResults (instr).
 *   post: result # NIL -> defined(result^)
 *)
PROCEDURE ResultNth*(nth : INTEGER; inst : Instruction) : Result;
  VAR
    res: Result;
    i : INTEGER;
BEGIN
  res := inst.results.bres;
  WHILE (res # inst.results) & (nth # 0) DO
    res := res.bres;
    DEC(nth);
  END;
  IF (res # inst.results) & (nth = 0) THEN
    RETURN res;
  ELSE
    RETURN NIL;
  END;
END ResultNth;

(* Returns the position of 'result' in its instruction's result list.
 * The first result of an instruction (i.e.the instruction itself)
 * has the index 0.
 *)
PROCEDURE ResultIndex*(res : Result) : INTEGER;
  VAR
    i : INTEGER;
    x : Result;
BEGIN
  i := 0;
  x := res.owner.results.fres;
  WHILE (x # res.owner.results) & (x # res) DO
    INC(i);
    x := x.fres;
  END;
  ASSERT(x # res.owner.results);
  RETURN i;
END ResultIndex;

(* Returns the number of operands of 'instr'.*)
PROCEDURE OperandsNumberOf*(inst : Instruction) : INTEGER;
  VAR
    num : INTEGER;
    op : Operand;
BEGIN
  num := 0;
  op := inst.operands.fop;
  WHILE (op # inst.operands) DO
    INC(num);
    op := op.fop;
  END;
  RETURN num;
END OperandsNumberOf;

(* Returns the number of results of 'instr'.*)
PROCEDURE ResultsNumberOf*(inst : Instruction) : INTEGER;
  VAR
    num : INTEGER;
    res : Result;
BEGIN
  num := 0;
  res := inst.results.fres;
  WHILE (res # inst.results) DO
    INC(num);
    res := res.fres;
  END;
  RETURN num;
END ResultsNumberOf;

(* Returns the number of instructions in 'reg' *)
PROCEDURE InstructionsNumberOf*(reg : Region) : INTEGER;
  VAR
    num : INTEGER;
    inst : Instruction;
BEGIN
  num := 0;
  inst := reg.instructions.finst;
  WHILE (inst # reg.instructions) DO
    INC(num);
    inst := inst.finst;
  END;
  RETURN num;
END InstructionsNumberOf;

(* Locates the enter instruction of 'region's global
 * region.
 * Result is NIL if 'region=NIL' or no enter instruction exists.
 *)
PROCEDURE InstructionEnter*(reg : Region) : Region;
BEGIN
  IF reg = NIL THEN
    RETURN NIL;
  ELSE
    reg := RegionFindGlobal(reg);
    RETURN reg(GlobalRegion).enter;
  END;
END InstructionEnter;

(*
  Locates the exit instruction of 'region's global region.
  Result is NIL if 'region=NIL' or no exit instruction exists.
*)
PROCEDURE InstructionExit*(reg : Region) : Region;
BEGIN
  IF reg = NIL THEN
    RETURN NIL;
  ELSE
    reg := RegionFindGlobal(reg);
    RETURN reg(GlobalRegion).exit;
  END;
END InstructionExit;

(* Moves instruction 'inst' in the region's instruction list right behind the
   instruction 'prev'.
   Note that the region list is not modified.
*)
(*   pre: (prev.region = toMove.region)  *)
PROCEDURE InstructionMoveBehind*(prev, inst : Instruction);
  VAR
    reg : Region;
BEGIN
  ASSERT(prev.region = inst.region);
  InstructionsRemoveFrom(inst);
  inst.binst := prev;
  inst.finst := prev.finst;
  prev.finst := inst;
  prev.finst.binst := inst;
END InstructionMoveBehind;

(* Moves instruction 'toMove' in the region's instruction list right in front
   of the instruction 'next'.
   Note that the region list is not modified.
*)
(* pre: (next.region = inst.region)  *)
PROCEDURE InstructionMoveInFront*(next, inst: Instruction);
BEGIN
  ASSERT(next.region = inst.region);
  InstructionsRemoveFrom(inst);
  inst.binst := next;
  inst.finst := next.finst;
  next.finst := inst;
  next.finst.binst := inst;
END InstructionMoveInFront;

(* Sets 'info' fields of all results in 'region' to NIL.  *)
PROCEDURE ResultClearInfo*(region: Region);
  VAR
    inst : Instruction;
    res : Result;
BEGIN
  region.info := NIL;
  inst := region.instructions.finst;
  WHILE inst # region.instructions DO
    WITH inst:Region DO
      ResultClearInfo(inst);
    ELSE
      res := inst.results.fres;
      WHILE (res # inst.results) DO
        res.info := NIL;
        res := res.fres;
      END;
    END;
    inst := inst.finst;
  END;
END ResultClearInfo;

(* Sets 'info' fields of all instruction results in 'region' to NIL.
 * Regions are not modified.
 *)
PROCEDURE InstructionClearInfo*(region: Region);
  VAR
    inst : Instruction;
    res : Result;
BEGIN
  inst := region.instructions.finst;
  WHILE inst # region.instructions DO
    WITH inst: Region DO
      InstructionClearInfo(inst);
    ELSE
      res := inst.results.fres;
      WHILE res # inst.results DO
        res.info := NIL;
        res := res.fres;
      END;
    END;
    inst := inst.finst;
  END;
END InstructionClearInfo;

(* InstructionNewCopy: copy 'source'
  pre: r # NIL & defined(r^) (region into which the copy instruction is
                              appended)
  pre: source is the expression which should be copied
  pre: source # NIL & defined(source^)
*)
PROCEDURE InstructionNewCopy*(r : Region; source : Usable) : Instruction;
  VAR
    copy : Instruction;
BEGIN
  copy := NewInstruction(GSAOpcode.Gmisc, GSAOpcode.Gcopy,
                         source.type, source.pos);
  OperandAppend(copy, source);
  InstructionAppend(r, copy);
  RETURN copy;
END InstructionNewCopy;


(* InstructionNewMoveReg: Move to hardware register.
  pre: r # NIL & defined(r^) (region into which the copy instruction is
                              appended)
  pre: source is the result of the instruction that should be moved
       to a hardware register.
  pre: source # NIL & defined(source^)
*)
(* This should probably be removed in favor of doing these
 * instructions inline where needed. *)
PROCEDURE InstructionNewMoveReg*(r : Region;
                                 source : Usable;
                                 regno : INTEGER) : Instruction;
  VAR
    move : Instruction;
    const : Const;
BEGIN
  move := NewInstruction(GSAOpcode.Phwdreg, GSAOpcode.Pmovetoreg,
                         source.type, source.pos);
  const := ConstGetInt(r, regno, Symtab.linttyp, source.pos);
  OperandAppend(move, source);
  OperandAppend(move, const);
  InstructionAppend(r, move);
  RETURN move;
END InstructionNewMoveReg;

PROCEDURE InstructionAddAttribute*(inst : Instruction; attrib : SHORTINT);
BEGIN
  ASSERT(attrib IN {raLive, raUniqueResult});
  INCL(inst.attrib, attrib);
END InstructionAddAttribute;

PROCEDURE GateFind(m : Merge; var: Addressable) : Gate;
  VAR
    inst : Instruction;
BEGIN
  ASSERT(var # NIL, 1024);
  inst := m.instructions.finst;

  (* Scan instructions in the merge region.
   * Skip instructions which are not a Gate or which
   * do not match the addressable-item being searched.
   *)
  WHILE inst # m.instructions DO
    WITH inst:Gate DO
      IF inst.var = var THEN
        RETURN inst(Gate);
      END;

      IF (inst.var IS Symbol) &
         (var IS Symbol) &
         (inst.var(Symbol).sym = var(Symbol).sym) THEN
         RETURN inst(Gate);
      END;
    ELSE (* nop; ignore instruction *)
    END;
    inst := inst.finst;
  END;
  RETURN NIL;
END GateFind;

PROCEDURE GateNormalize(g : Gate);
  VAR
    m : Merge;
    nofMOp, nofGOp : INTEGER;
BEGIN
  m := g.region(Merge);
  nofMOp := OperandsNumberOf(m);
  nofGOp := OperandsNumberOf(g);
  IF nofMOp > nofGOp - 1 THEN

    (* Generally a gate will have no more than one operand
     * difference with the merge that controls it, however a merge
     * for a CASE can have an arbitrary number of operands, and a
     * Gate can be created along any arbitrary path.  This is
     * reflected in the following assertion.
     *)

    ASSERT((nofMOp - nofGOp IN {0, 1}) OR (m.subcl = GSAOpcode.Gcase), 1025);

    (* Merge: 1 operand for each control region which is merged
     * Gate: 1 operand for the variable gated, one operand
     *       for each control region
     *
     * If the merge has one more operand than the Gate;
     * add a new operand
     *)

    IF nofGOp = 1 THEN (* new gate (only merge region as operand) ;
                        * no control regions handled yet *)
      IF m.subcl = GSAOpcode.Gloop THEN

        (* A Gate in a loop-merge requires that RHS references to
          this variable reference the gate rather than the variable. *)

        (* The entire region must be numbered at this point because
          it is possible for a previously numbered region to have
          exactly the same dominance numbering and this will cause
          incorrect operands to be replaced in MergeLoopFix.

          It may be inefficient to number the whole region, but it
          is certain to give correct results.  Numbering just the
          region containing the Merge does not work (FOR loops).
         *)

        RegionNumber(RegionFindGlobal(m));
        MergeLoopFix(m, g, g.original);
      END;
    END;
    REPEAT
      OperandAppend(g, g.original);
      INC(nofGOp);
    UNTIL nofGOp > nofMOp;
  END;

  ASSERT(OperandsNumberOf(m) = OperandsNumberOf(g) - 1, 1030);
END GateNormalize;

PROCEDURE GateReplaceLastOperand(g : Gate; x : Item);
  VAR
    op : Operand;
BEGIN
  op := g.operands.bop; (* must have at least one operand *)
  ASSERT((op # NIL) & (op # g.operands), 1024);
  OperandReplace(op, x.node);
END GateReplaceLastOperand;

PROCEDURE GateReplaceOperand(g : Gate; r : Region; x : Item);
BEGIN
  ASSERT(FALSE);
END GateReplaceOperand;

(* GateGet: obtain a gate for 's' for region 'r' in merge region 'm'
  Since control paths are processed sequentially, operand 'n' of 'm'
  corresponds to control path 'n'.

  Merge regions which must be considered: if, loop, while, repeat,
  case

  For example:

  <outer control region>
  IF x THEN { path 0 }
  ELSE { path 1 }
  END;
  <outer control region>

  Merge <path 0>, <path 1>

  This extends to all looping and the CASE merges.

  When replacing gate operands it becomes very handy to have the
  original operand of path 'n' actually created in the control
  region (otherwise, the initial value of 's' will come from <outer
  control region> and it becomes difficult to determine which gate
  operand for a given region needs to be replaced.

  This problem can be remedied by creating <copy> instructions (of
  's') in the target region -- these will either be replaced by
  updates to the variable or they will be removed by copy
  propagation.

  This routine will ensure that the returned gate has the proper
  operands set up for region 'r'.  *)

PROCEDURE GateGet(m : Merge; r : Region; a : Addressable) : Gate;
  VAR
    g : Gate;
BEGIN
  g := GateFind(m, a);
  IF g = NIL THEN
    g := NewGate(GSAOpcode.Pgate, m, a);
  END;
  (* inv: g <-> gate for 'a' in 'm' *)

  GateNormalize(g);
  RETURN g;
END GateGet;

(* Sets 'info' fields of all regions in 'region' to NIL.
 * Instructions are not modified.  *)
PROCEDURE RegionClearInfo*(region: Region);
  VAR
    r : Region;
    inst : Instruction;
BEGIN
  region.info := NIL;
  r := region.regions.freg;
  inst := region.instructions.finst;
  WHILE inst # region.instructions DO
    inst.info := NIL;
    inst := inst.finst;
  END;
  WHILE r # region.regions DO
    RegionClearInfo(r);
    r := r.freg;
  END;
END RegionClearInfo;

PROCEDURE RegionClearLinks*(region: Region);
  VAR
    r : Region;
    inst : Instruction;
BEGIN
  region.inlink := NIL;
  region.iplink := NIL;
  inst := region.instructions.finst;
  WHILE inst # region.instructions DO
    inst.inlink := NIL;
    inst.iplink := NIL;
    inst := inst.finst;
  END;
  r := region.regions.freg;
  WHILE r # region.regions DO
    RegionClearLinks(r);
    r := r.freg;
  END;
END RegionClearLinks;

(** Constructors *)

PROCEDURE NewTemp(r : Region;
                  kind : SHORTINT;
                  type : Symtab.Type;
                  owner : Symtab.Symbol;
                  pos : LONGINT) : Temporary;
  VAR
    x : Temporary;
    sym : Symtab.Symbol;
    duplicate : BOOLEAN;
    name : Symtab.SymbolName;
    greg : GlobalRegion;
BEGIN
  NEW(x);
  greg := RegionFindGlobal(r);
  name := Symtab.MakeGeneratedName(NIL, NIL, '%', nofTemps);
  sym := Symtab.NewBasicSym(Symtab.var);
  sym.type := type;
  Symtab.InsertScope(greg.proc.scope, name^, sym, duplicate);
  ASSERT(~duplicate, 1100);
  InitTemporary(x, kind, type, sym, owner, pos);
  RETURN x;
END NewTemp;

PROCEDURE NewTemporary*(r : Region;
                        type : Symtab.Type;
                        owner : Symtab.Symbol;
                        pos : LONGINT) : Temporary;
  VAR
    x : Temporary;
BEGIN
  x := NewTemp(r, tfRegular, type, owner, pos);
  RETURN x;
END NewTemporary;

PROCEDURE NewTemporaryReturn*(r : Region;
                              owner : Symtab.Symbol;
                              pos : LONGINT) : Temporary;
  VAR
    rtn : Temporary;
BEGIN
  rtn := NewTemp(r, tfReturnFlag, Symtab.booltyp, owner, pos);
  RETURN rtn;
END NewTemporaryReturn;

PROCEDURE NewTemporaryResult*(r : Region;
                              type : Symtab.Type;
                              owner : Symtab.Symbol;
                              pos : LONGINT) : Temporary;
  VAR
    res : Temporary;
BEGIN
  res := NewTemp(r, tfReturnValue, type, owner, pos);
  RETURN res;
END NewTemporaryResult;

PROCEDURE NewTemporaryExit*(r : Region;
                            owner : Symtab.Symbol;
                            pos : LONGINT) : Temporary;
  VAR
    t0 : Temporary;
BEGIN
  t0 := NewTemp(r, tfExit, Symtab.booltyp, owner, pos);
  RETURN t0;
END NewTemporaryExit;

PROCEDURE NewTemporaryArrayLen*(r : Region;
                                dim : INTEGER;
                                owner : Symtab.Symbol;
                                pos : LONGINT) : Temporary;
  VAR
    t0 : Temporary;
BEGIN
  t0 := NewTemp(r, tfArrayLength, Symtab.linttyp, owner, pos);
  t0.dim := dim;
  RETURN t0;
END NewTemporaryArrayLen;

PROCEDURE NewTemporaryRecordTag*(r : Region;
                                 owner : Symtab.Symbol;
                                 pos : LONGINT) : Temporary;
  VAR
    t0 : Temporary;
BEGIN
  t0 := NewTemp(r, tfRecordTag, Symtab.linttyp, owner, pos);
  RETURN t0;
END NewTemporaryRecordTag;

PROCEDURE NewTemporaryDynFrame*(r : Region;
                                owner : Symtab.Symbol;
                                pos : LONGINT) : Temporary;
  VAR
    t0 : Temporary;
BEGIN
  t0 := NewTemp(r, tfDynFrame, Symtab.linttyp, owner, pos);
  RETURN t0;
END NewTemporaryDynFrame;

PROCEDURE NewTemporaryMemory*(r : Region;
                              owner : Symtab.Symbol;
                              pos : LONGINT) : Temporary;
  VAR
    t0 : Temporary;
BEGIN
  t0 := NewTemp(r, tfMemory, Symtab.linttyp, owner, pos);
  RETURN t0;
END NewTemporaryMemory;

(*
 * pre : owner <-> lexical scope which owns the temporary
 *)
PROCEDURE NewTemporaryNonLocalMem*(r : Region;
                                   owner : Symtab.Symbol;
                                   pos : LONGINT) : Temporary;
  VAR
    t0 : Temporary;
BEGIN
  t0 := NewTemp(r, tfNonLocalMem, Symtab.linttyp, owner, pos);
  RETURN t0;
END NewTemporaryNonLocalMem;

PROCEDURE NewSymLocation*(kind : INTEGER;
                          var : Addressable;
                          pos : LONGINT) : SymLocation;
  VAR
    loc: SymLocation;
BEGIN
  NEW(loc);
  InitSymLocation(loc, kind, var, pos);
  RETURN loc;
END NewSymLocation;

PROCEDURE NewGate(subcl : SHORTINT; merge: Merge; var: Addressable): Gate;
  VAR
    g : Gate;
    currvalue : Usable;
BEGIN
  NEW(g);
  (* FIXME(twh):
   * When a gate is created using a variable that has not been initialized,
   * it does not necessarily mean than it is uninitialized - it could be an
   * IF-ELSE in which the variable is initialized for the first time.
   * To alleviate failures in the compiler, handle this situation.  A further
   * pass on the gate when it is committed can determine if any path is
   * uninitialized.
   *)
  ASSERT(var.currvalue # NIL); (* Check that all variables are
                                * initialized before use. *)

  (* FIXME(twh): If the above assertion never fails, then the following IF
   * can be removed
   *)
  IF var.currvalue = NIL THEN
    currvalue := var;
  ELSE
    currvalue := var.currvalue;
  END;
  InitGate(g, GSAOpcode.Pmisc, subcl, var.type, var, currvalue, var.pos);
  OperandAppend(g, merge);
  InstructionAppend(merge, g);
  RETURN g;
END NewGate;

PROCEDURE NewInstruction*(class, subcl : SHORTINT;
                          type: Symtab.Type;
                          pos: LONGINT): Instruction;
  VAR
    inst: Instruction;
BEGIN
  NEW(inst);
  InitInstruction(inst, type, pos);
  inst.class := class;
  inst.subcl := subcl;
  RETURN inst;
END NewInstruction;

PROCEDURE NewGuard*(cond: Usable; subcl : SHORTINT; pos: LONGINT): Guard;
  VAR
    guard: Guard;
BEGIN
  NEW(guard);
  InitGuard(guard, cond, GSAOpcode.Gguard, subcl, pos);
  RETURN guard;
END NewGuard;

PROCEDURE NewMerge*(subcl: SHORTINT; pos : LONGINT): Merge;
  VAR
    merge: Merge;
BEGIN
  NEW(merge);
  InitMerge(merge, subcl, pos);
  RETURN merge;
END NewMerge;

PROCEDURE NewCondMerge*(pos : LONGINT): CondMerge;
  VAR
    m: CondMerge;
BEGIN
  NEW(m);
  InitCondMerge(m, pos);
  RETURN m;
END NewCondMerge;

PROCEDURE NewOperand*(pos : LONGINT; type : Symtab.Type) : Operand;
  VAR
    x : Operand;
BEGIN
  NEW(x);
  InitOperand(x, pos, type);
  RETURN x;
END NewOperand;

PROCEDURE NewResult*(inst : Instruction;
                     type : Symtab.Type;
                     pos : LONGINT) : Result;
  VAR
    r : Result;
    uh : Operand;
BEGIN
  NEW(r);
  InitResult(r, inst, type, pos);
  RETURN r;
END NewResult;

(* Creates a new Region, associating it with source position 'pos' *)
(* pre: pos >= 0 *)
PROCEDURE NewRegion*(pos : LONGINT) : Region;
  VAR
    r : Region;
BEGIN
  NEW(r);
  InitRegion(GSAOpcode.Mregion, GSAOpcode.Mreg, r, pos);
  RETURN r;
END NewRegion;

PROCEDURE NewRegionEnter*(pos : LONGINT) : Region;
  VAR
    r : Region;
BEGIN
  NEW(r);
  InitRegion(GSAOpcode.Mregion, GSAOpcode.Menter, r, pos);
  RETURN r;
END NewRegionEnter;

PROCEDURE NewRegionExit*(pos : LONGINT) : Region;
  VAR
    r : Region;
BEGIN
  NEW(r);
  InitRegion(GSAOpcode.Mregion, GSAOpcode.Mexit, r, pos);
  RETURN r;
END NewRegionExit;

PROCEDURE NewCase*(var : Usable; pos : LONGINT) : Case;
  VAR
    r : Case;
BEGIN
  NEW(r);
  InitCase(r, pos);
  OperandAppend(r, var);
  RETURN r;
END NewCase;

PROCEDURE NewGlobalRegion*(proc : Symtab.SymbolProc;
                           pos : LONGINT) : GlobalRegion;
  VAR
    r : GlobalRegion;
BEGIN
  NEW(r);
  InitGlobalRegion(r, proc, pos);
  r.freg := r;
  r.breg := r;
  RETURN r;
END NewGlobalRegion;

PROCEDURE NewBEData*() : BEData;
  VAR
    bedata : BEData;
BEGIN
  NEW(bedata);
  InitBEData(bedata);
  RETURN bedata;
END NewBEData;

PROCEDURE NewSymbol*(r : Region;
                     sym : Symtab.Symbol;
                     owner : Symtab.Symbol;
                     pos : LONGINT) : Symbol;
  VAR
    s : Symbol;
BEGIN
  ASSERT(owner # NIL);
  NEW(s);
  InitSymbol(s, sym, owner, pos);
  AddAddressable(RegionFindGlobal(r), s);
  RETURN s;
END NewSymbol;

PROCEDURE NewType*(type : Symtab.Type;
                   owner : Symtab.Symbol;
                   pos : LONGINT) : Type;
  VAR
    t : Type;
BEGIN
  NEW(t);
  InitType(t, type, owner, pos);
  t.currvalue := t;
  RETURN t;
END NewType;

PROCEDURE BindRegion*(old, new : Region);
BEGIN
  ASSERT(old # NIL);
  new.freg := old.freg;
  new.breg := old;
  old.freg.breg := new;
  old.freg := new;
END BindRegion;

(** Constant management *)

PROCEDURE AddConst(greg : GlobalRegion; c : Const);
BEGIN
  c.fcon := greg.constants.fcon;
  c.bcon := greg.constants;
  greg.constants.fcon.bcon := c;
  greg.constants.fcon := c;
END AddConst;

PROCEDURE ConstGetInt*(r : Region;
                       val : LONGINT;
                       type : Symtab.Type;
                       pos : LONGINT) : Const;
  VAR
    c : Const;
    ci : ConstInt;
    greg : GlobalRegion;
BEGIN
  greg := RegionFindGlobal(r);
  c := greg.constants.fcon;
  WHILE (c # greg.constants) DO
    IF (c.type = type) &
       (c IS ConstInt) &
       (c(ConstInt).val = val) THEN
      RETURN c;
    END;
    c := c.fcon;
  END;
  NEW(ci);
  InitConstInt(ci, pos);
  ci.type := type;
  ci.val := val;
  AddConst(greg, ci);
  RETURN ci;
END ConstGetInt;

PROCEDURE ConstGetIntRange*(r : Region;
                            lo, hi : LONGINT;
                            type : Symtab.Type;
                            pos : LONGINT) : Const;
  VAR
    c : Const;
    cr : ConstIntRange;
    greg : GlobalRegion;
BEGIN
  greg := RegionFindGlobal(r);
  c := greg.constants.fcon;
  WHILE (c # greg.constants) DO
    IF (c.type = type) & (c IS ConstIntRange) &
       (c(ConstIntRange).lo = lo) & (c(ConstIntRange).hi = hi) THEN
      RETURN c;
    END;
    c := c.fcon;
  END;
  NEW(cr);
  InitConstIntRange(cr, pos);
  cr.type := type;
  cr.lo := lo;
  cr.hi := hi;
  AddConst(greg, cr);
  RETURN cr;
END ConstGetIntRange;

PROCEDURE ConstGetBool*(r : Region; val : BOOLEAN; pos : LONGINT) : Const;
  VAR
    c : Const;
    cb : ConstBool;
    greg : GlobalRegion;
BEGIN
  greg := RegionFindGlobal(r);
  c := greg.constants.fcon;
  WHILE (c # greg.constants) DO
    IF (c.type = Symtab.booltyp) & (c(ConstBool).val = val) THEN
      RETURN c;
    END;
    c := c.fcon;
  END;
  NEW(cb);
  InitConstBool(cb, pos);
  cb.type := Symtab.booltyp;
  cb.val := val;
  AddConst(greg, cb);
  RETURN cb;
END ConstGetBool;

PROCEDURE ConstGetReal*(r : Region; val : REAL; pos : LONGINT) : Const;
  VAR
    c : Const;
    cr : ConstReal;
    greg : GlobalRegion;
BEGIN
  greg := RegionFindGlobal(r);
  c := greg.constants.fcon;
  WHILE (c # greg.constants) DO
    IF (c.type = Symtab.realtyp) & (c(ConstReal).val = val) THEN
      RETURN c;
    END;
    c := c.fcon;
  END;
  NEW(cr);
  InitConstReal(cr, pos);
  cr.type := Symtab.realtyp;
  cr.val := val;
  AddConst(greg, cr);
  RETURN cr;
END ConstGetReal;

PROCEDURE ConstGetLReal*(r : Region; val : LONGREAL; pos : LONGINT) : Const;
  VAR
    c : Const;
    cr : ConstLReal;
    greg : GlobalRegion;
BEGIN
  greg := RegionFindGlobal(r);
  c := greg.constants.fcon;
  WHILE (c # greg.constants) DO
    IF (c.type = Symtab.lrltyp) & (c(ConstLReal).val = val) THEN
      RETURN c;
    END;
    c := c.fcon;
  END;
  NEW(cr);
  InitConstLReal(cr, pos);
  cr.type := Symtab.lrltyp;
  cr.val := val;
  AddConst(greg, cr);
  RETURN cr;
END ConstGetLReal;

PROCEDURE ConstGetSet*(r : Region; val : SET; pos : LONGINT) : Const;
  VAR
    c : Const;
    cs : ConstSet;
    greg : GlobalRegion;
BEGIN
  greg := RegionFindGlobal(r);
  c := greg.constants.fcon;
  WHILE (c # greg.constants) DO
    IF (c.type = Symtab.settyp) & (c(ConstSet).val = val) THEN
      RETURN c;
    END;
    c := c.fcon;
  END;
  NEW(cs);
  InitConstSet(cs, pos);
  cs.type := Symtab.settyp;
  cs.val := val;
  AddConst(greg, cs);
  RETURN cs;
END ConstGetSet;

PROCEDURE ConstGetString*(r : Region;
                          val : Symtab.ConstExt;
                          pos : LONGINT) : Const;
  VAR
    c : Const;
    cs : ConstString;
    greg : GlobalRegion;
BEGIN
  greg := RegionFindGlobal(r);
  c := greg.constants.fcon;
  WHILE (c # greg.constants) DO
    IF (c.type = Symtab.stringtyp) & (c(ConstString).val^ = val^) THEN
      RETURN c;
    END;
    c := c.fcon;
  END;
  NEW(cs);
  InitConstString(cs, pos);
  cs.type := Symtab.stringtyp;
  cs.val^ := val^;
  AddConst(greg, cs);
  RETURN cs;
END ConstGetString;

PROCEDURE ConstGetNil*(r : Region; pos : LONGINT) : Const;
  VAR
    c : Const;
    ci : ConstInt;
    greg : GlobalRegion;
BEGIN
  greg := RegionFindGlobal(r);
  c := greg.constants.fcon;
  WHILE (c # greg.constants) DO
    IF (c.type = Symtab.niltyp) &
       (c IS ConstInt) &
       (c(ConstInt).val = Config.NilValue) THEN
      RETURN c;
    END;
    c := c.fcon;
  END;
  NEW(ci);
  InitConstInt(ci, pos);
  ci.type := Symtab.niltyp;
  ci.val := Config.NilValue;
  AddConst(greg, ci);
  RETURN ci;
END ConstGetNil;

(* Frees all constants in the internally managed list that aren't in use.  Not
   in use means that a given constant doesn't appear in some piece of GSA code
   and that it isn't part of some module's symbol table.
*)
(*
PROCEDURE FreeConsts*;
  VAR
    i: INTEGER;

  PROCEDURE FreeList (VAR c: Const);
  BEGIN
    IF (c # NIL) THEN FreeList (c.finstConst);
      IF (c.uses = NIL) & ~c.preserve THEN
        c.type := NIL;
        c.string := NIL;
        c := c.finstConst;
      END;
    END;
  END FreeList;

BEGIN
  FOR i := 0 TO sizeConstList-1 DO
    FreeList(constList[i]);
  END;
  FreeList (constRange);
END FreeConsts;
*)


(** Control Flow *)

(* CaseOperandAdd: add a 'case label range' to a case label *)
(* pre: (g # NIL) & (g IS Guard) & (g.subcl = Gcasesgl) *)
(* pre: (t # NIL) & (t <-> operand type of the CASE statement *)
(* pre: lo <= hi *)
(* pre: ('t lo bound' <= lo) & (hi <= 't high bound') *)
(* pre: front end ensures no duplicate case labels *)
(*
  This procedure inserts a new operand for 'g' corresponding to the
  label range denoted by [lo..hi].
  The operands will be maintained in an ascending sorted order.
  Adjacent ranges will be merged into a single range.
*)
PROCEDURE CaseOperandAdd*(g : Guard;
                          t : Symtab.Type;
                          lo, hi : LONGINT;
                          pos : LONGINT);
  VAR
    oldop, op : Operand;
    def, newop : Usable;
BEGIN
  def := NIL;
  op := g.operands.fop.fop; (* first operand (past head)
                             * is the selection variable *)
  (* find the position where the new operand should be placed *)
  LOOP
    IF op = g.operands THEN
      EXIT;
    END;
    ASSERT(op.def IS Const, 1024); (* all operands of a case label
                                    * must be constant *)
    def := op.def;
    WITH def:ConstIntRange DO
      IF lo < def.lo THEN
        ASSERT(hi < def.hi, 1025);
        EXIT;
      END;
    | def:ConstInt DO
      IF lo < def.val THEN
        ASSERT(hi < def.val, 1026);
        EXIT;
      END;
    END;
    op := op.fop;
  END;
  (* inv: new operand is to be inserted before 'op' *)
  (* inv: def contains the definition of 'op' *)

  IF def # NIL THEN
    (* check for coalescing of ranges *)
    WITH def:ConstIntRange DO
      IF (op # g.operands) &
         (hi < Symtab.metrics[t.form](Symtab.OrdMetric).max) &
         (hi + 1 = def.lo) THEN
        (* coalesce next *)
        hi := def.hi;
        oldop := op;
        op := op.fop;
        OperandDelete(oldop);
      END;
      IF (op.bop # g.operands) &
         (lo > Symtab.metrics[t.form](Symtab.OrdMetric).min) &
         (lo - 1 = def.hi) THEN
        (* coalesce previous *)
        lo := def.lo;
        oldop := op;
        op := op.fop;
        OperandDelete(oldop);
      END;
    | def:ConstInt DO
      IF (op # g.operands) &
         (hi < Symtab.metrics[t.form](Symtab.OrdMetric).max) &
         (hi + 1 = def.val) THEN
        (* coalesce next *)
        hi := def.val;
        oldop := op;
        op := op.fop;
        OperandDelete(oldop);
      END;
      IF (op.bop # g.operands) &
         (lo > Symtab.metrics[t.form](Symtab.OrdMetric).min) &
         (lo - 1 = def.val) THEN
        (* coalesce previous *)
        lo := def.val;
        oldop := op;
        op := op.fop;
        OperandDelete(oldop);
      END;
    END;
  END;

  IF lo = hi THEN
    newop := ConstGetInt(g, lo, t, pos);
  ELSE
    newop := ConstGetIntRange(g, lo, hi, t, pos);
  END;

  (* inv: op may have changed *)
  (* inv: 'newop' is to be inserted before 'op' *)
  OperandInsertBefore(g, op, newop);
END CaseOperandAdd;

PROCEDURE SplitPaths*(r : Region; cond : Item; pos : LONGINT;
                      VAR true, false : Region);
  VAR
    c : Node;
    x : Item;
    t0 : Region;
    not : Instruction;
BEGIN
  c := cond.node;
  IF c IS CondMerge THEN
    (*
     * A conditional merge as the condition already has merge nodes
     * set up, so they can be simply used instead of creating new
     * ones
     *)
    true := c(CondMerge).true;
    false := c(CondMerge).false;
  ELSIF (c IS Instruction) & (c(Instruction).class = GSAOpcode.Anot) &
        (c(Instruction).subcl = GSAOpcode.asU1) THEN
    (* instruction is a boolean 'not' operator; delete the
     * instruction and reverse the true/false regions
     *)
    not := c(Instruction);
    InitItem(x);
    x.node := c(Instruction).operands.fop.def;
    SplitPaths(r, x, pos, true, false);
    t0 := true;
    true := false;
    false := t0;
    InstructionDelete(not);
  ELSE
    true := NewGuard(cond.node, GSAOpcode.Gtrue, pos);
    false := NewGuard(cond.node, GSAOpcode.Gfalse, pos);
    InstructionAppend(r, true);
    InstructionAppend(r, false);
  END;
END SplitPaths;

PROCEDURE SplitControlPath*(r : Region;
                            cond : Item;
                            pos : LONGINT;
                            VAR true, false : Region;
                            VAR merge : Merge);
BEGIN
  merge := NewMerge(GSAOpcode.Gif, pos);
  SplitPaths(r, cond, pos, true, false);
  RegionSetMerge(true, merge);
  RegionSetMerge(false, merge);
  InstructionAppend(r, merge);
END SplitControlPath;

(* RegionReassociate
 *
 * After moving all instructions from a region, it is necessary to
 * associated subregions with the new parent region.  This procedure
 * disassociates direct subregions of 'r' from 'r' and then reassociates
 * them with the region containing 'r'.
 *)
PROCEDURE RegionReassociate(r : Region);
  VAR
    freg, lreg : Region;
BEGIN
  freg := r.regions.freg;
  lreg := r.regions.breg;
  WHILE freg # r.regions DO
    freg.region := r.region;
    freg := freg.freg;
  END;
  freg := r.regions.freg;
  IF freg # r.regions THEN (* there are regions which
                            * need reassociation *)
    freg.breg := r;
    lreg.freg := r.freg;
    r.freg.breg := lreg;
    r.freg := freg;
  END;
  r.regions.freg := r.regions;
  r.regions.breg := r.regions;
END RegionReassociate;

(* GuardMoveBody: move body of guard right before the guard
 *
 * When a guarded region is known to always be executed, it
 * is important to move the guarded region to the region
 * containing the guard.  For aesthetic reasons, it's
 * nice to place those instructions immediately prior
 * to the guard.
 *
 * pre: g evaluates to TRUE (conditional constant propagation)
 * pre: region is not empty
 *)
PROCEDURE GuardMoveBody*(g : Guard);
  VAR
    inst, linst, t : Instruction;
BEGIN
  IF g.instructions.finst # g.instructions THEN
    inst := g.instructions.finst;
    linst := g.instructions.binst;
    t := inst;
    WHILE t # linst DO
      t.region := g.region;
      t := t.finst;
    END;
    inst.binst := g.binst;
    linst.finst := g;
    g.binst.finst := inst;
    g.binst := linst;
    g.instructions.finst := g.instructions;
    g.instructions.binst := g.instructions;

    (* detach all regions contained and attach to parent region *)
    RegionReassociate(g);
  END;
END GuardMoveBody;

(* CaseMoveBody: move body of case right before the case
 *
 * When a case region evaluates to a constant, the body of
 * the executed region ends up as the body of the case.
 * For aesthetic reasons, it's
 * nice to place those instructions immediately prior
 * to the guard.
 *
 * pre: region is not empty
 *)
PROCEDURE CaseMoveBody*(c : Case);
  VAR
    inst, linst : Instruction;
BEGIN
  IF c.instructions.finst # c.instructions THEN
    ASSERT(c.instructions.finst # c.instructions);
    inst := c.instructions.finst;
    linst := c.instructions.binst;
    inst.binst := c.binst;
    linst.finst := c;
    c.binst.finst := inst;
    c.binst := linst;
    c.instructions.finst := c.instructions;
    c.instructions.binst := c.instructions;
    RegionReassociate(c);
  END;
END CaseMoveBody;

(* MergeMoveBody: move body of conditional merge right before the merge
 *
 * When a conditional-merge region is known to always be executed, it
 * is important to move the merged region to the containing
 * region.  For aesthetic reasons, it's
 * nice to place those instructions immediately prior
 * to the guard.
 *
 * pre: m evaluates to TRUE (conditional constant propagation)
 *)
PROCEDURE MergeMoveBody*(m : Merge);
  VAR
    inst, linst : Instruction;
BEGIN
  IF m.instructions.finst # m.instructions THEN
    inst := m.instructions.finst;
    linst := m.instructions.binst;
    inst.binst := m.binst;
    linst.finst := m;
    m.binst.finst := inst;
    m.binst := linst;
    m.instructions.finst := m.instructions;
    m.instructions.binst := m.instructions;
    RegionReassociate(m);
  END;
END MergeMoveBody;

PROCEDURE RegionNewSubRegion*(r : Region; pos : LONGINT; VAR sr : Region);
BEGIN
  sr := NewGuard(ConstGetBool(r, TRUE, pos), GSAOpcode.Gtrue, pos);
  InstructionAppend(r, sr);
END RegionNewSubRegion;

(* AssignToVariable:
 *
 *   Assign to a user-variable or a compiler-generated temporary
 *   but do not do alias analysis
 *)
PROCEDURE AssignToVariable*(r : Region; lhs : Addressable; rhs : Item);
  VAR
    merge : Merge;
    gate : Gate;
    source : Usable;
    exit : Instruction;
    copy : Instruction;
    greg : GlobalRegion;
    op : Operand;
    tname : Types.Name;
BEGIN
  ASSERT((lhs IS Symbol) OR  (* normal symbol *)
         (lhs IS Type) OR    (* anonymous type, heap access, array access *)
         (lhs IS Temporary), (* compiler-generated temp *)
         1024);

  source := rhs.node;
  IF (source IS Symbol) OR (source IS Const) OR (source IS Temporary) THEN
    (*
      Assignment from a variable or a constant is being made.
      To help the compiler and ensure the structure rules of a Gate
      (gate <Merge>, <Instruction>, <Instruction>), a copy is made
      of the original value.
    *)
    copy := InstructionNewCopy(r, source);
    source := copy;
  END;

  ASSERT(source IS Result, 1057); (* Not required for
                                   * the data structures to
                                   * be correct, but it is a nice
                                   * sanity check to ensure that only
                                   * Results will be assigned to
                                   * variables.
                                   *)
  rhs.node := source;
  merge    := r.merge;
  IF merge = NIL THEN
    (*
     *  No Merge exists in the region where instructions are being
     *  output.  This means that there are no control flow issues
     *  which must be resolved.  However, the variable being
     *  assigned may have non-local effects (NLE).
     *
     *  Things which can have non-local effect are:
     *
     *  o global variables
     *  o VAR parameters
     *  o non-local variables (owned by enclosing procedure)
     *
     *  Note that, due to the inverse recursive nature of the GSA building
     *  process (where effects inside merges percolate to the exterior of
     *  the merge), it is only necessary to consider NLE for non-merged
     *  regions because eventually a gate will be created outside of
     *  the merge region and the result of the gate will be assigned
     *  to the gated variable, thus causing the NLE to be checked.
     *)

    greg := RegionFindGlobal(r);
    IF (lhs.definedIn # greg.proc) OR (* non-local *)
       (lhs IS Symbol) &
       ((lhs(Symbol).sym.kind = Symtab.varpar) OR (* varpar OR global
                                                   * OR $result *)
        SymbolIsGlobal((lhs(Symbol).sym))) OR
       IsResult(lhs) THEN

      (* An NLE has occurred such that 'greg' has touched something
       * that does not belong to it.  Add 'lhs to the exit for greg.
       *)

      exit := InstructionExit(greg);
      ASSERT(exit # NIL, 1025); (* every greg has an exit *)
      op := OperandFind(exit, lhs, slSymbol);
      IF op = NIL THEN
        (*
         * lhs has not been set yet outside of a merge region.
         * Add an operand to $exit which indicates the value and set the
         * location field to the non-locally affected variable so that the
         * computed value will be stored in the correct place.
         *)
        OperandAppend(exit, source);
        op := OperandLast(exit);
        OperandSetSymLocation(op, lhs, slSymbol);
        ASSERT(op.def # NIL, 1029);
      ELSE
        (*
         * lhs has already been assigned outside of a merge region;
         * simply replace the operand with the new resultant value.
         * The location attribute should not be harmed by this.
         *)
        OperandReplace(op, source);
      END;
      (* Scan all previously accessed non-local items and insert
       * 'alias' nodes as needed. *)
    END;
  ELSE
    (*
     * A Merge exists for the region where instructions are
     * being output.  This means that control has been split
     * either through a conditional statement or a looping
     * construct.  It is necessary for the gate associated
     * with the variable being assigned to be updated to
     * reflect the proper value of the variable.
     *)
    ASSERT(lhs # NIL, 1031);
    gate := GateGet(merge, r, lhs);
    GateReplaceLastOperand(gate, rhs);
  END;
  lhs.currvalue := source(Usable); (* current value of the symbol now set *)

  (* Set 'lhs' field for nice GSA output for assignments *)
  IF source IS Instruction THEN
    source(Instruction).lhs := lhs;
  END;
END AssignToVariable;

(*
  Resets the symbol table at the end of an IF-section so that variables
  processed in the next section will obtain the last value stored prior
  to the IF beginning

              b := 0;
              IF cond THEN
                a := b + 12;
                b := 15;
  reset here  ELSE
                a := b + 1;  -- must use b as '0', not '15'
              END
*)
PROCEDURE MergeReset*(x : Merge);
  VAR
    u : Operand;
    gate : Gate;
    y : Item;
BEGIN
  u := x.uses.fuses;
  WHILE u # x.uses DO
    IF (u.owner IS Gate) & (u.owner(Gate).var # NIL) THEN
      gate := u.owner(Gate);
      gate.var.currvalue := gate.original;
    END;
    u := u.fuses;
  END;
END MergeReset;

PROCEDURE MergeCommit*(x : Merge; r : Region);
  VAR
    u : Operand;
    gate : Gate;
    y : Item;
    alias : BOOLEAN;
BEGIN
  u := x.uses.fuses;
  WHILE u # x.uses DO
    IF (u.owner IS Gate) & (u.owner(Gate).var # NIL) THEN
      gate := u.owner(Gate);
      InitItem(y);
      GateNormalize(gate);
      (* var-lhs := gate {assign value of gate to associated variable} *)
      y.node := gate;
      AssignToVariable(r, gate.var, y);
    END;
    u := u.fuses;
  END;
  IF x.subcl = GSAOpcode.Gloop THEN
    (* FIXME: instructions appearing in the 'always'
     * region could be prepended to the loop merge
     *)
  END;
END MergeCommit;

PROCEDURE CondMergeSetPaths*(m : CondMerge; true, false : Region);
BEGIN
  m.true := true;
  m.false := false;
END CondMergeSetPaths;

PROCEDURE ResetTempAttributes*(VAR save : TempAttributes);
BEGIN
  save.nofTemps := nofTemps;
  nofTemps := 0;
END ResetTempAttributes;

PROCEDURE RestoreTempAttributes*(old : TempAttributes);
BEGIN
  nofTemps := old.nofTemps;
END RestoreTempAttributes;

(* IsNecessary: determine if input instruction is necessary
 *
 * Necessary instructions can raise exceptions, or be required
 * for further code improvement algorithms.
 *)
PROCEDURE IsNecessary*(i : Instruction) : BOOLEAN;
BEGIN
  CASE i.class OF
  | GSAOpcode.Mregion:
    RETURN i.subcl IN {GSAOpcode.Menter, GSAOpcode.Mexit};

  | GSAOpcode.Mupdate, GSAOpcode.Mmemory:
      RETURN i.subcl IN {GSAOpcode.Minitialize, GSAOpcode.Mstringcopy,
                         GSAOpcode.Marraycopy, GSAOpcode.Mrecordcopy,
                         GSAOpcode.Mnewrecord, GSAOpcode.Mnewarray,
                         GSAOpcode.Mnewdynarray};
  | GSAOpcode.Pnlm:
      RETURN i.subcl IN {GSAOpcode.Pdtor, GSAOpcode.Pctor}

  | GSAOpcode.Ttrap:
    RETURN TRUE;

  | GSAOpcode.Gmisc:
    RETURN i.subcl IN {GSAOpcode.Gcall, GSAOpcode.Gcopy};

  | GSAOpcode.Gsystem:
    RETURN TRUE;

  | GSAOpcode.Gtypedesc:
    RETURN i.subcl IN {GSAOpcode.Ginitrec,
                       GSAOpcode.Ginitarr,
                       GSAOpcode.Ginitdarr};
  ELSE
    RETURN FALSE;
  END;
END IsNecessary;

(** Module initialization *)
PROCEDURE NILGlobalPointers;
BEGIN
END NILGlobalPointers;

PROCEDURE ModuleBegin(FileInfo : Config.SourceInfo) : BOOLEAN;
BEGIN
  NILGlobalPointers;
  nofTemps := 0;
  nofNodes := 0;
  RETURN TRUE;
END ModuleBegin;

PROCEDURE ModuleEnd(FileInfo : Config.SourceInfo) : BOOLEAN;
BEGIN
  NILGlobalPointers;
  RETURN TRUE;
END ModuleEnd;

PROCEDURE Init;
BEGIN
  Config.ControlModule(ModuleBegin, ModuleEnd);
END Init;

BEGIN
  Init;
END O3GSAData.
