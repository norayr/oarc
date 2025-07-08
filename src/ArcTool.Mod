MODULE ArcTool;
IMPORT Files, FileUtil, Out, Platform, Strings, SYSTEM;

CONST
  BufferSize = 4096;
  IndexBitCount = 12;
  LengthBitCount = 4;
  WindowSize = 4096;
  RawLookAheadSize = 16;
  BreakEven = 1;
  LookAheadSize = RawLookAheadSize + BreakEven;
  TreeRoot = WindowSize;
  EndOfStream = 0;
  Unused = 0;
  Temp = "/tmp/Compress.Temp";
  err1 = "Error in archive";
  err2 = " not found";
  xx = 32768;
  EOFName = "~ ";
  Done = 0;
  ArchiveNotFound = 1;
  ErrorInArchive = 2;
  EntryNotFound = 3;
  ArchiveExists = 4;
  FileError = 5;

TYPE
  Node = RECORD
    parent, smallerChild, largerChild: INTEGER
  END;
  Name = ARRAY 32 OF CHAR;
  Header = RECORD
    name: Name;
    length, check: LONGINT;
    date, time: LONGINT;
    ratio: REAL
  END;
  EnumProc = PROCEDURE (h: Header; VAR stop: BOOLEAN);

VAR
  Buffer: ARRAY BufferSize OF CHAR;
  Window: ARRAY WindowSize+RawLookAheadSize+1 OF CHAR;
  Tree: ARRAY WindowSize+1 OF Node;
  CurBitNr, Len, maxLen: LONGINT;
  CurByte: LONGINT;
  BufferPtr: LONGINT;
  Err: BOOLEAN;

PROCEDURE Init();
VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE i < WindowSize DO
    Tree[i].parent := Unused;
    Tree[i].smallerChild := Unused;
    Tree[i].largerChild := Unused;
    Window[i] := CHR(0);
    INC(i)
  END;
  Tree[i].parent := Unused;
  Tree[i].smallerChild := Unused;
  Tree[i].largerChild := Unused;
  WHILE i < WindowSize+RawLookAheadSize+1 DO
    Window[i] := CHR(0);
    INC(i)
  END
END Init;

PROCEDURE CopyFrom(VAR Ri, Ro: Files.Rider; len: LONGINT);
VAR i: LONGINT;
BEGIN
  Files.ReadBytes(Ri, Buffer, BufferSize);
  i := BufferSize;
  WHILE i <= len DO
    Files.WriteBytes(Ro, Buffer, BufferSize);
    Files.ReadBytes(Ri, Buffer, BufferSize);
    INC(i, BufferSize)
  END;
  Files.WriteBytes(Ro, Buffer, len MOD BufferSize)
END CopyFrom;

PROCEDURE ReadHeader(VAR R: Files.Rider; VAR h: Header; VAR err: BOOLEAN);
VAR chk, pos: LONGINT; i: INTEGER;
BEGIN
  pos := Files.Pos(R);
  Files.ReadBytes(R, h.name, 32);
  IF R.eof & (R.res = 32) THEN
    h.name := EOFName;
    err := FALSE;
    RETURN
  END;
  Files.ReadLInt(R, h.length);
  Files.ReadLInt(R, h.check);
  Files.ReadLInt(R, h.date);
  Files.ReadLInt(R, h.time);
  Files.ReadReal(R, h.ratio);
  IF (h.ratio > 0.0) & (h.ratio < 1000000.0) THEN
    pos := 0; chk := 0;
    WHILE pos < 32 DO
      chk := chk + ORD(h.name[pos]);
      INC(pos)
    END;
    chk := chk + h.length + ENTIER(h.ratio) + (h.time MOD xx) + (h.date MOD xx);
    err := chk # h.check
  ELSE
    err := TRUE
  END
END ReadHeader;

PROCEDURE WriteHeader(VAR R: Files.Rider; VAR h: Header);
VAR i: LONGINT;
BEGIN
  h.check := 0;
  i := 0;
  WHILE i < 32 DO
    h.check := h.check + ORD(h.name[i]);
    INC(i)
  END;
  Platform.GetClock(h.time, h.date);
  h.check := h.check + h.length + (h.time MOD xx) + (h.date MOD xx) + ENTIER(h.ratio);
  Files.WriteBytes(R, h.name, 32);
  Files.WriteLInt(R, h.length);
  Files.WriteLInt(R, h.check);
  Files.WriteLInt(R, h.date);
  Files.WriteLInt(R, h.time);
  Files.WriteReal(R, h.ratio)
END WriteHeader;

PROCEDURE InputBit(VAR R: Files.Rider): LONGINT;
VAR h: LONGINT;
BEGIN
  IF CurBitNr = 7 THEN
    IF BufferPtr = BufferSize THEN
      Files.ReadBytes(R, Buffer, BufferSize);
      INC(Len, BufferSize);
      IF Len >= maxLen + BufferSize THEN Err := TRUE END;
      BufferPtr := 0
    END;
    CurByte := ORD(Buffer[BufferPtr]);
    INC(BufferPtr)
  END;
  h := SYSTEM.LSH(CurByte, -CurBitNr) MOD 2;
  DEC(CurBitNr);
  IF CurBitNr < 0 THEN CurBitNr := 7 END;
  RETURN h
