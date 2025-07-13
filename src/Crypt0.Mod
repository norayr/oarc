MODULE Crypt0; 
IMPORT Files, SYSTEM, ArcTool;  (* Import ArcTool to use its CryptProc type *)

CONST 
  idversion* = 'Crypt0 0.1d1 VOC';
  defaultseed = 871491;
  (* Constants from ArcTool *)
  Done = 0;
  ErrorInArchive = 2;

VAR 
  seed, keylen, curkey: LONGINT;
  Decrypt*, Encrypt*: ArcTool.CryptProc;  (* Use ArcTool's type! *)

PROCEDURE Length(VAR s: ARRAY OF CHAR): LONGINT;
VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END;
  RETURN i
END Length;
  
PROCEDURE ParksMiller(VAR s: LONGINT; inc: CHAR): LONGINT;   
(* One step of Parks & Miller portable random number generator, with pre-increment *)
CONST
  a = 16807; 
  m = 2147483647;    (*=$7FFFFFFF*)  
  q = m DIV a;   
  r = m MOD a; 
BEGIN
  IF ORD(inc) < m - s THEN 
    s := s + ORD(inc) 
  ELSE 
    s := s - m + ORD(inc) 
  END; 
  s := a * (s MOD q) - r * (s DIV q); 
  IF s < 0 THEN s := s + m END; 
  RETURN s DIV 0FFFFH
END ParksMiller;     
  
PROCEDURE GetSeed(key: ARRAY OF CHAR); 
VAR 
  n, scr: LONGINT; 
BEGIN
  seed := defaultseed;    
  keylen := Length(key);
  IF keylen = 0 THEN keylen := 1 END; (* Avoid division by zero *)
  curkey := 0;  (* Reset current key position *)
  n := keylen - 1;   
  WHILE n >= 0 DO 
    scr := ParksMiller(seed, key[n]);  
    DEC(n) 
  END; 
END GetSeed; 
  
PROCEDURE NextKey(key: ARRAY OF CHAR): LONGINT;   
BEGIN
  INC(curkey);
  IF curkey >= keylen THEN curkey := 0 END;  (* Wrap around *)
  RETURN ParksMiller(seed, key[curkey])
END NextKey; 

(* Original Crypt0 encryption - modular addition *)
PROCEDURE ModDecrypt(VAR Rin: Files.Rider; nIn: LONGINT; 
                     VAR Rout: Files.Rider; key: ARRAY OF CHAR; 
                     VAR res: INTEGER); 
VAR
  i, ks: LONGINT; 
  ch: CHAR;
BEGIN
  GetSeed(key); 
  i := 0;    
  WHILE ~Rin.eof & (i < nIn) DO
    Files.Read(Rin, ch);
    ks := NextKey(key) MOD 256;
    (* Modular subtraction for decryption - ensure positive result *)
    Files.Write(Rout, CHR((ORD(ch) - ks + 256) MOD 256)); 
    INC(i)
  END; 
  IF i = nIn THEN
    res := Done
  ELSE
    res := ErrorInArchive
  END
END ModDecrypt; 
  
PROCEDURE ModEncrypt(VAR Rin: Files.Rider; nIn: LONGINT; 
                     VAR Rout: Files.Rider; key: ARRAY OF CHAR; 
                     VAR res: INTEGER); 
VAR
  i, ks: LONGINT; 
  ch: CHAR;
BEGIN
  GetSeed(key); 
  i := 0;
  WHILE ~Rin.eof & (i < nIn) DO
    Files.Read(Rin, ch);
    ks := NextKey(key) MOD 256;
    (* Modular addition for encryption *)
    Files.Write(Rout, CHR((ORD(ch) + ks) MOD 256)); 
    INC(i)
  END; 
  IF i = nIn THEN
    res := Done
  ELSE
    res := ErrorInArchive
  END
END ModEncrypt; 

(* XOR variant for future use *)
PROCEDURE XORDecrypt*(VAR Rin: Files.Rider; nIn: LONGINT; 
                      VAR Rout: Files.Rider; key: ARRAY OF CHAR; 
                      VAR res: INTEGER); 
VAR
  i: LONGINT; 
  ch: CHAR;
  ks: INTEGER;
  chVal, ksVal, result: INTEGER;
BEGIN
  GetSeed(key); 
  i := 0;    
  WHILE ~Rin.eof & (i < nIn) DO
    Files.Read(Rin, ch);
    ks := SHORT(NextKey(key) MOD 256);
    (* Perform XOR using integer operations *)
    chVal := ORD(ch);
    ksVal := ks;
    result := 0;
    (* XOR bit by bit *)
    IF (chVal MOD 2) # (ksVal MOD 2) THEN result := result + 1 END;
    chVal := chVal DIV 2; ksVal := ksVal DIV 2;
    IF (chVal MOD 2) # (ksVal MOD 2) THEN result := result + 2 END;
    chVal := chVal DIV 2; ksVal := ksVal DIV 2;
    IF (chVal MOD 2) # (ksVal MOD 2) THEN result := result + 4 END;
    chVal := chVal DIV 2; ksVal := ksVal DIV 2;
    IF (chVal MOD 2) # (ksVal MOD 2) THEN result := result + 8 END;
    chVal := chVal DIV 2; ksVal := ksVal DIV 2;
    IF (chVal MOD 2) # (ksVal MOD 2) THEN result := result + 16 END;
    chVal := chVal DIV 2; ksVal := ksVal DIV 2;
    IF (chVal MOD 2) # (ksVal MOD 2) THEN result := result + 32 END;
    chVal := chVal DIV 2; ksVal := ksVal DIV 2;
    IF (chVal MOD 2) # (ksVal MOD 2) THEN result := result + 64 END;
    chVal := chVal DIV 2; ksVal := ksVal DIV 2;
    IF (chVal MOD 2) # (ksVal MOD 2) THEN result := result + 128 END;
    
    Files.Write(Rout, CHR(result)); 
    INC(i)
  END; 
  IF i = nIn THEN
    res := Done
  ELSE
    res := ErrorInArchive
  END
END XORDecrypt; 
  
PROCEDURE XOREncrypt*(VAR Rin: Files.Rider; nIn: LONGINT; 
                      VAR Rout: Files.Rider; key: ARRAY OF CHAR; 
                      VAR res: INTEGER); 
BEGIN
  (* XOR encryption and decryption are the same operation *)
  XORDecrypt(Rin, nIn, Rout, key, res)
END XOREncrypt; 
  
PROCEDURE Key*; 
BEGIN
  (* Install the modular addition/subtraction handlers by default *)
  Decrypt := ModDecrypt; 
  Encrypt := ModEncrypt
END Key; 

BEGIN
  (* Initialize module *)
  keylen := 1; (* Safe default *)
  Decrypt := NIL;
  Encrypt := NIL;
END Crypt0.