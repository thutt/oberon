MODULE Printer;  (*bh, ard 27.11.92  /  kr 23.12. 92 / 03.08.93*)

	IMPORT SYSTEM;

	CONST
		PW = 2336; PH = 3281;
		
	VAR res*: INTEGER; (*0 = done, 1 = not done*)		
		Width*, Height*, Depth*: INTEGER;
		FrameX*, FrameY*, FrameW*, FrameH*: INTEGER;
		Unit*: LONGINT;

	PROCEDURE Open*(name, user: ARRAY OF CHAR; password: LONGINT);
	BEGIN
	END Open;

	PROCEDURE ReplConst*(x, y, w, h: INTEGER);
	BEGIN
	END ReplConst;

	PROCEDURE fontno(name: ARRAY OF CHAR): SHORTINT;
	BEGIN
	END fontno;

	PROCEDURE UseListFont*(VAR name: ARRAY OF CHAR);
	BEGIN
	END UseListFont;

	PROCEDURE String*(x, y: INTEGER; VAR s, fname: ARRAY OF CHAR);
	BEGIN
	END String;

	PROCEDURE ContString*(VAR s, fname: ARRAY OF CHAR);
	BEGIN
	END ContString;

	PROCEDURE ReplPattern*(x, y, w, h, col: INTEGER);
	BEGIN
	END ReplPattern;

	PROCEDURE Line*(x0, y0, x1, y1: INTEGER);
	BEGIN
	END Line;

	PROCEDURE Circle*(x0, y0, r: INTEGER);
	BEGIN
	END Circle;

	PROCEDURE Ellipse*(x0, y0, a, b: INTEGER);
	BEGIN
	END Ellipse;

	PROCEDURE Spline*(x0, y0, n, open: INTEGER; VAR X, Y: ARRAY OF INTEGER);
	BEGIN
	END Spline;

	PROCEDURE Picture*(x, y, w, h, mode: INTEGER; adr: LONGINT);
	BEGIN
	END Picture;

	PROCEDURE Page*(nofcopies: INTEGER);
	BEGIN
	END Page;

	PROCEDURE Close*;
	BEGIN
	END Close;
	
	PROCEDURE UseColor*(red,green,blue : INTEGER);
	BEGIN
	END UseColor;
	

BEGIN
	Width := PW; Height := PH;
	Unit := 3048;
END Printer.Print

