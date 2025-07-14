MODULE TestCompressEncrypt;
IMPORT Out, Files, ArcTool, Crypt0;

PROCEDURE ShowBytes(F: Files.File; name: ARRAY OF CHAR; max: INTEGER);
VAR
  R: Files.Rider;
  ch: CHAR;
  i: INTEGER;
BEGIN
  Out.String(name); Out.String(": ");
  Out.Int(Files.Length(F), 0); Out.String(" bytes: ");
  Files.Set(R, F, 0);
  i := 0;
  WHILE ~R.eof & (i < max) DO
    Files.Read(R, ch);
    Out.Int(ORD(ch), 4);
    INC(i);
  END;
  IF ~R.eof THEN Out.String("...") END;
  Out.Ln;
END ShowBytes;

PROCEDURE Test*;
VAR
  F1, F2, F3, F4, F5: Files.File;
  R1, R2, R3, R4, R5: Files.Rider;
  res: INTEGER;
  key: ARRAY 10 OF CHAR;
  len: LONGINT;
  tmp: SHORTINT;
BEGIN
  key := "aoe";

  (* 1. Create original file *)
  Out.String("1. Creating original file"); Out.Ln;
  F1 := Files.New("1_original.txt");
  Files.Set(R1, F1, 0);
  Files.WriteString(R1, "aaa"); Files.Write(R1, 0AX);
  Files.WriteString(R1, "bbb"); Files.Write(R1, 0AX);
  Files.WriteString(R1, "ccc"); Files.Write(R1, 0AX);
  Files.Write(R1, 0AX);
  Files.Register(F1);
  ShowBytes(F1, "Original", 20);

  (* 2. Compress *)
  Out.String("2. Compressing"); Out.Ln;
  F2 := Files.New("2_compressed.bin");
  Files.Set(R1, F1, 0);
  Files.Set(R2, F2, 0);

  (* Initialize compression *)
  ArcTool.SetLen(0);
  ArcTool.SetBufferPtr(0);
  ArcTool.SetCurBitNr(7);
  ArcTool.SetCurByte(0);

  ArcTool.Compress(R1, R2, Files.Length(F1));
  ArcTool.FlushBits(R2);
  Files.Register(F2);
  len := ArcTool.Len;
  Out.String("Compressed length: "); Out.Int(len, 0); Out.Ln;
  ShowBytes(F2, "Compressed", 20);

  (* 3. Encrypt compressed data *)
  Out.String("3. Encrypting compressed data"); Out.Ln;
  Crypt0.Key();
  F3 := Files.New("3_encrypted.bin");
  Files.Set(R2, F2, 0);
  Files.Set(R3, F3, 0);

  Crypt0.Encrypt(R2, len, R3, key, res);
  Files.Register(F3);
  Out.String("Encrypt result: "); Out.Int(res, 0); Out.Ln;
  ShowBytes(F3, "Encrypted", 20);

  (* 4. Decrypt *)
  Out.String("4. Decrypting"); Out.Ln;
  F4 := Files.New("4_decrypted.bin");
  Files.Set(R3, F3, 0);
  Files.Set(R4, F4, 0);

  Crypt0.Decrypt(R3, Files.Length(F3), R4, key, res);
  Files.Register(F4);
  Out.String("Decrypt result: "); Out.Int(res, 0); Out.Ln;
  ShowBytes(F4, "Decrypted", 20);

  (* 5. Decompress *)
  Out.String("5. Decompressing"); Out.Ln;
  F5 := Files.New("5_final.txt");
  Files.Set(R4, F4, 0);
  Files.Set(R5, F5, 0);

  (* Initialize decompression *)
  ArcTool.SetLen(0);
  ArcTool.SetBufferPtr(ArcTool.BufferSize);
  ArcTool.SetCurBitNr(7);
  ArcTool.SetCurByte(0);
  ArcTool.SetMaxLen(Files.Length(F4));

  ArcTool.Expand(R4, R5);
  Files.Register(F5);
  ShowBytes(F5, "Final", 20);

  (* Compare *)
  Files.Set(R1, F1, 0);
  Files.Set(R5, F5, 0);
  Out.String("Comparing original and final: ");
  WHILE ~R1.eof & ~R5.eof DO
    Files.Read(R1, tmp);  (* dummy read *)
    Files.Read(R5, tmp);
  END;

  IF R1.eof & R5.eof THEN
    Out.String("MATCH!"); Out.Ln;
  ELSE
    Out.String("DIFFER!"); Out.Ln;
  END;

  (* Cleanup *)
  Files.Close(F1); Files.Close(F2); Files.Close(F3);
  Files.Close(F4); Files.Close(F5);
END Test;

BEGIN
  Test();
END TestCompressEncrypt.
