MODULE DisplayFrame;
  IMPORT Display;

  PROCEDURE ReplConst*(F: Display.Frame; col : Display.COLOR; X, Y, W, H : INTEGER; mode: SHORTINT);
  BEGIN Display.SetClip(F.X, F.Y, F.W, F.H); Display.ReplConst(col, X, Y, W, H, mode); Display.ResetClip;
  END ReplConst;

  PROCEDURE Dot*(F: Display.Frame; col : Display.COLOR; X, Y : INTEGER; mode: SHORTINT);
  BEGIN Display.SetClip(F.X, F.Y, F.W, F.H); Display.Dot(col, X, Y, mode); Display.ResetClip;
  END Dot;

  PROCEDURE CopyBlock*(F : Display.Frame; SX, SY, W, H, DX, DY : INTEGER; mode : SHORTINT);
  BEGIN Display.SetClip(F.X, F.Y, F.W, F.H); Display.CopyBlock(SX, SY, W, H, DX, DY, mode); Display.ResetClip;
  END CopyBlock;

  PROCEDURE Line*(F: Display.Frame; col : Display.COLOR; X0, Y0, X1, Y1: INTEGER; mode: SHORTINT);
  BEGIN Display.SetClip(F.X, F.Y, F.W, F.H); Display.Line(col, X0, Y0, X1, Y1, mode); Display.ResetClip;
  END Line;

  PROCEDURE Circle*(F: Display.Frame; col : Display.COLOR; X, Y, R : INTEGER; mode: SHORTINT);
  BEGIN Display.SetClip(F.X, F.Y, F.W, F.H); Display.Circle(col, X, Y, R, mode); Display.ResetClip;
  END Circle;

  PROCEDURE Ellipse*(F: Display.Frame; col : Display.COLOR; X, Y, A, B : INTEGER; mode: SHORTINT);
  BEGIN Display.SetClip(F.X, F.Y, F.W, F.H); Display.Ellipse(col, X, Y, A, B, mode); Display.ResetClip;
  END Ellipse;

  PROCEDURE ReplPattern*
       (    F : Display.Frame;
            col : Display.COLOR; 
            pat : Display.Pattern; 
            X, Y, W, H, X0, Y0 : INTEGER; 
            mode : SHORTINT);
  BEGIN Display.SetClip(F.X, F.Y, F.W, F.H); Display.ReplPattern(col, pat, X0, Y0, W, H, mode); Display.ResetClip;
  END ReplPattern;

  PROCEDURE CopyPattern*
       (    F: Display.Frame; 
            col : Display.COLOR; 
            pat: Display.Pattern; 
            X, Y : INTEGER; 
            mode: SHORTINT);
  BEGIN Display.SetClip(F.X, F.Y, F.W, F.H); Display.CopyPattern(col, pat, X, Y, mode); Display.ResetClip;
  END CopyPattern;

END DisplayFrame.
