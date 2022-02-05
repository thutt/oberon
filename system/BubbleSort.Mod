MODULE BubbleSort;

PROCEDURE Bubble(VAR array : ARRAY OF INTEGER);
  VAR swapped: BOOLEAN; i, t: INTEGER; n : LONGINT;
BEGIN
  n := LEN(array);
  REPEAT swapped := FALSE; i := 1;
    WHILE i < n DO
      IF array[i] < array[i - 1] THEN
        t := array[i]; array[i] := array[i - 1]; array[i - 1] := t;
        swapped := TRUE;
      END;
      INC(i);
    END;
  UNTIL ~swapped;
END Bubble;

END BubbleSort.
