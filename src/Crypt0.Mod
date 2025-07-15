MODULE Crypt0;
IMPORT Files, Out, ArcTool;  (* Import ArcTool to use its CryptProc type *)

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
  IF keylen > 0 THEN
    DEC(keylen);  (* Original uses Length-1 *)
  ELSE
    keylen := 0;  (* Handle empty key *)
  END;
  curkey := 0;  (* Reset current key position *)
  n := keylen;
  WHILE n >= 0 DO
    scr := ParksMiller(seed, key[n]);
    DEC(n)
  END;
END GetSeed;

PROCEDURE NextKey(key: ARRAY OF CHAR): LONGINT;
BEGIN
  IF keylen > 0 THEN
    curkey := (curkey + 1) MOD (keylen + 1);  (* keylen is already Length-1 *)
  ELSE
    curkey := 0;
  END;
  RETURN ParksMiller(seed, key[curkey])
END NextKey;

PROCEDURE NextKeyVoyager(key: ARRAY OF CHAR): LONGINT;
BEGIN
  IF keylen = 0 THEN
    Out.String("ERROR: Division by zero in Voyager/Heidelberg cipher!"); Out.Ln;
    Out.String("This cipher has a bug: it uses Length(key)-1 as the modulo divisor."); Out.Ln;
    Out.String("With a 1-character key, this becomes 0, causing division by zero."); Out.Ln;
    Out.String("This replicates the original bug from:"); Out.Ln;
    Out.String("http://statlab.uni-heidelberg.de/projects/voyager/"); Out.Ln;
    Out.String("Use a key with 2 or more characters, or use a different cipher."); Out.Ln;
    HALT(1);
  ELSE
    curkey := (curkey + 1) MOD keylen;   (* Original bug: crashes if key length is 1 *)
    RETURN ParksMiller(seed, key[curkey])
  END
END NextKeyVoyager;

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

PROCEDURE ModDecryptVoyager(VAR Rin: Files.Rider; nIn: LONGINT;
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
    ks := NextKeyVoyager(key) MOD 256;
    (* Modular subtraction for decryption - ensure positive result *)
    Files.Write(Rout, CHR((ORD(ch) - ks + 256) MOD 256));
    INC(i)
  END;
  IF i = nIn THEN
    res := Done
  ELSE
    res := ErrorInArchive
  END
END ModDecryptVoyager;

PROCEDURE ModEncryptVoyager(VAR Rin: Files.Rider; nIn: LONGINT;
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
    ks := NextKeyVoyager(key) MOD 256;
    (* Modular addition for encryption *)
    Files.Write(Rout, CHR((ORD(ch) + ks) MOD 256));
    INC(i)
  END;
  IF i = nIn THEN
    res := Done
  ELSE
    res := ErrorInArchive
  END
END ModEncryptVoyager;



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

(* S3 encryption from ETH Oberon System 3 *)
(* Note: This is a simple substitution cipher, not cryptographically secure *)
PROCEDURE S3Encrypt*(VAR Rin: Files.Rider; nIn: LONGINT;
                     VAR Rout: Files.Rider; key: ARRAY OF CHAR;
                     VAR res: INTEGER);
VAR
  i, n: LONGINT;
  ch: CHAR;
BEGIN
  n := Length(key);
  IF n = 0 THEN n := 1 END; (* Avoid division by zero *)
  i := 0;
  WHILE ~Rin.eof & (i < nIn) DO
    Files.Read(Rin, ch);
    (* Add key character for encryption *)
    Files.Write(Rout, CHR((ORD(ch) + ORD(key[i MOD n])) MOD 256));
    INC(i)
  END;
  IF i = nIn THEN
    res := Done
  ELSE
    res := ErrorInArchive
  END
END S3Encrypt;

PROCEDURE S3Decrypt*(VAR Rin: Files.Rider; nIn: LONGINT;
                     VAR Rout: Files.Rider; key: ARRAY OF CHAR;
                     VAR res: INTEGER);
VAR
  i, n: LONGINT;
  ch: CHAR;
BEGIN
  n := Length(key);
  IF n = 0 THEN n := 1 END; (* Avoid division by zero *)
  i := 0;
  WHILE ~Rin.eof & (i < nIn) DO
    Files.Read(Rin, ch);
    (* Subtract key character for decryption, handle negative values *)
    Files.Write(Rout, CHR((ORD(ch) - ORD(key[i MOD n]) + 256) MOD 256));
    INC(i)
  END;
  IF i = nIn THEN
    res := Done
  ELSE
    res := ErrorInArchive
  END
END S3Decrypt;

PROCEDURE Key*;
BEGIN
  (* Install the modular addition/subtraction handlers by default *)
  Decrypt := ModDecrypt;
  Encrypt := ModEncrypt
END Key;

PROCEDURE SetCipher*(cipher: ARRAY OF CHAR);
BEGIN
  IF cipher = "mod" THEN
    Decrypt := ModDecrypt;
    Encrypt := ModEncrypt;
  ELSIF cipher = "heidelberg" THEN
    Decrypt := ModDecryptVoyager;  (* replicates bug found in Crypt0.Mod from https://web.archive.org/web/20140314210953/http://statlab.uni-heidelberg.de/projects/voyager/ *)
    Encrypt := ModEncryptVoyager;
  ELSIF cipher = "xor" THEN
    Decrypt := XORDecrypt;
    Encrypt := XOREncrypt;
  ELSIF cipher = "s3" THEN
    Decrypt := S3Decrypt;
    Encrypt := S3Encrypt;
  ELSE
    (* Fallback to default mod encryption *)
    Decrypt := ModDecrypt;
    Encrypt := ModEncrypt;
  END;
END SetCipher;

BEGIN
  (* Initialize module *)
  keylen := 1; (* Safe default *)
  Decrypt := NIL;
  Encrypt := NIL;
END Crypt0.
