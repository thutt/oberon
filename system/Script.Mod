MODULE Script;	(* RS, Wed, 9-Jun-1993*)

(* ChangeFont only fnt.type = Objects.font
	Fri, 26-Nov-93 Search: trap on no selection
*)

	IMPORT ScriptFrames, Texts, MenuViewers, TextFrames, Oberon, Fonts, Objects, Printer, Display, Styles, Files;

	CONST
		(*MenuStr = "System.Close  System.Copy  System.Grow  Script.NewStyle  Script.Style  Script.Search  Script.Store";*)
		MenuStr = "System.Close  System.Copy  System.Grow  Script.NewStyle  Script.Search  Script.Replace  Script.Store";
		CR  = 0DX;	TAB = 9X;
		MaxPatLen = 32;
		Opt = "/"; Opt0 = "%";	(*option chars*)

		(* print options *)
		pageNo = 0;	onTop = 1;	alter = 2;	header = 3;	notFirst = 4;	

		(* print units *)
		PrtUnit = 3048;
		ScnUnit = 10000;(* 10973;	*)
	
	
		(* print layout *)
(*
		leftX = 290;
		headY = 3300;	topY = 3200;	botY = 300;	pagY = 150;
		pagW = Styles.pageW DIV PrtUnit;
*)

	
	VAR
		W: Texts.Writer;
		sPat: ARRAY MaxPatLen OF CHAR;	(* search pattern [read only] *)
		sTab: ARRAY 256 OF INTEGER;		(* table for Boyer Moore algorithm *)
		sPatLen: INTEGER;	(* number of valid characters in sPat [read only] *)
		rBuf: Texts.Buffer;	(* replace buffer [read only] *)
		lTime: LONGINT;	(* most recent time for sPat and/or rBuf *)
		lastPno: INTEGER;
		printer, ext: ARRAY 32 OF CHAR;

	(* print layout *)
		leftX, headY, topY, botY, pagY, pagW: INTEGER;

	PROCEDURE FocusFrame(): ScriptFrames.Frame;
		VAR M: (*ScriptFrames.Focus*)Oberon.CaretMsg;
	BEGIN M.F := NIL; M.car := NIL; M.id := Oberon.get; Display.Broadcast(M);
		IF (M.car = NIL) OR ~(M.car IS ScriptFrames.Frame) THEN RETURN NIL
		ELSE RETURN M.car(ScriptFrames.Frame)
		END
	END FocusFrame;

	PROCEDURE OpenViewer (name: ARRAY OF CHAR; F: Display.Frame);
		VAR X, Y : INTEGER; V : MenuViewers.Viewer;
	BEGIN
		Oberon.AllocateUserViewer(Oberon.UserTrack(Oberon.Mouse.X), X, Y);
		V := MenuViewers.New(TextFrames.NewMenu(name, MenuStr),  F, TextFrames.menuH, X, Y );
	END OpenViewer;

	PROCEDURE OpenScanner(VAR S: Texts.Scanner; F: TextFrames.Frame);
		VAR M: Oberon.SelectMsg;
	BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") THEN
			IF F # NIL THEN M.time := -1; M.id := Oberon.get; TextFrames.GetSelection(F, M)
			ELSE Oberon.GetSelection(M.text, M.beg, M.end, M.time)
			END;
			IF M.time > 0 THEN Texts.OpenScanner(S, M.text, M.beg); Texts.Scan(S) END
		END
	END OpenScanner;

