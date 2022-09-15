MODULE SKLDS; (* Symbol Table Dumper *)
IMPORT
  OPM:=SKLMD,
  ST:=SKLST;

	PROCEDURE PadStr(s : ARRAY OF CHAR; pad : INTEGER);
		VAR buf : ARRAY 51 OF CHAR; i : INTEGER; ch : CHAR;
	BEGIN
		IF pad >= LEN(buf) THEN pad := LEN(buf) - 1; END;
		buf[LEN(buf) - 1] := 0X; i := 0; ch := s[0];
		WHILE (i < pad) & (ch # 0X) DO buf[i] := ch; INC(i); ch := s[i]; END;
		WHILE (i < pad) DO buf[i] := ' '; INC(i); END;
		OPM.LogWStr(buf);
	END PadStr;

	PROCEDURE DumpType(t : ST.Type);
	BEGIN
		OPM.LogWNum(t.form, 3); OPM.LogW(' ');
		OPM.LogWNum(t.mno, 3); OPM.LogW(' ');
		IF t.sym # NIL THEN PadStr(t.sym.name^, 15); END;
	END DumpType;

	PROCEDURE DumpSym(VAR info : ST.ProcessScopeInfo);
		VAR sym : ST.Symbol;
	BEGIN
		OPM.LogWNum(sym.kind, 5); OPM.LogW(' '); PadStr(sym.name^, 25);
		DumpType(sym.type);
		OPM.LogWLn;
	END DumpSym;

	PROCEDURE Dump*(scope : ST.SymbolScope);
		VAR info : ST.ProcessScopeInfo;
	BEGIN
		OPM.LogWNum(scope.dsize, 3); OPM.LogW(' '); OPM.LogWStr(scope.name^); OPM.LogWLn;
		ST.ProcessScope(scope, DumpSym, info)
	END Dump;
BEGIN
END SKLDS.
