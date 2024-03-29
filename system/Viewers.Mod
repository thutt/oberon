MODULE Viewers; (*JG 4.8.93*)

    IMPORT Objects, Display;

    CONST minint = MIN(INTEGER); maxint = MAX(INTEGER);

    TYPE
     Viewer* = POINTER TO ViewerDesc;

     ViewerDesc* = RECORD (Display.FrameDesc)
         state*: INTEGER
     END;

     (*state > 1: displayed
        state = 1: filler
        state = 0: closed
        state < 0: suspended*)

     Track = POINTER TO TrackDesc;

     TrackDesc = RECORD (ViewerDesc)
       under: Display.Frame
     END;

    VAR
      curW*, minH*, DH: INTEGER;
      FillerTrack: Track; FillerViewer, buf: Viewer; (*for closed viewers*)

    PROCEDURE Open* (V: Viewer; X, Y: INTEGER);
      VAR T, u, v: Display.Frame; M: Display.ControlMsg; N: Display.ModifyMsg;
    BEGIN
      IF (V.state = 0) & (X < maxint) THEN
          IF Y > DH THEN Y := DH END;
          T := FillerTrack.next;
          WHILE X >= T.X + T.W DO T := T.next END;
          u := T.dsc; v := u.next;
          WHILE Y > v.Y + v.H DO u := v; v := u.next END;
          IF Y < v.Y + minH THEN Y := v.Y + minH END;
          IF (v.next.Y # 0) & (Y > v.Y + v.H - minH) THEN
            WITH v: Viewer DO
              V.X := T.X; V.W := T.W; V.Y := v.Y; V.H := v.H;
              M.F := NIL; M.id := Display.suspend;
              v.handle(v, M); v.state := 0; buf := v;
              V.next := v.next; u.next := V;
              V.state := 2
            END
          ELSE
            V.X := T.X; V.W := T.W; V.Y := v.Y; V.H := Y - v.Y;
            N.F := v; N.id := Display.reduce;
            N.Y := Y; N.H := v.Y + v.H - Y;
            v.handle(v, N); v.Y := N.Y; v.H := N.H;
            V.next := v; u.next := V;
            V.state := 2
          END
      END;
    END Open;
  
    PROCEDURE Change* (V: Viewer; Y: INTEGER);
      VAR v: Display.Frame; M: Display.ModifyMsg;
    BEGIN
      IF V.state > 1 THEN
       IF Y > DH THEN Y := DH END;
       v := V.next;
       IF (v.next.Y # 0) & (Y > v.Y + v.H - minH) THEN
        Y := v.Y + v.H - minH
      END;
          IF Y > v.Y THEN
        M.F := v; M.id := Display.reduce;
              M.Y := Y; M.H := v.Y + v.H - Y;
              v.handle(v, M); v.Y := M.Y; v.H := M.H;
        V.H := Y - V.Y
      ELSIF Y >= V.Y + minH THEN
        M.F := v; M.id := Display.extend;
              M.Y := Y; M.H := v.Y + v.H - Y;
              v.handle(v, M); v.Y := M.Y; v.H := M.H;
        V.H := Y - V.Y
      END
     END
    END Change;

    PROCEDURE RestoreTrack (S: Display.Frame);
      VAR T, t, v: Display.Frame; M: Display.ControlMsg;
  BEGIN
    WITH S: Track DO
       t := S.next;
        WHILE t.next.X # S.X DO t := t.next END;
        T := S.under;
        WHILE T.next # NIL DO T := T.next END;
        t.next := S.under; T.next := S.next;
        M.F := NIL; M.id := Display.restore;
        REPEAT t := t.next;
          v := t.dsc;
          REPEAT v := v.next; v.handle(v, M);
            WITH v: Viewer DO v.state := - v.state END
          UNTIL v = t.dsc
        UNTIL t = T
     END
     END RestoreTrack;

    PROCEDURE Close* (V: Viewer);
      VAR T, U: Display.Frame; M: Display.ControlMsg; N: Display.ModifyMsg;
    BEGIN
        IF V.state > 1 THEN
            U := V.next; T := FillerTrack;
        REPEAT T := T.next UNTIL V.X < T.X + T.W;
            IF (T(Track).under = NIL) OR (U.next # V) THEN
            M.F := NIL; M.id := Display.suspend;
                V.handle(V, M); V.state := 0; buf := V;
                N.F := U; N.id := Display.extend;
                N.Y := V.Y; N.H := V.H + U.H;
            U.handle(U, N); U.Y := N.Y; U.H := N.H;
          WHILE U.next # V DO U := U.next END;
              U.next := V.next
            ELSE (*close track*)
              M.F := NIL; M.id := Display.suspend;
                V.handle(V, M); V.state := 0; buf := V;
            U.handle(U, M); U(Viewer).state := 0;
          RestoreTrack(T)
            END
        END
     END Close;

    PROCEDURE Recall* ( VAR V: Viewer);
    BEGIN V := buf
    END Recall;

    PROCEDURE This* (X, Y: INTEGER): Viewer;
      VAR T, V: Display.Frame;
    BEGIN
      IF (X < maxint) & (Y < DH) THEN
        T := FillerTrack;
        REPEAT T := T.next; UNTIL X < T.X + T.W;
        V := T.dsc;
        REPEAT V := V.next; UNTIL Y < V.Y + V.H;
        RETURN V(Viewer)
      ELSE RETURN NIL
      END
    END This;

    PROCEDURE Next* (V: Viewer): Viewer;
    BEGIN RETURN V.next(Viewer)
    END Next;

    PROCEDURE Locate* (X, H: INTEGER; VAR fil, bot, alt, max: Display.Frame);
      VAR T, V: Display.Frame;
    BEGIN
      IF X < maxint THEN
        T := FillerTrack;
        REPEAT T := T.next UNTIL X < T.X + T.W;
        fil := T.dsc; bot := fil.next;
        IF bot.next # fil THEN
          alt := bot.next; V := alt.next;
          WHILE (V # fil) & (alt.H < H) DO
            IF V.H > alt.H THEN alt := V END; V := V.next
          END
        ELSE alt := bot
        END;
        max := T.dsc; V := max.next;
      WHILE V # fil DO
          IF V.H > max.H THEN max := V END; V := V.next
        END
      END
    END Locate;

    PROCEDURE InitTrack* (W, H: INTEGER; Filler: Viewer);
      VAR S: Display.Frame; T: Track;
  BEGIN
        IF Filler.state = 0 THEN
          Filler.X := curW; Filler.W := W; Filler.Y := 0; Filler.H := H;
          Filler.state := 1;
          Filler.next := Filler;
        NEW(T);
        T.X := curW; T.W := W; T.Y := 0; T.H := H;
        T.dsc := Filler; T.under := NIL;
          FillerViewer.X := curW + W; FillerViewer.W := maxint - FillerViewer.X;
        FillerTrack.X := FillerViewer.X; FillerTrack.W := FillerViewer.W;
          S := FillerTrack;
            WHILE S.next # FillerTrack DO S := S.next END;
        S.next := T; T.next := FillerTrack;
            curW := curW + W
        END
    END InitTrack;

    PROCEDURE OpenTrack* (X, W: INTEGER; Filler: Viewer);
      VAR newT: Track; S, T, t, v: Display.Frame; M: Display.ControlMsg;
    BEGIN
      IF (X < maxint) & (Filler.state = 0) THEN
        S := FillerTrack; T := S.next;
        WHILE X >= T.X + T.W DO S := T; T := S.next END;
        WHILE X + W > T.X + T.W DO T := T.next END;
        M.F := NIL; M.id := Display.suspend;
        t := S;
        REPEAT t := t.next; v := t.dsc;
          REPEAT v := v.next;
                    WITH v: Viewer DO v.state := -v.state; v.handle(v, M) END
        UNTIL v = t.dsc
      UNTIL t = T;
        Filler.X := S.next.X; Filler.W := T.X + T.W - S.next.X; Filler.Y := 0; Filler.H := DH;
      Filler.state := 1;
      Filler.next := Filler;
      NEW(newT);
      newT.X := Filler.X; newT.W := Filler.W; newT.Y := 0; newT.H := DH;
        newT.dsc := Filler; newT.under := S.next; S.next := newT;
        newT.next := T.next; T.next := NIL
      END
    END OpenTrack;

    PROCEDURE CloseTrack* (X: INTEGER);
      VAR T, V: Display.Frame; M: Display.ControlMsg;
    BEGIN
      IF X < maxint THEN
        T := FillerTrack;
        REPEAT T := T.next UNTIL X < T.X + T.W;
        IF T(Track).under # NIL THEN
          M.F := NIL; M.id := Display.suspend; V := T.dsc;
          REPEAT V := V.next; V.handle(V, M); V(Viewer).state := 0 UNTIL V = T.dsc;
          RestoreTrack(T)
        END
      END
    END CloseTrack;

  PROCEDURE Broadcast (VAR M: Display.FrameMsg);
      VAR F, V: Display.Frame;
  BEGIN M.res := minint; Objects.Stamp(M);
    F := FillerTrack.next;
    WHILE (F # FillerTrack) & (M.res < 0) DO V := F.dsc;
      REPEAT V := V.next; M.dlink := NIL; M.x := 0; M.y := 0; V.handle(V, M)
      UNTIL (V = F.dsc) OR (M.res >= 0) ;
      F := F.next
    END
  END Broadcast;

BEGIN
    DH := Display.Height;
    NEW(FillerViewer);
    FillerViewer.X := 0; FillerViewer.W := maxint; FillerViewer.Y := 0; FillerViewer.H := DH;
    FillerViewer.next := FillerViewer;
    NEW(FillerTrack);
    FillerTrack.X := 0; FillerTrack.W := maxint; FillerTrack.Y := 0; FillerTrack.H := DH;
    FillerTrack.dsc := FillerViewer;
    FillerTrack.next := FillerTrack;
    buf := NIL; curW := 0; minH := 1;
    Display.Broadcast := Broadcast
END Viewers.
