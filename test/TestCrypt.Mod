MODULE TestCrypt;
IMPORT Out, Files, Crypt0, ArcTool;

PROCEDURE TestEncryptDecrypt*;
VAR
  F1, F2, F3: Files.File;
  R1, R2, R3: Files.Rider;
  key: ARRAY 10 OF CHAR;
  res: INTEGER;
  ch: CHAR;
  i: INTEGER;
BEGIN
  key := "aoe";
  
  (* Create test file *)
  F1 := Files.New("test_plain.txt");
  Files.Set(R1, F1, 0);
  Files.Write(R1, 'a'); Files.Write(R1, 'a'); Files.Write(R1, 'a'); Files.Write(R1, 0AX);
  Files.Write(R1, 'b'); Files.Write(R1, 'b'); Files.Write(R1, 'b'); Files.Write(R1, 0AX);
  Files.Write(R1, 'c'); Files.Write(R1, 'c'); Files.Write(R1, 'c'); Files.Write(R1, 0AX);
  Files.Write(R1, 0AX);
  Files.Register(F1);
  
  (* Initialize encryption *)
  Crypt0.Key();
  ArcTool.Encrypt := Crypt0.Encrypt;
  ArcTool.Decrypt := Crypt0.Decrypt;
  
  (* Encrypt *)
  Out.String("Encrypting..."); Out.Ln;
  F1 := Files.Old("test_plain.txt");
  F2 := Files.New("test_encrypted.bin");
  Files.Set(R1, F1, 0);
  Files.Set(R2, F2, 0);
  
  Crypt0.Encrypt(R1, Files.Length(F1), R2, key, res);
  Files.Register(F2);
  
  Out.String("Encryption result: "); Out.Int(res, 0); Out.Ln;
  
  (* Show encrypted bytes *)
  Out.String("Encrypted bytes: ");
  Files.Set(R2, F2, 0);
  i := 0;
  WHILE ~R2.eof & (i < 20) DO
    Files.Read(R2, ch);
    Out.Int(ORD(ch), 4);
    INC(i);
  END;
  Out.Ln;
  
  (* Decrypt *)
  Out.String("Decrypting..."); Out.Ln;
  F3 := Files.New("test_decrypted.txt");
  Files.Set(R2, F2, 0);
  Files.Set(R3, F3, 0);
  
  Crypt0.Decrypt(R2, Files.Length(F2), R3, key, res);
  Files.Register(F3);
  
  Out.String("Decryption result: "); Out.Int(res, 0); Out.Ln;
  
  (* Show decrypted content *)
  Out.String("Decrypted content: ");
  Files.Set(R3, F3, 0);
  i := 0;
  WHILE ~R3.eof & (i < 20) DO
    Files.Read(R3, ch);
    IF ch = 0AX THEN
      Out.String("\\n");
    ELSE
      Out.Char(ch);
    END;
    INC(i);
  END;
  Out.Ln;
  
  (* Compare *)
  Files.Set(R1, F1, 0);
  Files.Set(R3, F3, 0);
  Out.String("Comparing: ");
  WHILE ~R1.eof & ~R3.eof DO
    Files.Read(R1, ch);
    Files.Read(R3, ch);
    IF R1.eof # R3.eof THEN
      Out.String("Length mismatch!"); Out.Ln;
      RETURN;
    END;
  END;
  
  IF R1.eof & R3.eof THEN
    Out.String("Files match!"); Out.Ln;
  ELSE
    Out.String("Files differ!"); Out.Ln;
  END;
  
  Files.Close(F1);
  Files.Close(F2);
  Files.Close(F3);
END TestEncryptDecrypt;

BEGIN
  TestEncryptDecrypt();
END TestCrypt.