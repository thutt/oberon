(* Copyright (c) 2021 Logic Magicians Software
 *)
MODULE CTSetCtor;
IMPORT Console;

CONST (* compiler options: *)
  InxChk = 0;  (* index check on *)
  OvflChk = 1;  (* overflow check on *)
  RanChk = 2;  (* range check on *)
  TypChk = 3;  (* type check on *)
  NewSF = 4;  (* generation of new symbol file allowed *)
  ExtSF = 5;  (* extension of old symbol file allowed *)
  PtrInit = 6;  (* pointer initialization *)
  Assert = 7;  (* assert evaluation *)
  FindPC = 8;  (* find text position of breakpc *)
  OptPtrChk = 9; (* NIL pointer deref check (explicit & type guard) *)
  OptDumpNode = 10; (* when enabled, dumps out the AST *)
  OptBanner = 11; (* OptBanner IN options => print banner & exit *)
  OptHashStats = 12; (* HashStats IN options => print hash table statistics *)
  DefaultOptions = {InxChk, RanChk, TypChk, PtrInit, Assert, OptPtrChk};  (* default options *)

TYPE
  Const = POINTER TO ConstDesc;
  ConstDesc = RECORD
    set : SET;
  END;

  Node = POINTER TO NodeDesc;
  NodeDesc = RECORD
    val : Const;
  END;

PROCEDURE Construct(VAR s : SET);
  VAR x : Node;
BEGIN
  s := DefaultOptions; (* Generate: lwi 2cdH, R27 *)
  NEW(x);
  NEW(x.val);
  x.val.set := s;
END Construct;

PROCEDURE Test*;
  VAR
    s : SET;
BEGIN
  Construct(s);
  Console.Set(s);
END Test;
END CTSetCtor.
