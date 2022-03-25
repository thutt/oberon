MODULE CTStrings;


(* #---------  line lenght for this file: 100 characters  -------------------------------------# *)


IMPORT  Console, Strings;


(*---------------------------------------------------------------------------*)
PROCEDURE spc;                           BEGIN Console.Ch( " " );         END spc;
PROCEDURE lf;                            BEGIN Console.Ln;                END lf;
PROCEDURE cprint( c: CHAR );             BEGIN Console.Ch( c );           END cprint;
PROCEDURE sprint( str: Strings.String ); BEGIN Console.Str( str^ );       END sprint;
PROCEDURE mprint( s: ARRAY OF CHAR);     BEGIN Console.Str( s );          END mprint;
PROCEDURE bprint( b: BOOLEAN );          BEGIN Console.Bool( b ); spc;    END bprint;
PROCEDURE iprint( i: LONGINT );          BEGIN Console.Int( i,8 ); spc;   END iprint;

PROCEDURE astr( s: ARRAY OF CHAR ): Strings.String;
BEGIN
  RETURN Strings.Create( s );
END astr;

PROCEDURE IsDigit(c: CHAR): BOOLEAN;
BEGIN
  RETURN (c >= "0") & (c <= "9")
END IsDigit;


(*---------------------------------------------------------------------------*)
PROCEDURE tString;
VAR
 pos, val: LONGINT;
 s: ARRAY 32 OF CHAR;
 str, p,q : Strings.String;
 done, b: BOOLEAN;
 here: INTEGER;
BEGIN


  (*---------------------------------*)
  str := Strings.Empty();      ASSERT( 1 = LEN( str^ ));
  str := Strings.Create("");   ASSERT( 1 = LEN( str^ ));
  str := Strings.New( 0,"X");  ASSERT( 1 = LEN( str^ ));

  ASSERT( 0 = Strings.Length( Strings.Empty()) );
  ASSERT( 0 = Strings.Length( Strings.Create( "")));
  ASSERT( 2 = Strings.Length( Strings.Create( "01")));
  ASSERT( 0 = Strings.Length( Strings.New( 0, "X")));
  ASSERT( 2 = Strings.Length( Strings.New( 2, "X")));

  str := astr( "" );           ASSERT( 1 =  LEN( str^ ), 4200);
  str := astr( " " );          ASSERT( 2 =  LEN( str^ ), 4201);
  str := astr( "01234" );      ASSERT( 6 =  LEN( str^ ), 4202);


  (*---------------------------------*)
  p := astr( "0123456789" );
  q := Strings.Sub( p,3,0 );  ASSERT( q^ = "" );
  q := Strings.Sub( p,0,2 );  ASSERT( q^ = "01" );
  q := Strings.Sub( p,3,2 );  ASSERT( q^ = "34" );
  q := Strings.Sub( p,8,2 );  ASSERT( q^ = "89" );
  q := Strings.Sub( p,9,2 );  ASSERT( q^ = "9" );
  q := Strings.Sub( p,10,2 ); ASSERT( q^ = "" );
  q := Strings.Sub( p,11,2 ); ASSERT( q^ = "" );
  q := Strings.Sub( p,110,2 );ASSERT( q^ = "" );
  q := Strings.Sub( p,8,200 );ASSERT( q^ = "89" );

  q := Strings.Head( p,0 );    ASSERT( q^ = "", 4210 );
  q := Strings.Head( p,3 );    ASSERT( q^ = "012", 4211 );
  q := Strings.Head( p,10 );   ASSERT( q^ = "0123456789", 4212 );
  q := Strings.Head( p,30);    ASSERT( q^ = "0123456789", 4213 );

  q := Strings.Tail( p,0 );    ASSERT( q^ = "" );
  q := Strings.Tail( p,3 );    ASSERT( q^ = "789" );
  q := Strings.Tail( p,10 );   ASSERT( q^ = "0123456789" );
  q := Strings.Tail( p,100 );  ASSERT( q^ = "0123456789" );

  q := Strings.Drop( p,0 );    ASSERT( q^ = "0123456789" );
  q := Strings.Drop( p,3 );    ASSERT( q^ = "3456789" );
  q := Strings.Drop( p,30 );   ASSERT( q^ = "" );

  q := Strings.DropTail( p,0 );ASSERT( q^ = "0123456789" );
  q := Strings.DropTail( p,3 );ASSERT( q^ = "0123456" );
  q := Strings.DropTail( p,30);ASSERT( q^ = "" );

  q := Strings.Append( astr( ""        ), astr( ""        ));    ASSERT( q^ = ""  );
  q := Strings.Append( astr( "0"       ), astr( ""        ));    ASSERT( q^ = "0"  );
  q := Strings.Append( astr( ""        ), astr( "a"       ));    ASSERT( q^ = "a"  );
  q := Strings.Append( astr( "0123"    ), astr( "abcd"    ));    ASSERT( q^ = "0123abcd"  );

  q := Strings.Insert( astr( "0123"    ), astr( "abcd"    ), -1);    ASSERT( q  = NIL  );
  q := Strings.Insert( astr( "0123"    ), astr( "abcd"    ),  0);    ASSERT( q^ = "abcd0123"  );
  q := Strings.Insert( astr( "0123"    ), astr( "abcd"    ),  1);    ASSERT( q^ = "0abcd123"  );
  q := Strings.Insert( astr( "0123"    ), astr( "abcd"    ),  2);    ASSERT( q^ = "01abcd23"  );
  q := Strings.Insert( astr( "0123"    ), astr( "abcd"    ),  3);    ASSERT( q^ = "012abcd3"  );
  q := Strings.Insert( astr( "0123"    ), astr( "abcd"    ),  4);    ASSERT( q^ = "0123abcd"  );
  q := Strings.Insert( astr( "0123"    ), astr( "abcd"    ),  5);    ASSERT( q = NIL  );
  q := Strings.Insert( astr( ""        ), astr( ""        ),  0);    ASSERT( q^ = ""  );
  q := Strings.Insert( astr( ""        ), astr( "a"       ),  0);    ASSERT( q^ = "a"  );
  q := Strings.Insert( astr( "0"       ), astr( ""        ),  0);    ASSERT( q^ = "0"  );
  q := Strings.Insert( astr( "0"       ), astr( ""        ),  1);    ASSERT( q^ = "0"  );
  q := Strings.Insert( astr( "012"     ), astr( ""        ),  1);    ASSERT( q^ = "012");

  q := Strings.Delete( astr( ""), 0,0 );         ASSERT( q^ = "", 4230 );
  q := Strings.Delete( astr( ""), 0,100 );       ASSERT( q^ = "", 4231 );
  q := Strings.Delete( astr( "0"), 0,0 );        ASSERT( q^ = "0", 4232 );
  q := Strings.Delete( astr( "0"), 0,100 );      ASSERT( q^ = "", 4233 );
  q := Strings.Delete( astr( "012345"), 0,0 );   ASSERT( q^ = "012345", 4234 );

  q := Strings.Delete( astr( "01234"), -1,2 );   ASSERT( q  = NIL,     4235 );
  q := Strings.Delete( astr( "01234"),  0,-1 );  ASSERT( q^ = "01234", 4235 );
  q := Strings.Delete( astr( "01234"),  0, 0 );  ASSERT( q^ = "01234", 4235 );
  q := Strings.Delete( astr( "01234"),  0, 1 );  ASSERT( q^ = "1234",  4235 );
  q := Strings.Delete( astr( "01234"),  0,2 );   ASSERT( q^ = "234",   4236 );
  q := Strings.Delete( astr( "01234"),  1,2 );   ASSERT( q^ = "034",   4237 );
  q := Strings.Delete( astr( "01234"),  2,2 );   ASSERT( q^ = "014",   4238 );
  q := Strings.Delete( astr( "01234"),  3,2 );   ASSERT( q^ = "012",   4239 );
  q := Strings.Delete( astr( "01234"),  4,2 );   ASSERT( q^ = "0123",  4240 );
  q := Strings.Delete( astr( "01234"),  5,2 );   ASSERT( q^ = "01234", 4241 );
  q := Strings.Delete( astr( "01234"),  6,2 );   ASSERT( q^ = "01234", 4242 );
  q := Strings.Delete( astr( "01234"),  600,2 ); ASSERT( q^ = "01234", 4243 );

        
  (*---------------------------------*)
  ASSERT( Strings.IsEqual( astr( "" ),      astr( "" ))        = TRUE,   4240 );
  ASSERT( Strings.IsEqual( astr( "1" ),     astr( "1" ))       = TRUE,   4241 );
  ASSERT( Strings.IsEqual( astr( "1" ),     astr( "2" ))       = FALSE,  4242 );
  ASSERT( Strings.IsEqual( astr( "1234" ),  astr( "123" ))     = FALSE,  4243 );
  ASSERT( Strings.IsEqual( astr( "123" ),   astr( "1234" ))    = FALSE,  4244 );
  ASSERT( Strings.IsEqual( astr( "12345" ), astr( "123.5" ))   = FALSE,  4245 );
  ASSERT( Strings.IsEqual( astr( "12345" ), astr( "12345" ))   = TRUE,   4246 );
  ASSERT( Strings.IsEqual( NIL,             NIL)               = TRUE,   4247 );
  ASSERT( Strings.IsEqual( NIL,             astr( "12345" ))   = FALSE,  4248 );
  ASSERT( Strings.IsEqual( astr( "12345" ), NIL)               = FALSE,  4249 );

  ASSERT( Strings.IsEqualHead( astr( "" ),      astr( "" ))        = TRUE,   4250 );
  ASSERT( Strings.IsEqualHead( astr( "1" ),     astr( "1" ))       = TRUE,   4251 );
  ASSERT( Strings.IsEqualHead( astr( "1" ),     astr( "" ))        = TRUE,   4251 );
  ASSERT( Strings.IsEqualHead( astr( "1" ),     astr( "2" ))       = FALSE,  4252 );
  ASSERT( Strings.IsEqualHead( astr( "1234" ),  astr( "123" ))     = TRUE ,  4253 );
  ASSERT( Strings.IsEqualHead( astr( "123" ),   astr( "1234" ))    = FALSE,  4254 );
  ASSERT( Strings.IsEqualHead( astr( "12345" ), astr( "123.5" ))   = FALSE,  4255 );
  ASSERT( Strings.IsEqualHead( astr( "12345" ), astr( "12345" ))   = TRUE,   4256 );
  ASSERT( Strings.IsEqualHead( NIL,             NIL)               = FALSE,  4257 );
  ASSERT( Strings.IsEqualHead( NIL,             astr( "12345" ))   = FALSE,  4258 );
  ASSERT( Strings.IsEqualHead( astr( "12345" ), NIL)               = FALSE,  4259 );

  ASSERT( Strings.IsMember( "0", astr("0123")));
  ASSERT( Strings.IsMember( "3", astr("0123")));
  ASSERT( ~Strings.IsMember( ".", astr("0123")));
  ASSERT( ~Strings.IsMember( ".", astr("")));


  (*---------------------------------*)
str:=astr(".12.4.6");  pos := -1;
INC(pos);   b:=Strings.FindChar(str,pos,".");               ASSERT((pos = 0) & (b = TRUE),  4280);
INC(pos);   b:=Strings.FindChar(str,pos,".");               ASSERT((pos = 3) & (b = TRUE),  4281);
INC(pos);   b:=Strings.FindChar(str,pos,".");               ASSERT((pos = 5) & (b = TRUE),  4282);
pos:= -100; b:=Strings.FindChar(astr("0123.567"),pos, '.'); ASSERT((pos = 4) & (b = TRUE),  4283);
pos:=  100; b:=Strings.FindChar(astr("0123.567"),pos, '.'); ASSERT((pos=100) & (b = FALSE), 4284);
pos:=    1; b:=Strings.FindChar(astr("0123.567"),pos, 'X' );ASSERT((pos=  1) & (b = FALSE), 4285);
pos:=  -10; b:=Strings.FindChar(astr("0123.567"),pos, '.' );ASSERT((pos=  4) & (b = TRUE), 4285);

(* overwrite 0X, that is string without 0X *)
str:=astr(".12.4.6");  pos:= 0;  str[7] := "-";   
b := Strings.FindChar(str,pos, 'X' ); ASSERT((pos=0)&(b = FALSE), 4286);
b := Strings.FindChar(str,pos, '-' ); ASSERT((pos=7)&(b = TRUE),  4287);

pos := 0;  ASSERT(Strings.FindChar(astr("0123"), pos, "3") & (pos = 3), 4288);



  str := astr( "abcd" );
  pos := -10; b := Strings.FindSeq( astr("01234567"),pos,str );  ASSERT((pos = -10)&(b = FALSE ));
  pos :=   0; b := Strings.FindSeq( astr("01234567"),pos,str );  ASSERT((pos =   0)&(b = FALSE ));
  pos := 100; b := Strings.FindSeq( astr("01234567"),pos,str );  ASSERT((pos = 100)&(b = FALSE ));

  pos :=   0; b := Strings.FindSeq( astr("abcd4567"),pos,str );  ASSERT((pos =   0)&(b = TRUE  ));
  pos :=   0; b := Strings.FindSeq( astr("0abcd567"),pos,str );  ASSERT((pos =   1)&(b = TRUE  ));
  pos :=   0; b := Strings.FindSeq( astr("01abcd67"),pos,str );  ASSERT((pos =   2)&(b = TRUE  ));
  pos :=   0; b := Strings.FindSeq( astr("012abcd7"),pos,str );  ASSERT((pos =   3)&(b = TRUE  ));
  pos :=   0; b := Strings.FindSeq( astr("0123abcd"),pos,str );  ASSERT((pos =   4)&(b = TRUE  ));
  pos :=   2; b := Strings.FindSeq( astr("0123abcd"),pos,str );  ASSERT((pos =   4)&(b = TRUE  ));
  pos :=   4; b := Strings.FindSeq( astr("0123abcd"),pos,str );  ASSERT((pos =   4)&(b = TRUE  ));
  pos :=   5; b := Strings.FindSeq( astr("0123abcd"),pos,str );  ASSERT((pos =   5)&(b = FALSE  ));
  pos :=   0; b := Strings.FindSeq( astr("01234abc"),pos,str );  ASSERT((pos =   0)&(b = FALSE  ));


here := 0;
  (*---------------------------------*)
  str := astr( "0123456789" );
  Strings.Fill( str, 0,0, ".");
  ASSERT( str^ = "0123456789" );
  Strings.Fill( str, 0,1, ".");  ASSERT( str^ = ".123456789" );
  Strings.Fill( str, 3,5, ".");  ASSERT( str^ = ".12.....89" );

  str := astr( "0123456" );
  pos := -1; Strings.Replace(str,pos,astr(""));        ASSERT((str^ = "0123456" )&(pos = -1),4260);
  pos :=  4; Strings.Replace(str,pos,astr(""));        ASSERT((str^ = "0123456" )&(pos =  4),4261);
  pos :=  7; Strings.Replace(str,pos,astr(""));        ASSERT((str^ = "0123456" )&(pos =  7),4261);
  pos :=  8; Strings.Replace(str,pos,astr(""));        ASSERT((str^ = "0123456" )&(pos =  8),4261);
  pos :=  9; Strings.Replace(str,pos,astr(""));        ASSERT((str^ = "0123456" )&(pos = -1),4261);
  pos :=  7; Strings.Replace(str,pos,astr("X"));       ASSERT((str^ = "0123456X")&(pos =  7),4262);
  str := astr( "0123456" );
  pos :=  8; Strings.Replace(str,pos,astr(""));        ASSERT((str^ = "0123456" )&(pos =  8),4263);
  pos :=  9; Strings.Replace(str,pos,astr(""));        ASSERT((str^ = "0123456" )&(pos = -1),4263);

  str := astr( "0123456" );
  pos :=  0; Strings.Replace(str,pos,astr(""));        ASSERT((str^ = "0123456" )&(pos =  0),4264);
  pos :=  0; Strings.Replace(str,pos,astr("A"));       ASSERT((str^ = "A123456" )&(pos =  0),4265);
  pos :=  1; Strings.Replace(str,pos,astr("B"));       ASSERT((str^ = "AB23456" )&(pos =  1),4266);
  pos :=  5; Strings.Replace(str,pos,astr("GH"));      ASSERT((str^ = "AB234GH" )&(pos =  5),4267);
  pos :=  6; Strings.Replace(str,pos,astr("GH"));      ASSERT((str^ = "AB234GGH")&(pos =  6),4268);
  str := astr( "0123456" );
  pos :=  0; Strings.Replace(str,pos,astr("0123456" ));ASSERT((str^ = "0123456" )&(pos =  0),4269);
  pos :=  0; Strings.Replace(str,pos,astr("0123456."));ASSERT((str^ = "0123456.")&(pos =  0),4269);
  str := astr( "0123456" );
  pos :=  0; Strings.Replace(str,pos,astr("0123456.."));ASSERT((str^= "0123456" )&(pos = -1),4269);


here := 3;
  (*---------------------------------*)
  str := astr( "0123456789" );
  pos := 1;
  Strings.Push( str, pos, astr("1") );      ASSERT( (pos =   2) & (str^ = "01"), 4270 );
  Strings.Push( str, pos, astr("234") );    ASSERT( (pos =   5) & (str^ = "01234"), 4271 );
  Strings.Push( str, pos, astr("56789") );  ASSERT( (pos =  10) & (str^ = "0123456789"), 4272 );
  Strings.Push( str, pos, astr("X") );      ASSERT( (pos =  -1) & (str^ = "0123456789"), 4273 );
  Strings.Push( str, pos, astr("X") );      ASSERT( (pos =  -1) & (str^ = "0123456789"), 4274 );

  str := astr( "0123" );
  pos := 0;
  Strings.Push( str, pos, astr( "ab")); ASSERT( (pos =   2) & (str^ = "ab" ), 4275);
  Strings.Push( str, pos, astr( "cd")); ASSERT( (pos =   4) & (str^ = "abcd" ), 4276);

  str := astr( "0123" );
  pos := 0;
  Strings.Push( str, pos, astr( "ab")); ASSERT( (pos =   2) & (str^ = "ab" ), 4277);
  Strings.Push( str, pos, astr( "cde"));ASSERT( (pos =  -1) & (str^ = "ab" ), 4278);


here := 5;
  (*---------------------------------*)
  str := astr( "" );
  pos := 0;
  Strings.PushChar( str, pos, 'a' );   ASSERT( (pos = -1) & (str^ = ""));

  str := astr( " " );
  pos := 0;
  Strings.PushChar( str, pos, 'a' );   ASSERT( (pos =  1) & (str^ = "a"));

  str := astr( "...." );
  pos := 3;
  Strings.PushChar( str, pos, 'X' );   ASSERT( (pos =  4) & (str^ = "...X"));

  str := astr( "...." );
  pos := 4;
  Strings.PushChar( str, pos, 'X' );   ASSERT( (pos = -1) & (str^ = "...."));

  str := Strings.New( 16, "." );
  pos := 2;
  Strings.PushInt( str, pos, 9800012 ); ASSERT( str^ = "..9800012", 4101 );
  Strings.PushChar(str, pos, "-" );     ASSERT( str^ = "..9800012-" );
  Strings.PushInt( str, pos, 42 );      ASSERT( str^ = "..9800012-42", 4102 );
  Strings.PushInt( str, pos, 123000 );  ASSERT((str^ = "..9800012-42") & (pos = -1), 4200);
  pos := 0;
  Strings.PushInt( str, pos, MAX(LONGINT));  ASSERT(str^ =  "2147483647" , 4207);
  pos := 0;
  Strings.PushInt( str, pos, MIN(LONGINT));  ASSERT(str^ = "-2147483648" , 4208);
  pos := 0;
  Strings.PushInt( str, pos, 0);             ASSERT(str^ = "0" , 4208);


  ASSERT(Strings.IsEqual(Strings.Quote("{", astr("otto"), "}"), astr("{otto}")));
  ASSERT(Strings.IsEqual(Strings.Quote("{", astr(""), "}"), astr("{}")));



  (*---------------------------------*)
  pos := 0;
  b := Strings.ReadInt(astr("1"), pos, val);  ASSERT((val = 1) & (pos = 1) & (b = TRUE), 4200);
  pos := 0;
  b := Strings.ReadInt(astr("12"), pos, val);  ASSERT((val = 12) & (pos = 2) & (b = TRUE), 4200);
  pos := 0;
  b := Strings.ReadInt(astr("123"), pos, val);  ASSERT((val = 123) & (pos = 3) & (b = TRUE), 4200);
  
  pos := -10;
  b := Strings.ReadInt(astr("123"), pos, val);  ASSERT((val = 123) & (pos = 3) & (b = TRUE), 4200);
  pos := 0;
  b := Strings.ReadInt(astr("123"), pos, val);  ASSERT((val = 123) & (pos = 3) & (b = TRUE), 4200);
  pos := 1;
  b := Strings.ReadInt(astr("123"), pos, val);  ASSERT((val = 23) & (pos = 3) & (b = TRUE), 4200);
  pos := 2;
  b := Strings.ReadInt(astr("123"), pos, val);  ASSERT((val = 3) & (pos = 3) & (b = TRUE), 4200);
  pos := 3; val := -1;
  b := Strings.ReadInt(astr("123"), pos, val);  ASSERT((val = -1) & (pos = 3) & (b = FALSE), 4200);
  pos := 4;
  b := Strings.ReadInt(astr("123"), pos, val);  ASSERT((val = -1) & (pos = 4) & (b = FALSE), 4200);
  
  pos := 0; val := -1; str := Strings.Empty(); str[0] := "7";
  b := Strings.ReadInt(str, pos, val);  ASSERT((val = 7) & (pos = 1) & (b = TRUE), 4200);
  
  pos := -3; val := -1; str := Strings.Empty(); str[0] := "A";
  b := Strings.ReadInt(str, pos, val);  ASSERT((val = -1) & (pos = -3) & (b = FALSE), 4200);

  pos := 2;
  b := Strings.ReadInt(astr("  +100,12"), pos, val);  ASSERT((val = 100) & (pos = 6) & (b = TRUE));
  pos := 2;
  b := Strings.ReadInt(astr("  -100,12"), pos, val);  ASSERT((val = -100)& (pos = 6) & (b = TRUE));

  pos := -3; val := -4; ASSERT( ~Strings.ReadInt( astr("++"), pos, val) & (pos = -3) & (val = -4));
  pos := -3; val := -4; ASSERT( ~Strings.ReadInt( astr("--"), pos, val) & (pos = -3) & (val = -4));
  pos := -3; val := -4; ASSERT( Strings.ReadInt( astr("-1"), pos, val) & (pos = 2) & (val = -1));
  pos := -3; val := -4; ASSERT( Strings.ReadInt( astr("+1"), pos, val) & (pos = 2) & (val = 1));
  pos := -3; val := -4; ASSERT( Strings.ReadInt( astr("+0"), pos, val) & (pos = 2) & (val = 0));
  pos := -3; val := -4; ASSERT( Strings.ReadInt( astr("-0"), pos, val) & (pos = 2) & (val = 0));
  pos := -3; val := -4; ASSERT( Strings.ReadInt( astr("0"), pos, val) & (pos = 1) & (val = 0));


  pos := -3; ASSERT(Strings.ReadChar(astr("0123"), pos, "0") & (pos = 1), 4210);
  pos := 0; ASSERT(Strings.ReadChar(astr("0123"), pos, "0") & (pos = 1), 4210);
  pos := 2; ASSERT(Strings.ReadChar(astr("0123"), pos, "2") & (pos = 3), 4210);
  pos := 0; ASSERT(Strings.ReadChar(astr("3"), pos, "3") & (pos = 1), 4210);
  
  pos := 1; ASSERT(~Strings.ReadChar(astr("0123"), pos, "0") & (pos = 1), 4210);
  pos := 4; ASSERT(~Strings.ReadChar(astr("0123"), pos, "3") & (pos = 4), 4210);
  pos := -1; ASSERT(~Strings.ReadChar(astr("0123"), pos, "A") & (pos = -1), 4210);
  pos := 1; ASSERT(~Strings.ReadChar(astr("0123"), pos, "0") & (pos = 1), 4210);
  pos := 0; ASSERT(~Strings.ReadChar(astr("0"), pos, "1") & (pos = 0), 4210);
  pos := 0; ASSERT(~Strings.ReadChar(astr(""), pos, "1") & (pos = 0), 4210);


  pos := -3; ASSERT(Strings.ReadWhileChar(astr("0123"), pos, IsDigit) & (pos = 4), 4220);
  pos := -3; ASSERT(Strings.ReadWhileChar(astr("012A"), pos, IsDigit) & (pos = 3), 4220);
  pos := -3; ASSERT(Strings.ReadWhileChar(astr("01A0"), pos, IsDigit) & (pos = 2), 4220);
  pos := -3; ASSERT(Strings.ReadWhileChar(astr("0"), pos, IsDigit) & (pos = 1), 4220);
  
  pos := -3; ASSERT(~Strings.ReadWhileChar(astr(""), pos, IsDigit) & (pos = -3), 4221);
  pos := 3; ASSERT(~Strings.ReadWhileChar(astr("012A45"), pos, IsDigit) & (pos = 3), 4221);
  
  
  (*---------------------------------*)
  str := Strings.Maximal( astr( "0123" ), -1 );  ASSERT( str  = NIL );
  str := Strings.Maximal( astr( "0123" ),  0 );  ASSERT( str^ = "" );
  str := Strings.Maximal( astr( "0123" ),  1 );  ASSERT( str^ = "0" );
  str := Strings.Maximal( astr( "0123" ),  2 );  ASSERT( str^ = "01" );
  str := Strings.Maximal( astr( "0123" ),  3 );  ASSERT( str^ = "012" );
  str := Strings.Maximal( astr( "0123" ),  4 );  ASSERT( str^ = "0123" );
  str := Strings.Maximal( astr( "0123" ),  5 );  ASSERT( str^ = "0123" );
  str := Strings.Maximal( astr( "0123" ),  6 );  ASSERT( str^ = "0123" );

  str := astr( "0123" );  str := Strings.PadLeft( str, 3, "." ); ASSERT( str^ = "0123", 4201 );
  str := astr( "0123" );  str := Strings.PadLeft( str, 4, "." ); ASSERT( str^ = "0123", 4202 );
  str := astr( "0123" );  str := Strings.PadLeft( str, 5, "." ); ASSERT( str^ = ".0123", 4203 );
  str := astr( "0123" );  str := Strings.PadLeft( str, 8, "." ); ASSERT( str^ = "....0123", 4204 );

  str := astr( "0123" );  str := Strings.PadRight( str, 3, "." ); ASSERT( str^ = "0123", 4201 );
  str := astr( "0123" );  str := Strings.PadRight( str, 4, "." ); ASSERT( str^ = "0123", 4202 );
  str := astr( "0123" );  str := Strings.PadRight( str, 5, "." ); ASSERT( str^ = "0123.", 4203 );
  str := astr( "0123" );  str := Strings.PadRight( str, 8, "." ); ASSERT( str^ = "0123....",4204 );


  str := astr( "" );        str := Strings.Trim( str, " " ); ASSERT( (str^ = "") &(LEN(str^) = 1));
  str := astr( "A" );       str := Strings.Trim( str, " " ); ASSERT( str^ = "A", 4210 );
  str := astr( " A" );      str := Strings.Trim( str, " " ); ASSERT( str^ = "A", 4210 );
  str := astr( "A " );      str := Strings.Trim( str, " " ); ASSERT( str^ = "A", 4210 );
  str := astr( " A " );     str := Strings.Trim( str, " " ); ASSERT( str^ = "A", 4210 );
  str := astr( "----A----");str := Strings.Trim( str, "-" ); ASSERT( str^ = "A", 4210 );
  str := astr( "---------");str := Strings.Trim( str, "-" ); ASSERT( str^ = "", 4210 );


  str := astr( "" );        str := Strings.TrimRight( str, " " );ASSERT((str^ = "")&(LEN(str^)=1));
  str := astr( "A" );       str := Strings.TrimRight( str, " " ); ASSERT(str^ = "A", 4220 );
  str := astr( " A" );      str := Strings.TrimRight( str, " " ); ASSERT(str^ = " A", 4221 );
  str := astr( "A " );      str := Strings.TrimRight( str, " " ); ASSERT(str^ = "A", 4222 );
  str := astr( " A " );     str := Strings.TrimRight( str, " " ); ASSERT(str^ = " A", 4223 );
  str := astr( "----A----" );str:= Strings.TrimRight( str, "-" ); ASSERT(str^ = "----A", 4224 );
  str := astr( "---------" );str:= Strings.TrimRight( str, "-" ); ASSERT(str^ = "", 4224 );


  str := astr( "" ); str := Strings.TrimRight1( str, " " ); ASSERT( (str^ = " ") & (LEN(str^) =2));
  str := astr( "A" );        str := Strings.TrimRight1( str, " " ); ASSERT( str^ = "A ", 4230 );
  str := astr( " A" );       str := Strings.TrimRight1( str, " " ); ASSERT( str^ = " A ", 4231 );
  str := astr( "A " );       str := Strings.TrimRight1( str, " " ); ASSERT( str^ = "A ", 4232 );
  str := astr( " A " );      str := Strings.TrimRight1( str, " " ); ASSERT( str^ = " A ", 4233 );
  str := astr( " A    " );   str := Strings.TrimRight1( str, " " ); ASSERT( str^ = " A ", 4233 );
  str := astr( "----A----" );str := Strings.TrimRight1( str, "-" ); ASSERT( str^ = "----A-",4234 );
  str := astr( "---------" );str := Strings.TrimRight1( str, "-" ); ASSERT( str^ = "-",4234 );


here := 10;
  (*---------------------------------*)
  str := Strings.Spaces( 0 ); ASSERT( str^ = "" );
  str := Strings.Spaces( 5 ); ASSERT( str^ = "     " );

  pos := 0; str := astr( "01234567" );   Strings.SkipWhitespace( str, pos );   ASSERT( pos = 0 );
  pos := 0; str := astr( " 1234567" );   Strings.SkipWhitespace( str, pos );   ASSERT( pos = 1 );
  pos := 0; str := astr( "  234567" );   Strings.SkipWhitespace( str, pos );   ASSERT( pos = 2 );
  pos := 1; str := astr( "  234567" );   Strings.SkipWhitespace( str, pos );   ASSERT( pos = 2 );
  pos := 2; str := astr( "  234567" );   Strings.SkipWhitespace( str, pos );   ASSERT( pos = 2 );
  pos := 3; str := astr( "  234567" );   Strings.SkipWhitespace( str, pos );   ASSERT( pos = 3 );

  ASSERT( 0 = Strings.Indentation( astr("" )));
  ASSERT( 0 = Strings.Indentation( astr("abc" )));
  ASSERT( 1 = Strings.Indentation( astr(" a  " )));
  ASSERT( 5 = Strings.Indentation( astr("     a bcd" )));

  str := Strings.Indent( astr( "" ), 0 );        ASSERT( str^ = "" );
  str := Strings.Indent( astr( "" ), 4 );        ASSERT( str^ = "    " );
  str := Strings.Indent( astr( "01234" ), 0 );   ASSERT( str^ = "01234" );
  str := Strings.Indent( astr( "01234" ), 1 );   ASSERT( str^ = " 01234" );
  str := Strings.Indent( astr( " 0123" ), 1 );   ASSERT( str^ = " 0123" );
  str := Strings.Indent( astr( " 0123" ), 0 );   ASSERT( str^ = "0123" );
  str := Strings.Indent( astr( "     0123" ), 8 );ASSERT( str^ = "        0123" );
  str := Strings.Indent( astr( "  0123" ), 8 );   ASSERT( str^ = "        0123" );
  str := Strings.Indent( astr( "abc" ), -4 );    ASSERT( str  = NIL );
  str := Strings.Indent( astr( "" ), -4 );       ASSERT( str  = NIL );

  str := Strings.Reverse( astr( "" ));           ASSERT( str^ = "", 4290 );
  str := Strings.Reverse( astr( "A" ));          ASSERT( str^ = "A", 4291 );
  str := Strings.Reverse( astr( "AB" ));         ASSERT( str^ = "BA", 4292 );
  str := Strings.Reverse( astr( "ABC" ));        ASSERT( str^ = "CBA", 4293 );
  str := Strings.Reverse( astr( "ABCD" ));       ASSERT( str^ = "DCBA", 4294 );
  str := Strings.Reverse( astr( "ABCDE" ));      ASSERT( str^ = "EDCBA", 4295 );
  (*---------------------------------*)

END tString;


(*---------------------------------------------------------------------------*)
PROCEDURE All*;
BEGIN
  tString;
  lf; mprint( "CTStrings: No assertion triggered." );
  lf;
END All;


END CTStrings.   (*  sts-q  2022-Mrz  *)
