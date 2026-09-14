MODULE O3GSAOpcode;

  CONST (* opcode default values *)
    OpcodeClassBegin* = 0;
    UndefClass* = -1;
    UndefSubclass* = -1;

  CONST (* OPCODE CLASS: memory related *)
    Mbegin*  = OpcodeClassBegin;
    Maccess* = Mbegin + 0; (* memory access *)
    Mupdate* = Mbegin + 1; (* memory update *)
    Mmemory* = Mbegin + 2; (* memory allocation, initialization, movement, copying *)
    Mregion* = Mbegin + 3;
    Mend*    = Mbegin + 3 + 1;

  CONST (* OPCODE CLASS: arithmetic *)
    Abegin*   = Mend;
    Aabs*     = Abegin + 0; (* absolute value *)
    Aneg*     = Abegin + 1; (* arithmetic negation (monadic minus) *)
    Aadd*     = Abegin + 2; (* addition operators *)
    Asub*     = Abegin + 3; (* subtraction operators *)
    Adiv*     = Abegin + 4; (* division operators *)
    Amul*     = Abegin + 5; (* multiplication operators *)
    Amod*     = Abegin + 6; (* modulo operators *)
    Aodd*     = Abegin + 7; (* ODD *)
    Anot*     = Abegin + 8; (* boolean operators *)
    Aconvert* = Abegin + 9; (* type conversion/coercion *)
    Aend*     = Abegin + 9 + 1;

  CONST (* OPCODE CLASS: logical shift/rotate *)
    Lbegin*   = Aend;
    Lrol*     = Lbegin + 0; (* rotate left *)
    Lror*     = Lbegin + 1; (* rotate right *)
    Llsl*     = Lbegin + 2; (* logical shift left *)
    Llsr*     = Lbegin + 3; (* logical shift right *)
    Lasl*     = Lbegin + 4; (* arithmetic shift left *)
    Lasr*     = Lbegin + 5; (* arithmetic shift right *)
    Lend*     = Lbegin + 5 + 1;

  CONST (* OPCODE CLASS: hardware memory & direct register access *)
    Hbegin*   = Lend;
    Hget*     = Hbegin + 0; (* SYSTEM.GET *)
    Hput*     = Hbegin + 1; (* SYSTEM.PUT *)
    Hgetreg*  = Hbegin + 2; (* SYSTEM.GET *)
    Hputreg*  = Hbegin + 3; (* SYSTEM.PUT *)
    Hmemr*    = Hbegin + 4; (* SYSTEM.MEMR *)
    Hmemw*    = Hbegin + 5; (* SYSTEM.MEMW *)
    Hend*     = Hbegin + 5 + 1;

  CONST (* OPCODE CLASS: comparison *)
    Cbegin* = Hend;
    Ceql*   = Cbegin + 0; (* equal test *)
    Cneq*   = Cbegin + 1; (* not equal test *)
    Clss*   = Cbegin + 2; (* less test *)
    Cleq*   = Cbegin + 3; (* less or equal test *)
    Cgtr*   = Cbegin + 4; (* greater  test *)
    Cgeq*   = Cbegin + 5; (* greater or equal test *)
    Cend*   = Cbegin + 5 + 1;

  CONST (* OPCODE CLASS: set operations *)
    Sbegin*        = Cend;
    Sdiff*         = Sbegin + 0; (* set / (XOR) *)
    Sunion*        = Sbegin + 1; (* set + (OR) *)
    Ssub*          = Sbegin + 2; (* set - *)
    Sintersection* = Sbegin + 3; (* set * *)
    Sneg*          = Sbegin + 4; (* monadic set - *)
    Sincl*         = Sbegin + 5;
    Sexcl*         = Sbegin + 6;
    Srange*        = Sbegin + 7; (* {x..y} *)
    Selement*      = Sbegin + 8; (* x IN y *)
    Sconvert*      = Sbegin + 9; (* {x} *)
    Send*          = Sbegin + 9 + 1;

  CONST (* OPCODE CLASS: trap *)
    Tbegin* = Send;
    Ttrap*  = Tbegin + 0; (* runtime tests *)
    Tend*   = Tbegin + 0 + 1;

  CONST (* OPCODE CLASS: general *)
    Gbegin*    = Tend;
    Gmisc*     = Gbegin + 0; (* uncategorized *)
    Gsystem*   = Gbegin + 1; (* SYSTEM module functions *)
    Gguard*    = Gbegin + 2; (* guards *)
    Gmerge*    = Gbegin + 3; (* merges *)
    Gtypedesc* = Gbegin + 4; (* type descriptor *)
    Gend*      = Gbegin + 4 + 1;

  CONST (* OPCODE CLASS: pseudo *)
    Pbegin*    = Gend;
    Palias*    = Pbegin + 0;    (* Aliasing instructions *)
    Phwdreg*   = Pbegin + 1;    (* Move to/from hardware register. *)
    Pnlm*      = Pbegin + 2;    (* Model non-local memory (nlm). *)
    Pmisc*     = Pbegin + 3;
    Pend*      = Pbegin + 3 + 1;

  CONST
    OpcodeClassEnd* = Pend;

  (*********** OPCODE SUBCLASSES ***********)

  CONST (* Maccess, Mupdate *)
    Mfield* = 0;    (* (record) $extract-field, $update-field *)
    Melement* = 1;  (* (array)  $extract-element, $update-element *)
    Mderef* = 2;
    Mnonlocal* = 3; (* (global & non-local variables *)
    Mvarparm* = 4;

  CONST (* Mmemory *)
    Madr*         = 0; (* address *)
    Mtbpadr*      = 1;
    Mdynarrlen*   = 2;
    Mheaptag*     = 3;  (* dynamically allocated type tag *)
    Minitialize*  = 4;  (* initialize memory to binary 0 *)
    Mstringcopy*  = 5;  (* string copy *)
    Marraycopy*   = 6;  (* array copy for procedure prolog*)
    Mrecordcopy*  = 7;  (* record copy for procedure prolog *)
    Mnewrecord*   = 8;  (* record allocation *)
    Mnewarray*    = 9;  (* (static) array allocation *)
    Mnewdynarray* = 10; (* (dynamic) array allocation *)

  CONST (* Mregion *)
    Mgreg* = 0;
    Mreg* = 1;
    Mcasereg* = 2;
    Menter* = 3;
    Mexit* = 4;
    Mbody* = 5; (* loop body *)

  CONST (* Arithmetic subclasses, generically named *)
    asS1* = 0; asU1* = 1; (* signed/unsigned 1-byte *)
    asS2* = 2; asU2* = 3; (* signed/unsigned 2-byte *)
    asS4* = 4; asU4* = 5; (* signed/unsigned 4-byte *)
    asR8* = 22; asR4* = 23; (* real 8-byte, 4-byte *)
    asST* = 31; (* string *)

  CONST (* Ttrap *)
    Tindex* = 0;
    Trange* = 1;
    Teguard* = 2;
    Tiguard* = 3;
    Treturn* = 4;
    Tcase* = 5;
    Tassert* = 6;
    Thalt* = 7;
    Twith* = 8;
    Tnil* = 9;

  CONST (* Gmisc *)
    Gcall* = 0;
    Gcopy* = 1;
    Gcap* = 2;

  CONST (* Gsystem *)
    Gbit* = 0; (* SYSTEM.BIT *)
    Gnewblock* = 1; (* SYSTEM.NEW *)
    Gmove* = 2; (* SYSTEM.MOVE (or compiler created move) *)
    Gresetbit* = 3; (* SYSTEM.BITR(adr, bitno) *)
    Gsetbit* = 4;  (* SYSTEM.BITS(adr, bitno) *)
    Gfinalize* = 5; (* SYSTEM.FINALIZE(func) *)
    Gcondcode* = 6;

  CONST (* Gguard *)
    Gtrue* = 0;
    Gfalse* = 1;
    Gcasesgl* = 2; (* AST.SingleCase guard *)
    Gcaseelse* = 3; (* case ELSE guard *)
    Gbackedge* = 4; (* loop backedge; specialization of Gtrue *)
    Gexit* = 5;     (* loop exit; specialization of Gfalse *)

  CONST (* Gmerge *)
    Gif* = 0;  (* if merge *)
    Gcond* = 1; (* conditional merge *)
    Gloop* = 2; (* loop merge *)
    Gcase* = 3; (* case merge *)

  CONST (* Gtypedesc *)
    Ginitrec* = 0; (* initialize record descriptor *)
    Ginitarr* = 1; (* initialize array descriptor *)
    Ginitdarr* = 2; (* initialize dynamic array descriptor *)

  CONST (* Palias *)
    Pnoalias*    = 0;       (* Deliberate {Palias, Pmayalias, Pdoesalias} ordering. *)
    Pmayalias*   = 1;
    Pdoesalias*  = 2;
    Paliasasgn*  = 3;       (* Psuedo assignment of possible alias. *)

  CONST (* Phwdreg *)
    Pmovetoreg*    = 0;           (* Move to hardware register. *)
    Pmovefromreg*  = 1;           (* Move from hardware register. *)

  CONST (* Pmisc *)
    Pgate*   = 0;
    Pimport* = 1;


  CONST (* Pnlm *)
    Pdtor* = 0; (* delete %nlm *)
    Pctor* = 1; (* create %nlm *)


  PROCEDURE validate;
  BEGIN
    (* Do not test instruction classes with SET tests.  Instruction
     * subclasses can be tested with SET instructions, but classes are
     * not designed that way
     *)
    ASSERT(MAX(SET) >= 31, 1026);
  END validate;

BEGIN validate;
END O3GSAOpcode.
