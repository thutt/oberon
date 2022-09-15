(* Copyright (c) 2021 Logic Magicians Software
 *
 * Test code generation for RETURN statements.
 *)
MODULE CTReturn;
  CONST
    array*      = 15;
    dynarr*      = 16;

  TYPE
    Type* = POINTER TO TypeDesc;
    TypeDesc* = RECORD
      form* : SHORTINT;
    END;

  TYPE
    Array* = POINTER TO ArrayDesc;
    ArrayDesc* = RECORD (TypeDesc)
      of* : Type;
    END;

  (* This is a potential failure because the result of the
   * recursive invocation will be in the register that's needed
   * to satisfy the RETURN statement.
   *)
  PROCEDURE OpenDimensions(type: Type): INTEGER;
  BEGIN
    RETURN OpenDimensions(type(Array).of) + 1;
  END OpenDimensions;

  PROCEDURE Dimensions(type: Type): INTEGER;
  BEGIN
    IF ~(type.form IN {array, dynarr}) THEN RETURN 0;
    ELSE RETURN Dimensions(type(Array).of) + 1;
    END;
  END Dimensions;

  PROCEDURE Test*;
  END Test;

END CTReturn.
