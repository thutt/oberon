(* Copyright (c) 2021, 2022 Logic Magicians Software
 * 
 * Tests that software fault '12' is generated for a set
 * range construction with the low value being larger than the
 * high value.
 *)
MODULE CTBitsetRangeFail;
IMPORT Console;

PROCEDURE create(low, high : INTEGER) : SET;
BEGIN
  RETURN {low..high};
END create;

PROCEDURE Test*;
VAR
  v : SET;
BEGIN
  v := create(12, 0);
END Test;

END CTBitsetRangeFail.