(* -------- Script commands -------- *)

	PROCEDURE Open*;
	VAR S: Texts.Scanner;
		F: ScriptFrames.Frame; T: Texts.Text;
		name: ARRAY 32 OF CHAR;
	BEGIN OpenScanner(S, NIL);
		IF S.class # Texts.Name THEN name := "Script.Open" ELSE COPY(S.s, name) END;
		NEW(T); Texts.Open(T, name); F := ScriptFrames.NewText(T, 0);
		Texts.Scan(S); F.hide := (S.class = Texts.Char) & (S.c = "/") & (S.nextCh = "n");
		OpenViewer (name, F);
	END Open;

	PROCEDURE Backup (VAR name: ARRAY OF CHAR);
	VAR res, i, j: INTEGER; bak: ARRAY 32 OF CHAR;
	BEGIN
		i := 0; WHILE name[i] # 0X DO bak[i] := name[i]; INC(i) END;
		IF i > 31-4 THEN i := 31-4 END;
		bak[i] := "."; bak[i+1] := "B"; bak[i+2] := "a"; bak[i+3] := "k"; bak[i+4] := 0X;
		Files.Rename(name, bak, res)
	END Backup;

	PROCEDURE Store*;
	(*
		Script.Store from title bar = store text of open viewer (name = document name)
		otherwise store marked viewer
			Script.Store X.Text	(name from parameterlist)
			Script.Store ^	(name from selection)
	*)
	
	VAR
		F: ScriptFrames.Frame;
		par: Oberon.ParList;
		V: Display.Frame;
		S: Texts.Scanner;
		f: Files.File;
		len: LONGINT;
	BEGIN
		Texts.WriteString(W, "Script.Store ");
		par := Oberon.Par; S.s := "";
		IF par.frame = par.vwr.dsc THEN (* command in menu frame *)
			V := par.vwr; MenuViewers.GetName(V(MenuViewers.Viewer), S.s)	(*!*)
		ELSE
			V := Oberon.MarkedViewer(); OpenScanner(S, NIL)
		END;
		IF (V.dsc # NIL) & (V.dsc.next # NIL) & (V.dsc.next IS ScriptFrames.Frame) THEN
			Texts.WriteString(W, S.s); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
			F := V.dsc.next(ScriptFrames.Frame);
			ScriptFrames.Mark(F, -1);
			Backup(S.s); f := Files.New(S.s); Texts.Store(F.text,f,0,len); Files.Register(f);
			ScriptFrames.Mark(F, 1)
		END
	END Store;

	PROCEDURE FindPat(F: ScriptFrames.Frame; pos: LONGINT);
	(* searches pattern sPat beginning at position pos *)
		VAR R: Texts.Reader;	buf: ARRAY MaxPatLen OF CHAR;
			len, lPos: LONGINT; 	n, j: INTEGER;

		PROCEDURE Forward (n: INTEGER);
			VAR m: INTEGER; j: INTEGER;
		BEGIN m := sPatLen - n; j := 0;
			WHILE j # m DO buf[j] := buf[n + j]; INC(j) END;
			WHILE j # sPatLen DO Texts.Read(R, buf[j]); INC(j) END
		END Forward;

	BEGIN
		ScriptFrames.Mark(F, -1);
		len := F.text.len;
		Texts.OpenReader(R, F.text, pos);
		Forward(sPatLen); pos := pos + sPatLen;
		LOOP j := sPatLen;
			REPEAT DEC(j) UNTIL (j < 0) OR (buf[j] # sPat[j]);
			IF (j < 0) OR (pos >= len) THEN EXIT END;
			n := sTab[ORD(buf[sPatLen-1])];
			Forward(n); pos := pos + n
		END;
		IF j < 0 THEN
			ScriptFrames.Neutralize(F);
			IF (pos < ScriptFrames.Pos(F, 0, F.H)) OR (ScriptFrames.Pos(F, F.W, 0) < pos) THEN
				ScriptFrames.Show(F, pos - 200)
			END;
			Oberon.Defocus; ScriptFrames.SetCaret(F, pos);
			ScriptFrames.SetSelection(F, pos - sPatLen, pos); lTime := F.time
		ELSE
			ScriptFrames.Neutralize(F)
		END;
		ScriptFrames.Mark(F, 1)
	END FindPat;
	
	PROCEDURE Search*;
		VAR F: ScriptFrames.Frame;
			R: Texts.Reader;	text: Texts.Text;
			pos, beg, end, time: LONGINT; 	i: INTEGER;
			par: Oberon.ParList;
	BEGIN par := Oberon.Par; F := NIL;
		IF (par.vwr # NIL) & (par.frame = par.vwr.dsc) THEN
			IF par.frame.next IS ScriptFrames.Frame THEN F := par.frame.next(ScriptFrames.Frame) END
		ELSE F := FocusFrame()
		END;
		IF F = NIL THEN RETURN END;	(*###*)
		text := NIL; Oberon.GetSelection(text, beg, end, time);
		IF (time >= 0) & (*(text # NIL) &*) (text.len > 0) & (time > lTime) THEN	(* set search pattern *)
			Texts.OpenReader(R, text, beg);
			i := 0; pos := beg;
			REPEAT Texts.Read(R, sPat[i]); INC(i); INC(pos) UNTIL (i = MaxPatLen) OR (pos = end);
			sPatLen := i; lTime := time;
			i := 0; WHILE i # 256 DO sTab[i] := sPatLen; INC(i) END;
			i := 0; WHILE i # sPatLen - 1 DO sTab[ORD(sPat[i])] := sPatLen - 1 - i; INC(i) END
		END;
		IF F.car THEN pos := F.carLoc.pos ELSE pos := 0 END;
		FindPat(F, pos)
	END Search;

	PROCEDURE replace(): BOOLEAN;
		VAR F: ScriptFrames.Frame;
			R: Texts.Reader;	tBuf: Texts.Buffer;	text: Texts.Text;
			pos, beg, end, time, p, len: LONGINT; 	i: INTEGER;	ch: CHAR;
	BEGIN
		F := FocusFrame();
		IF F = NIL THEN RETURN FALSE END;	(*###*)
		text := NIL; Oberon.GetSelection(text, beg, end, time);
		IF (time >= 0) & (*(text # NIL) &*) (time > lTime) THEN	(* set replace buffer *)
			lTime := time; NEW(rBuf); Texts.OpenBuf(rBuf); Texts.Save(text, beg, end, rBuf)
		END;
		IF ~F.car OR ~ (sPatLen > 0) OR (rBuf = NIL) THEN RETURN FALSE END;	(*###*)
		pos := F.carLoc.pos; p := pos - sPatLen;
		IF p < 0 THEN RETURN FALSE END;	(*###*)
		Texts.OpenReader(R, F.text, p); Texts.Read(R, ch); i := 0;
		WHILE (ch = sPat[i]) & (i < sPatLen) DO Texts.Read(R, ch); INC(i) END;
		IF i = sPatLen THEN
			NEW(tBuf); Texts.OpenBuf(tBuf); Texts.Copy(rBuf, tBuf); len := tBuf.len;
			Texts.Replace(F.text, p, pos, tBuf); pos := p + len
(*
			Texts.Delete(F.text, p, pos); pos := p;
			NEW(tBuf); Texts.OpenBuf(tBuf);
			Texts.Copy(rBuf, tBuf); len := tBuf.len;
			Texts.Insert(F.text, pos, tBuf); pos := pos + len
*)
		END;
		FindPat(F, pos);
		RETURN F.car
	END replace;
	
	PROCEDURE Replace*;
	BEGIN
		IF replace() THEN END
	END Replace;
	
	PROCEDURE ReplaceAll*;
	BEGIN
		WHILE replace() DO END
	END ReplaceAll;

	PROCEDURE Font(name: ARRAY OF CHAR): Fonts.Font;	(*append .Scn.Fnt if necessary*)
		VAR i, j: INTEGER;
	BEGIN i := 0;
		WHILE (name[i] # ".") & (name[i] # 0X) DO INC(i) END;
		IF name[i] = 0X THEN j := 0;
			WHILE ext[j] # 0X DO name[i] := ext[j]; INC(i); INC(j) END;
			name[i] := 0X
		END;
		RETURN Fonts.This(name)
	END Font;

	PROCEDURE ChangeFont*;
	VAR S: Texts.Scanner;
		T: Texts.Text; beg, end, time: LONGINT;
		fnt: Fonts.Font;
	BEGIN OpenScanner(S, NIL);
		IF S.class = Texts.Name THEN
			Oberon.GetSelection(T, beg, end, time); fnt := Font(S.s);
			IF (time >= 0) & (fnt.type = Fonts.font) THEN Texts.ChangeLooks(T, beg, end, {0}, fnt, 0, 0) END
		END
	END ChangeFont;

	PROCEDURE ChangeColor*;
	VAR S: Texts.Scanner;
		T: Texts.Text; col: Display.COLOR; beg, end, time: LONGINT;
	BEGIN OpenScanner(S, NIL);
		IF S.class # Texts.Int THEN col := S.col ELSE col := SHORT(SHORT(S.i)) END;
		Oberon.GetSelection(T, beg, end, time);
		IF time >= 0 THEN Texts.ChangeLooks(T, beg, end, {1}, NIL, col, 0) END
	END ChangeColor;

	PROCEDURE ChangeOffset*;
	VAR S: Texts.Scanner; T: Texts.Text; voff: SHORTINT; beg, end, time: LONGINT;
	BEGIN OpenScanner(S, NIL);
		IF S.class # Texts.Int THEN voff := S.voff ELSE voff := SHORT(SHORT(S.i)) END;
		Oberon.GetSelection(T, beg, end, time);
		IF time >= 0 THEN Texts.ChangeLooks(T, beg, end, {2}, NIL, 0, voff) END
	END ChangeOffset;

	PROCEDURE Recall*;
		VAR M: Oberon.RecallMsg;
	BEGIN M.F := NIL; Display.Broadcast(M)
	END Recall;

	PROCEDURE NewStyle*;
		VAR M : Display.ConsumeMsg;
	BEGIN M.id := Display.integrate; M.res := -1; M.obj := Styles.NewStyle(); M.F := NIL; Display.Broadcast(M)
	END NewStyle;
	
	PROCEDURE SetStyle*;
	VAR M: Styles.ParamMsg;
		style: Styles.Style;
		F: Display.Frame;
	BEGIN F := Oberon.Par.frame;
		IF F IS TextFrames.Frame THEN
			OpenScanner(M.S, F(TextFrames.Frame)); TextFrames.RemoveSelection(F(TextFrames.Frame))
		ELSE OpenScanner(M.S, NIL)
		END;
		Styles.SelStyle(style);
		IF style # NIL THEN M.id := Styles.set; style.handle(style, M) END
	END SetStyle;
	
	PROCEDURE GetStyle*;
	VAR M: Styles.ParamMsg;
		style: Styles.Style;
		F: Display.Frame;
	BEGIN F := Oberon.Par.frame;
		IF F IS TextFrames.Frame THEN
			OpenScanner(M.S, F(TextFrames.Frame)); TextFrames.RemoveSelection(F(TextFrames.Frame))
		ELSE OpenScanner(M.S, NIL)
		END;
		Styles.SelStyle(style);
		IF style # NIL THEN M.T := Oberon.Log; M.id := Styles.get; style.handle(style, M) END
	END GetStyle;

	PROCEDURE Style*;
	VAR V, F: Display.Frame; par: Oberon.ParList;
		M: Display.DisplayMsg;
		S: Texts.Scanner;
	BEGIN par := Oberon.Par; V := NIL;
		IF par.frame = par.vwr.dsc THEN V := par.vwr	(*menu frame*)
		ELSE Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
			IF (S.class = Texts.Char) & (S.c = "*") THEN V := Oberon.MarkedViewer() END
		END;
		IF (V # NIL) & (V.dsc # NIL) & (V.dsc.next # NIL) THEN F := V.dsc.next;
			IF F IS ScriptFrames.Frame THEN
				WITH F: ScriptFrames.Frame DO
					ScriptFrames.Neutralize(F);
					F.hide := ~F.hide; M.F := F; M.id := Display.frame; Display.Broadcast(M)
				END
			END
		END
	END Style;


(* Script.Print server ( * | ^ | name) {option} ~ *)
	PROCEDURE PrintUnit(T: Texts.Text; VAR name: ARRAY OF CHAR; fnt: Fonts.Font; opts: SET; pn0, pnb, pne, copies: INTEGER);
	TYPE
		Line = POINTER TO LineDesc;

		LineDesc = RECORD
			next: Line;
			len: LONGINT;
			w, asr, dsr, h, nSpc: INTEGER;
			eot, brk: BOOLEAN
		END;
(*
	style height
*)

	VAR
		R: Texts.Reader;
		Y, Y0, H, pno: INTEGER;
		eot, pbrk, open: BOOLEAN;
		buf, L: Line;
		style: Styles.Style;
		h0: INTEGER;
		ox, sx, rx: INTEGER;

		PROCEDURE log(ch: CHAR);
		BEGIN Texts.Write(W, ch); Texts.Append(Oberon.Log, W.buf)
		END log;

		PROCEDURE ToPrt(d: INTEGER): INTEGER;
		BEGIN RETURN SHORT(LONG(d) * ScnUnit DIV PrtUnit)
		END ToPrt;
		
		PROCEDURE OpenPrinter();
			VAR retries: INTEGER;
		BEGIN retries := 4;
			Printer.Open(printer, Oberon.User, Oberon.Password);
			WHILE (Printer.res > 0) & (Printer.res < 4) & (retries > 0) DO
				log("-"); Printer.Open(printer, Oberon.User, Oberon.Password); DEC(retries)
			END;
			IF Printer.res = 1 THEN Texts.WriteString(W, " no such printer")
			ELSIF Printer.res = 2 THEN Texts.WriteString(W, " no link")
			ELSIF Printer.res = 3 THEN Texts.WriteString(W, " printer not ready")
			ELSIF Printer.res = 4 THEN Texts.WriteString(W, " no permission")
			END;
(*
			IF Printer.FrameX > leftX THEN leftX := Printer.FrameX END;	(*adjust sizes*)
			IF Printer.FrameY > pagY THEN pagY := Printer.FrameY + ToPrt(fnt.height); botY := pagY + 150 END;
			IF Printer.FrameW < pagW THEN pagW := Printer.FrameW END;
			IF Printer.FrameY + Printer.FrameH < headY THEN
				headY := Printer.FrameY + Printer.FrameH - ToPrt(fnt.height); topY := headY - 100
			END
*)
		END OpenPrinter;

		PROCEDURE InitFormatterPrt(T: Texts.Text; VAR L: Line);
		BEGIN NEW(L); ScriptFrames.FirstLine(T, L.w, L.asr, L.dsr, L.nSpc, L.len, L.brk, L.eot); L.h := L.asr+L.dsr;
			style := Styles.defStyle
		END InitFormatterPrt;

		PROCEDURE FormatLinePrt(VAR L: Line);
		BEGIN NEW(L); ScriptFrames.NextLine(L.w, L.asr, L.dsr, L.nSpc, L.len, L.brk, L.eot); L.h := L.asr+L.dsr
		END FormatLinePrt;

		PROCEDURE FrameDsr(F: Display.Frame): INTEGER;
			VAR B: Objects.AttrMsg;
		BEGIN B.dlink := NIL; B.i := 0; Objects.Stamp(B);
			B.res := -1; B.id := Objects.get; B.name := "LineupHY"; F.handle(F, B);
			RETURN ToPrt(SHORT(B.i))
		END FrameDsr;

		PROCEDURE ChW(fnt: Fonts.Font; ch: CHAR): INTEGER;
		VAR obj: Objects.Object; unit: LONGINT;
		BEGIN Styles.MetricFnt(fnt, unit, fnt); fnt.GetObj(fnt, ORD(ch), obj);
			IF fnt.type = Fonts.metric THEN RETURN obj(Fonts.Char).dx
			ELSE RETURN SHORT(unit*obj(Fonts.Char).dx DIV PrtUnit)
			END
		END ChW;

		PROCEDURE print(pno, pnb, pne: INTEGER): BOOLEAN;
		BEGIN RETURN (pnb <= pno) & (pno < pne)
		END print;
	

		PROCEDURE Offsets(L: Line; VAR ox, sx, rx: INTEGER);
		VAR dw: INTEGER;
		BEGIN
			ox := SHORT(style.left DIV PrtUnit); sx := 0; rx := 0;
			dw := SHORT(style.paraW DIV PrtUnit) - L.w;
			IF Styles.left IN style.opts THEN
				IF (Styles.right IN style.opts) & ~L.brk & (L.nSpc > 0) THEN
					sx := dw DIV L.nSpc; rx := dw MOD L.nSpc
				END
			ELSE
				IF Styles.right IN style.opts THEN INC(ox, dw) ELSE INC(ox, dw DIV 2) END
			END
		END Offsets;

		PROCEDURE PrintFrame(G: Display.Frame; X, Y, pno: INTEGER);	(*handles big frames*)
		VAR M: Display.PrintMsg;
		BEGIN M.res := -1; M.id := Display.view; M.pageno := pno; M.dlink := NIL;
			M.x := X; M.y := Y - FrameDsr(G); Objects.Stamp(M);
			IF M.x = leftX THEN
				IF ToPrt(G.W) > pagW THEN DEC(M.x, (ToPrt(G.W)-pagW) DIV 2) END;	(*!*)
				IF (M.y < 100) OR (M.y + ToPrt(G.H) > topY) THEN M.y := 100 END	(*!*)
			END;
			G.dlink := NIL; M.F := G; G.handle(G, M)	(*G.dlink : HACK*)
		END PrintFrame;

		PROCEDURE PrintLine(VAR R: Texts.Reader; X, Y, pno, sx, rx: INTEGER; len: LONGINT; VAR pbrk: BOOLEAN);	(*X, Y: baseline*)
		VAR
			buf: ARRAY 256 OF CHAR;
			pos, ddX, unit: LONGINT;
			obj: Objects.Object; G: Display.Frame;
			lib: Objects.Library;
			mlib: Fonts.Font;
			k, x, dx, dY, dX, X0, voff, asr, offX : INTEGER; col: Display.COLOR;
			ch: CHAR;
	
			PROCEDURE Out;
			BEGIN
				IF (k > 0) & print(pno, pnb, pne) THEN buf[k] := 0X; Printer.String(X0, Y + dY, buf, lib.name) END; k := 0
			END Out;
	
			PROCEDURE UseColor(col: Display.COLOR);
			VAR r, g, b: INTEGER;
			BEGIN Display.GetColor(col, r, g, b); Printer.UseColor(r, g, b)
			END UseColor;

		BEGIN
			lib := NIL; col := -1; k := 0; pos := 0; pbrk := FALSE;
			x := 0; X0 := X; offX := X;
			WHILE pos # len DO
				Texts.Read(R, ch); INC(pos);
				IF R.lib # NIL THEN
					IF (lib # R.lib) OR (voff # R.voff) OR (col # R.col) THEN Out; X0 := X;
						IF col # R.col THEN col := R.col; UseColor(col) END;
						lib := R.lib; voff := R.voff; dY := 0;
						IF lib IS Fonts.Font THEN
							dY := ToPrt(lib(Fonts.Font).height)*voff DIV 100; Styles.MetricFnt(lib(Fonts.Font), unit, mlib)
						END;
					END;
					lib.GetObj(lib, ORD(ch), obj);
					IF obj IS Fonts.Char THEN dx := obj(Fonts.Char).dx;
						mlib.GetObj(mlib, ORD(ch), obj); dX := obj(Fonts.Char).dx;
						IF mlib.type # Fonts.metric THEN dX := SHORT(unit*dX DIV PrtUnit) END;
						IF (ch = " ") & ((sx # 0) OR (rx # 0)) THEN Out;
							INC(dX, sx); IF rx > 0 THEN INC(dX); DEC(rx) END;
							INC(X, dX); X0 := X
						ELSIF ch = TAB THEN Out; Styles.Tab(style, lib(Fonts.Font), x, LONG(X-offX)*PrtUnit, dx, ddX);
							INC(X, SHORT(ddX DIV PrtUnit)); X0 := X
						ELSIF ch >= " " THEN buf[k] := ch; INC(k); INC(X, dX)
						ELSIF (ch =1FX) & (pos = len) THEN buf[k] := "_"; INC(k)	(*hyph*)
						END;
					ELSE	(*object*)
						IF obj IS Styles.Style THEN style := obj(Styles.Style); pbrk := Styles.break IN style.opts; RETURN END;
						IF obj IS Display.Frame THEN G := obj(Display.Frame); dx := G.W; dX := ToPrt(dx);
							IF print(pno, pnb, pne) THEN PrintFrame(G, X, Y+dY+ToPrt((voff*G.H) DIV 100), pno); col := -1 END;
							INC(X, dX); X0 := X
						END
					END;
					INC(x, dx)
				END
			END;
			Out
		END PrintLine;


		PROCEDURE PrintNum(x, y, n: INTEGER; fnt: Fonts.Font; right: BOOLEAN);
		VAR
			s: ARRAY 8 OF CHAR;
			i, w, k: INTEGER;
		BEGIN i := 7;
			REPEAT s[i] := CHR(n MOD 10 + 30H); DEC(i); n := n DIV 10 UNTIL n = 0;
			k := 0; w := 0;
			WHILE i < 7 DO INC(i); s[k] := s[i]; w := w + ChW(fnt, s[k]); INC(k) END; s[k] := 0X;
			IF right THEN DEC(x, w) END;
			Printer.String(x, y, s, fnt.name)
		END PrintNum;

		PROCEDURE PageHeader(VAR title: ARRAY OF CHAR; pn: INTEGER; opts: SET);
		VAR
			y, i, w: INTEGER;
			F: Display.Frame;
		BEGIN
			IF ~print(pn, pnb, pne) THEN RETURN END;
			Printer.UseColor(0, 0, 0);	(*black*)
			IF header IN opts THEN (* only if (pageNo IN opts) & (onTop IN opts) *)
				IF (pageNo IN opts) & (onTop IN opts) & (alter IN opts) & ~ODD(pn) THEN	(* place header right adjusted *)
					i := 0; w := 0; WHILE title[i] # 0X DO w := w + ChW(fnt, title[i]); INC(i) END;
					Printer.String(leftX + pagW - w, headY, title, fnt.name)
				ELSE
					Printer.String(leftX, headY, title, fnt.name)
				END
			END;
			IF pageNo IN opts THEN
				IF onTop IN opts THEN y := headY ELSE y := pagY END;
				IF (alter IN opts) & ~ODD(pn) THEN PrintNum(leftX, y, pn, fnt, FALSE)
				ELSE PrintNum(leftX + pagW, y, pn, fnt, TRUE)
				END
			END
		END PageHeader;

		PROCEDURE Empty(L: Line): BOOLEAN;
		BEGIN RETURN L.brk & (L.len = 1)
		END Empty;
	
		PROCEDURE Title(L0, L: Line): BOOLEAN;	(*L is Title*)
		BEGIN RETURN L.brk & (L.len > 1) & L0.brk & (L0.len = 1)
		END Title;

		PROCEDURE Page(nextL: Line; VAR Y: INTEGER);
		BEGIN pbrk := FALSE;	(*not really needed*)
			IF print(pno, pnb, pne) THEN Printer.Page(copies); log(".") END;
			IF nextL # NIL THEN Y := topY; INC(pno); PageHeader(name, pno, opts) END
		END Page;

		PROCEDURE Flush(L: Line; Y: INTEGER; VAR h0: INTEGER);
		VAR ox, sx, rx: INTEGER;
		BEGIN	(*print buffer upto L (excl) or page break*)
			WHILE (buf # L) & ~pbrk DO h0 := buf.h;
				Offsets(buf, ox, sx, rx);
				PrintLine(R, leftX+ox, Y-buf.asr, pno, sx, rx, buf.len, pbrk); DEC(Y, buf.h); buf := buf.next
			END;
			IF ~pbrk THEN h0 := 0 END
		END Flush;

		PROCEDURE CompletePage(L: Line; VAR Y: INTEGER);
		VAR h0: INTEGER;
		BEGIN Flush(L, Y, h0); Page(L, Y); DEC(Y, h0)
		END CompletePage;

		PROCEDURE CompletePage0(VAR L: Line; VAR Y: INTEGER);
		VAR h0: INTEGER;
		BEGIN Flush(L, Y, h0);
			(*here*)
			IF ~pbrk THEN	(*skip empty lines on top of page*)
				WHILE Empty(L) & ~L.eot & ~pbrk DO h0 := L.h;
					PrintLine(R, 0, 0, pno, 0, 0, L.len, pbrk); FormatLinePrt(L)
				END;
				(*~Empty OR pbrk*)
				buf := L
			END;
			Page(L, Y); DEC(Y, h0)
		END CompletePage0;

		PROCEDURE CompletePage1;	(*end of doc*)
			VAR h0: INTEGER;
		BEGIN REPEAT Flush(NIL, Y, h0); Page(buf, Y); DEC(Y, h0) UNTIL buf = NIL
		END CompletePage1;

		PROCEDURE ResetBuf(VAR L: Line; VAR Y0: INTEGER);
		VAR L0: Line; i: INTEGER;
		BEGIN L0 := buf; Y0 := topY-L0.h; i := 1;
			WHILE L0 # L DO L0 := L0.next; DEC(Y0, L0.h); INC(i) END;
			WHILE ~L.eot & (i < 5) DO
				FormatLinePrt(L.next); L := L.next; DEC(Y0, L.h);
				IF Y0 < botY THEN CompletePage0(L, Y); Y0 := topY-L.h; i := 0 END;	(*!*)
				INC(i)
			END
		END ResetBuf;

		PROCEDURE PageBreak(VAR L: Line; VAR Y: INTEGER);
		VAR L0, L1: Line;
		BEGIN	(*L goes to next page*)
			L0 := buf.next; L1 := L0.next;
			IF Title(buf, L0) & Empty(L1) THEN CompletePage(L0, Y)	(*Title at L0*)
			ELSIF Title(L0, L1) THEN CompletePage(L1, Y)	(*Title at L1*)
			ELSE L0 := L1; L1 := L0.next;
				(*IF Title(L0, L1) OR ~L1.brk & (L.brk OR L0.brk) THEN CompletePage(L1, Y)	break before L1*)
				IF Title(L0, L1) OR ~L1.brk & L0.brk THEN CompletePage(L1, Y)	(*Title OR first 2 lines of para*)
				ELSIF ~L1.brk & L.brk THEN	(*last 2 lines of para*)
					IF buf.next.brk & ~L0.brk THEN CompletePage(L0, Y)	(*3 lines para at once*)
					ELSE CompletePage(L1, Y)	(*last 2 lines of para*)
					END
				ELSE
					CompletePage0(L, Y)	(*normal break at L*)
				END
			END
		END PageBreak;

	BEGIN Texts.WriteString(W, name);
		IF T.len > 0 THEN Texts.WriteString(W, " printing"); Texts.Append(Oberon.Log, W.buf);
			InitFormatterPrt(T, buf); Texts.OpenReader(R, T, 0); open := FALSE;
			L := buf; Y := topY; ResetBuf(L, Y0); pno := pn0; pbrk := FALSE;
			REPEAT
				IF ~open & (pno >= pnb) THEN
					OpenPrinter(); open := TRUE;
					IF Printer.res # 0 THEN RETURN END;
					IF (pno > pn0) OR ~(notFirst IN opts) THEN PageHeader(name, pno, opts) END
				END;
				h0 := buf.h;	(*save height for explicit page break (gap)*)
				Offsets(buf, ox, sx, rx);
				PrintLine(R, leftX+ox, Y-buf.asr, pno, sx, rx, buf.len, pbrk); DEC(Y, buf.h); buf := buf.next;
				IF pbrk THEN Page(buf, Y); ResetBuf(L, Y0); DEC(Y, h0); DEC(Y0, h0) END;	(*explicit*)
				IF ~L.eot THEN
					FormatLinePrt(L.next); L := L.next; DEC(Y0, L.h);
					IF Y0 < botY THEN
						PageBreak(L, Y); ResetBuf(L, Y0);
						L.eot := L.eot OR (pno >= pne)
					END
				END
			UNTIL L.eot;
			CompletePage1;
			lastPno := pno;
			Printer.Close
		ELSE
			Texts.WriteString(W, " not found"); Texts.Append(Oberon.Log, W.buf)
		END
	END PrintUnit;

	PROCEDURE Options(VAR S: Texts.Scanner; VAR fnt: Fonts.Font; VAR opts: SET; VAR pn0, pnb, pne, copies: INTEGER);
	CONST
		pageNo = 0;	onTop = 1;	alter = 2;	header = 3;	notFirst = 4;
	VAR
		i, line: INTEGER;
	(* /h header (file name & date)
		/c 0..9
		/p[a][t][f][c] [number] alternate/top
		/r number [number] range
		/f name
	*)
	BEGIN
		opts := {}; pnb := MIN(INTEGER); pne := MAX(INTEGER); copies := 1; pn0 := 0; fnt := Fonts.Default;	(*init*)
		line := S.line;
		WHILE (S.class = Texts.Char) & ((S.c = Opt) OR (S.c = Opt0)) & (S.line = line) DO
			Texts.Scan(S);
			IF (S.line = 0) & (S.class = Texts.Name) THEN
				IF S.s[0] = "h" THEN INCL(opts, header); Texts.Scan(S)	(*header*)
				ELSIF S.s[0] = "c" THEN	(*copies*)
					Texts.Scan(S); IF S.class = Texts.Int THEN copies := SHORT(S.i); Texts.Scan(S) END
				ELSIF S.s[0] = "r" THEN	(*range*)
					Texts.Scan(S); IF S.class = Texts.Int THEN pnb := SHORT(S.i); Texts.Scan(S) END;
					IF S.class = Texts.Int THEN pne := SHORT(S.i); Texts.Scan(S) END
				ELSIF S.s[0] = "f" THEN	(*font*)
					Texts.Scan(S); IF S.class = Texts.Name THEN fnt := Font(S.s) END
				ELSIF S.s[0] = "u" THEN	(*US letter*)
					topY := 2900; headY := topY + 100
				ELSIF S.s[0] = "p" THEN	(*page numbering*)
					INCL(opts, pageNo); i := 1;
					WHILE i < S.len DO
						IF S.s[i] = "a" THEN	INCL(opts, alter)
						ELSIF S.s[i] = "t" THEN INCL(opts, onTop)
						ELSIF S.s[i] = "f" THEN INCL(opts, notFirst)
						ELSIF S.s[i] = "c" THEN pn0 := lastPno+1	(*continuous*)
						END;
						INC(i)
					END;
					Texts.Scan(S);
					IF S.class = Texts.Int THEN pn0 := SHORT(S.i); Texts.Scan(S) END
				END
			END
		END
	END Options;

(* Script.Print Pluto (^ | * [opts] | {name [opts]}) *)
PROCEDURE Print*;
VAR
	S: Texts.Scanner;
	V: Display.Frame;
	F: ScriptFrames.Frame;
	title: ARRAY 32 OF CHAR;
	T: Texts.Text; beg, end, time: LONGINT;

	PROCEDURE PrintText(T: Texts.Text; title: ARRAY OF CHAR; VAR S: Texts.Scanner);
	VAR opts: SET; pn0, pnb, pne, copies: INTEGER; fnt: Fonts.Font;
	BEGIN
		leftX := 290; pagW := Styles.pageW DIV PrtUnit;	(*reset default print metrics*)
		headY := 3300; topY := 3200; botY := 300; pagY := 150;
		Texts.Scan(S); Options(S, fnt, opts, pn0, pnb, pne, copies);
		IF T = NIL THEN NEW(T); Texts.Open(T, title) END;
		PrintUnit(T, title, fnt, opts, pn0, pnb, pne, copies)
	END PrintText;

BEGIN
	Texts.WriteString(W, "Script.Print ");
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
	IF S.class = Texts.Name THEN COPY(S.s, printer);
		Texts.WriteString(W, printer); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
(*	Printer.Open(S.s, Oberon.User, Oberon.Password);
		IF Printer.res = 0 THEN
*)
			Texts.Scan(S);
			IF S.class = Texts.Char THEN
				IF S.c = "*" THEN V := Oberon.MarkedViewer();
					IF (V.dsc # NIL) & (V.dsc.next # NIL) & (V.dsc.next IS ScriptFrames.Frame) THEN
						F := V.dsc.next(ScriptFrames.Frame);
						MenuViewers.GetName(V(MenuViewers.Viewer), title);
						ScriptFrames.Mark(F, -1); PrintText(F.text, title, S); ScriptFrames.Mark(F, 1)
					END
				ELSIF S.c = "^" THEN Oberon.GetSelection(T, beg, end, time);
					IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S);
						IF S.class = Texts.Name THEN PrintText(NIL, S.s, S) END
					END
				END
			ELSE
				WHILE S.class = Texts.Name DO PrintText(NIL, S.s, S); Texts.WriteLn(W) END
			END;
			(*Printer.Close
		ELSE
			IF Printer.res = 1 THEN Texts.WriteString(W, " no such printer")
			ELSIF Printer.res = 2 THEN Texts.WriteString(W, " no link")
			ELSIF Printer.res = 3 THEN Texts.WriteString(W, " printer not ready")
			ELSIF Printer.res = 4 THEN Texts.WriteString(W, " no permission")
			END
		END*)
	ELSE Texts.WriteString(W, " no printer specified")
	END;
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END Print;



BEGIN
	Texts.OpenWriter(W); lastPno := 0;
	ext := ".Scn.Fnt"
END Script.