END InputBit;

PROCEDURE InputBits(VAR R: Files.Rider; count: LONGINT): LONGINT;
VAR i, h: LONGINT;
BEGIN
  h := 0;
  i := count-1;
  WHILE i >= 0 DO
    IF CurBitNr = 7 THEN
      IF BufferPtr = BufferSize THEN
        Files.ReadBytes(R, Buffer, BufferSize);
        INC(Len, BufferSize);
        IF Len >= maxLen + BufferSize THEN Err := TRUE END;
        BufferPtr := 0
      END;
      CurByte := ORD(Buffer[BufferPtr]);
      INC(BufferPtr)
    END;
    IF SYSTEM.LSH(CurByte, -CurBitNr) MOD 2 = 1 THEN
      h := h + SYSTEM.LSH(1, i)
    END;
    DEC(CurBitNr);
    IF CurBitNr < 0 THEN CurBitNr := 7 END;
    DEC(i)
  END;
  RETURN h
END InputBits;

PROCEDURE OutputBit(VAR R: Files.Rider; bit: LONGINT);
BEGIN
  IF bit = 1 THEN
    CurByte := CurByte + SYSTEM.LSH(1, CurBitNr)
  END;
  DEC(CurBitNr);
  IF CurBitNr < 0 THEN
    Buffer[BufferPtr] := CHR(CurByte);
    INC(BufferPtr);
    IF BufferPtr = BufferSize THEN
      Files.WriteBytes(R, Buffer, BufferSize);
      INC(Len, BufferSize);
      BufferPtr := 0
    END;
    CurBitNr := 7;
    CurByte := 0
  END
END OutputBit;

PROCEDURE OutputBits(VAR R: Files.Rider; bits, count: LONGINT);
VAR i, h: LONGINT;
BEGIN
  h := bits;
  i := count-1;
  WHILE i >= 0 DO
    IF SYSTEM.LSH(h, -i) MOD 2 = 1 THEN
      CurByte := CurByte + SYSTEM.LSH(1, CurBitNr)
    END;
    DEC(CurBitNr);
    IF CurBitNr < 0 THEN
      Buffer[BufferPtr] := CHR(CurByte);
      INC(BufferPtr);
      IF BufferPtr = BufferSize THEN
        Files.WriteBytes(R, Buffer, BufferSize);
        INC(Len, BufferSize);
        BufferPtr := 0
      END;
      CurBitNr := 7;
      CurByte := 0
    END;
    DEC(i)
  END
END OutputBits;

PROCEDURE Compress(VAR Input, Output: Files.Rider; maxbytes: LONGINT);
VAR i, lookAheadBytes, currentPosition, replaceCount, matchLength, matchPosition: INTEGER;
    ch: CHAR; bytesread: LONGINT;
BEGIN
  Init();
  bytesread := 0;
  currentPosition := 1;
  i := 0;
  WHILE (i < LookAheadSize) & ~Input.eof & (bytesread < maxbytes) DO
    Files.Read(Input, ch);
    INC(bytesread);
    Window[currentPosition+i] := ch;
    INC(i)
  END;
  IF Input.eof OR (bytesread >= maxbytes) THEN DEC(i) END;
  lookAheadBytes := i;
  (* Rest of compression algorithm *)
END Compress;

PROCEDURE Expand(VAR Input, Output: Files.Rider);
VAR
  i, currentPosition: INTEGER;
  matchLength, matchPosition: INTEGER;
  ch: CHAR;
BEGIN
  Err := FALSE;
  Init;
  currentPosition := 1;
  LOOP
    IF InputBit(Input) # 0 THEN
      ch := CHR(InputBits(Input, 8));
      Files.Write(Output, ch);
      Window[currentPosition] := ch;
      currentPosition := (currentPosition+1) MOD (WindowSize-1)
    ELSE
      (* Cast LONGINT to INTEGER for window indices *)
      matchPosition := SHORT(InputBits(Input, IndexBitCount));
      IF matchPosition = EndOfStream THEN EXIT END;
      matchLength := SHORT(InputBits(Input, LengthBitCount));
      INC(matchLength, BreakEven);
      i := 0;
      WHILE i <= matchLength DO
        ch := Window[matchPosition+i];
        Files.Write(Output, ch);
        Window[currentPosition] := ch;
        currentPosition := (currentPosition+1) MOD (WindowSize-1);
        INC(i)
      END
    END;
    IF Err THEN RETURN END
  END
END Expand;

