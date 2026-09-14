MODULE O3MachineDep; (* Machine Dependent code *)
	IMPORT
		SYSTEM;
		
	PROCEDURE SetRealValues*
			(VAR minR : REAL; minRPat : LONGINT;
			 VAR maxR : REAL; maxRPat : LONGINT;
			 VAR minLR : LONGREAL; minLRL, minLRH : LONGINT;
			 VAR maxLR : LONGREAL; maxLRL, maxLRH : LONGINT);
	
			VAR i : LONGINT;
			
		PROCEDURE SetLongReal(VAR lr : LONGREAL; lo, hi : LONGINT);
		BEGIN SYSTEM.MEMW(SYSTEM.ADR(lr), 0, lo); SYSTEM.MEMW(SYSTEM.ADR(lr), SIZE(LONGINT), hi);
		END SetLongReal;
	
	BEGIN
		minR := SYSTEM.VAL(REAL, minRPat);
		maxR := SYSTEM.VAL(REAL, maxRPat); 
		
		SetLongReal(minLR, minLRL, minLRH); 
		SetLongReal(maxLR, maxLRL, maxLRH);
	END SetRealValues;
	
	(** Hashing *)
	PROCEDURE Hash*(name : ARRAY OF CHAR) : LONGINT;
		VAR i, val : LONGINT; ch : CHAR;

		PROCEDURE Accum(VAR fp : LONGINT; val : LONGINT);
			VAR x : LONGINT;
		BEGIN IF ODD(val) THEN x := fp + val; ELSE x := fp - val; END;
			fp := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, SYSTEM.ROT(x, -1)) / SYSTEM.VAL(SET, val));
		END Accum;

	BEGIN val := 0; i := 0; ch := name[0]; WHILE ch # 0X DO Accum(val, ORD(ch)); INC(i); ch := name[i]; END; RETURN val;
	END Hash;
	
END O3MachineDep.
