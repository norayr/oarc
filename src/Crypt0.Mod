MODULE Crypt0;
IMPORT Files;

CONST
  idversion* = 'Crypt0 0.1d1 VOC';
  defaultseed = 871491;
  (* Constants from ArcTool *)
  Done = 0;
  ErrorInArchive = 2;

TYPE
  CryptProc* = PROCEDURE (VAR Rin: Files.Rider; nIn: LONGINT;
                          VAR Rout: Files.Rider; key: ARRAY OF CHAR;
                          VAR res: INTEGER);

VAR
  seed, keylen, curkey: LONGINT;
  Decrypt*, Encrypt*: CryptProc;

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
  n := keylen - 1;
  curkey := 0;
  WHILE n >= 0 DO
    scr := ParksMiller(seed, key[n]);
    DEC(n)
  END;
END GetSeed;

PROCEDURE NextKey(key: ARRAY OF CHAR): LONGINT;
BEGIN
  curkey := (curkey + 1) MOD keylen;
  RETURN ParksMiller(seed, key[curkey])
END NextKey;

PROCEDURE XORDecrypt(VAR Rin: Files.Rider; nIn: LONGINT;
                     VAR Rout: Files.Rider; key: ARRAY OF CHAR;
                     VAR res: INTEGER);
VAR
  i: LONGINT;
  ch: CHAR;
BEGIN
  GetSeed(key);
  i := 0;
  WHILE ~Rin.eof & (i < nIn) DO
    Files.Read(Rin, ch);
    Files.Write(Rout, CHR((ORD(ch) - NextKey(key)) MOD 256));
    INC(i)
  END;
  IF i = nIn THEN
    res := Done
  ELSE
    res := ErrorInArchive
  END
END XORDecrypt;

PROCEDURE XOREncrypt(VAR Rin: Files.Rider; nIn: LONGINT;
                     VAR Rout: Files.Rider; key: ARRAY OF CHAR;
                     VAR res: INTEGER);
VAR
  i: LONGINT;
  ch: CHAR;
BEGIN
  GetSeed(key);
  i := 0;
  WHILE ~Rin.eof & (i < nIn) DO
    Files.Read(Rin, ch);
    Files.Write(Rout, CHR((ORD(ch) + NextKey(key)) MOD 256));
    INC(i)
  END;
  IF i = nIn THEN
    res := Done
  ELSE
    res := ErrorInArchive
  END
END XOREncrypt;

PROCEDURE Key*;
BEGIN
  Decrypt := XORDecrypt;
  Encrypt := XOREncrypt
END Key;

BEGIN
  (* Initialize module *)
  Decrypt := NIL;
  Encrypt := NIL;
  keylen := 1; (* Safe default *)
END Crypt0.