PROCEDURE Directory*(archive: ARRAY OF CHAR; detailed: BOOLEAN);
VAR ArcF: Files.File; R: Files.Rider; h: Header; err: BOOLEAN;
BEGIN
  ArcF := Files.Old(archive);
  IF ArcF # NIL THEN
    Files.Set(R, ArcF, 0);
    ReadHeader(R, h, err);
    WHILE (h.name # EOFName) & ~err DO
      Out.String(h.name);
      IF detailed THEN
        Out.String("  Size: "); Out.Int(h.length, 0);
        Out.String("  Ratio: "); Out.Real(h.ratio, 0); Out.String("%");
      END;
      Out.Ln;
      Files.Set(R, ArcF, Files.Pos(R) + h.length);
      ReadHeader(R, h, err)
    END;
    Files.Close(ArcF);
    IF err THEN Out.String(err1); Out.Ln END;
  ELSE
    Out.String(archive); Out.String(err2); Out.Ln;
  END;
END Directory;

PROCEDURE Add*(archive: ARRAY OF CHAR; files: FileUtil.FileList);
VAR ArcF, AddF: Files.File; Ra, RF: Files.Rider; h: Header;
    pos: LONGINT; nl: FileUtil.FileList; err: BOOLEAN;
    success: BOOLEAN;
BEGIN
  ArcF := Files.Old(archive);
  IF ArcF = NIL THEN
    ArcF := Files.New(archive);
    Files.Set(Ra, ArcF, 0);
    (* Write archive header *)
  END;

  nl := files;
  WHILE nl # NIL DO
    AddF := Files.Old(nl.name);
    IF AddF # NIL THEN
      Files.Set(RF, AddF, 0);
      COPY(nl.name, h.name);
      WriteHeader(Ra, h);
      (* Compress and add file *)
      Files.Close(AddF);
    ELSE
      Out.String(nl.name); Out.String(err2); Out.Ln;
    END;
    nl := nl.next;
  END;
  Files.Close(ArcF);
END Add;

PROCEDURE Extract*(archive: ARRAY OF CHAR; files: FileUtil.FileList);
VAR ArcF, AddF: Files.File; Ra, RF: Files.Rider;
    h: Header; pos: LONGINT; found: BOOLEAN; nl: FileUtil.FileList;
    err: BOOLEAN;
BEGIN
  ArcF := Files.Old(archive);
  IF ArcF # NIL THEN
    Files.Set(Ra, ArcF, 0);
    ReadHeader(Ra, h, err);
    nl := files;
    WHILE (h.name # EOFName) & ~err & (nl # NIL) DO
      IF h.name = nl.name THEN
        AddF := Files.New(nl.name);
        Files.Set(RF, AddF, 0);
        Expand(Ra, RF);
        Files.Close(AddF);
        found := TRUE;
      END;
      Files.Set(Ra, ArcF, Files.Pos(Ra) + h.length);
      ReadHeader(Ra, h, err);
      nl := nl.next;
    END;
    Files.Close(ArcF);
    IF ~found THEN Out.String(nl.name); Out.String(err2); Out.Ln END;
  ELSE
    Out.String(archive); Out.String(err2); Out.Ln;
  END;
END Extract;

PROCEDURE ExtractAll*(archive: ARRAY OF CHAR);
VAR ArcF, AddF: Files.File; Ra, RF: Files.Rider; h: Header; err: BOOLEAN;
BEGIN
  ArcF := Files.Old(archive);
  IF ArcF # NIL THEN
    Files.Set(Ra, ArcF, 0);
    ReadHeader(Ra, h, err);
    WHILE (h.name # EOFName) & ~err DO
      AddF := Files.New(h.name);
      Files.Set(RF, AddF, 0);
      Expand(Ra, RF);
      Files.Close(AddF);
      Files.Set(Ra, ArcF, Files.Pos(Ra) + h.length);
      ReadHeader(Ra, h, err)
    END;
    Files.Close(ArcF);
    IF err THEN Out.String(err1); Out.Ln END;
  ELSE
    Out.String(archive); Out.String(err2); Out.Ln;
  END;
END ExtractAll;

PROCEDURE Delete*(archive: ARRAY OF CHAR; files: FileUtil.FileList);
VAR
  ArcF, TmpF: Files.File;
  Ra, Rt: Files.Rider;
  h: Header;
  pos: LONGINT;
  nl: FileUtil.FileList;
  err: BOOLEAN;
  success: BOOLEAN;
  found: BOOLEAN;
BEGIN
  ArcF := Files.Old(archive);
  IF ArcF # NIL THEN
    TmpF := Files.New(Temp);
    Files.Set(Rt, TmpF, 0);
    Files.Set(Ra, ArcF, 0);
    ReadHeader(Ra, h, err);
    WHILE (h.name # EOFName) & ~err DO
      nl := files;
      found := FALSE;
      WHILE nl # NIL DO
        IF h.name = nl.name THEN
          found := TRUE;
        END;
        nl := nl.next;
      END;

      IF ~found THEN
        WriteHeader(Rt, h);
        Files.Set(Ra, ArcF, pos);
        CopyFrom(Ra, Rt, h.length);
      END;

      pos := Files.Pos(Ra);
      Files.Set(Ra, ArcF, pos + h.length);
      ReadHeader(Ra, h, err)
    END;

    (* Finalize temp archive and replace original *)
    Files.Close(ArcF);
    Files.Close(TmpF);
    success := FileUtil.DeleteFile(archive);
    success := FileUtil.RenameFile(Temp, archive);
  ELSE
    Out.String(archive); Out.String(err2); Out.Ln;
  END;
END Delete;

BEGIN
END ArcTool.
