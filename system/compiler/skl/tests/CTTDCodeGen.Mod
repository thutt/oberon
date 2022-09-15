(* Copyright (c) 2021 Logic Magicians Software
 *
 * This module caused the SKL interpreter to fail an assertion
 *  because SFP was being loaded with out-of-bounds value while
 *  the file is being compiled.
 *
 *  It is in the test harness to prevent a regression.
 *)
MODULE CTTDCodeGen;

  TYPE            
    TypeDesc = RECORD END;
    Type = POINTER TO TypeDesc;

  TYPE
    HashTable = POINTER TO ARRAY OF Type;


  PROCEDURE Test*;
  END Test;

END CTTDCodeGen.
