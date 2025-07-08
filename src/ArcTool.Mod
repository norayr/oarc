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
  err3 = " failed to create file";
  err4 = " failed to open archive";
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
    ratio: REAL;
    extensions: LONGINT
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
  help: INTEGER;

PROCEDURE InitTree(r: INTEGER);
BEGIN
  Tree[TreeRoot].largerChild := r;
  Tree[r].parent := TreeRoot;
  Tree[r].largerChild := Unused;
  Tree[r].smallerChild := Unused;
END InitTree;

PROCEDURE ContractNode(oldNode, newNode: INTEGER);
VAR parent: INTEGER;
BEGIN
  parent := Tree[oldNode].parent;
  Tree[newNode].parent := parent;
  IF Tree[parent].largerChild = oldNode THEN
    Tree[parent].largerChild := newNode
  ELSE
    Tree[parent].smallerChild := newNode
  END;
  Tree[oldNode].parent := Unused;
END ContractNode;

PROCEDURE ReplaceNode(oldNode, newNode: INTEGER);
VAR parent: INTEGER;
BEGIN
  parent := Tree[oldNode].parent;
  IF Tree[parent].smallerChild = oldNode THEN
    Tree[parent].smallerChild := newNode
  ELSE
    Tree[parent].largerChild := newNode
  END;
  Tree[newNode] := Tree[oldNode];
  Tree[Tree[newNode].smallerChild].parent := newNode;
  Tree[Tree[newNode].largerChild].parent := newNode;
  Tree[oldNode].parent := Unused;
END ReplaceNode;

PROCEDURE FindNextNode(node: INTEGER): INTEGER;
VAR next: INTEGER;
BEGIN
  next := Tree[node].smallerChild;
  WHILE Tree[next].largerChild # Unused DO
    next := Tree[next].largerChild;
  END;
  RETURN next;
END FindNextNode;

PROCEDURE DeleteString(p: INTEGER);
VAR replacement: INTEGER;
BEGIN
  IF Tree[p].parent = Unused THEN RETURN; END;
  IF Tree[p].largerChild = Unused THEN
    ContractNode(p, Tree[p].smallerChild)
  ELSIF Tree[p].smallerChild = Unused THEN
    ContractNode(p, Tree[p].largerChild)
  ELSE
    replacement := FindNextNode(p);
    DeleteString(replacement);
    ReplaceNode(p, replacement);
  END;
END DeleteString;

PROCEDURE AddString(newNode: INTEGER; VAR matchPosition: INTEGER): INTEGER;
VAR i, testNode, delta, matchLength, child: INTEGER;
BEGIN
  IF newNode = EndOfStream THEN RETURN 0; END;
  testNode := Tree[TreeRoot].largerChild;
  matchLength := 0;
  LOOP
    i := 0;
    delta := 0;
    WHILE (i < LookAheadSize) & (delta = 0) DO
      delta := ORD(Window[newNode + i]) - ORD(Window[testNode + i]);
      INC(i);
    END;
    IF delta # 0 THEN DEC(i); END;
    IF i > matchLength THEN
      matchLength := i;
      matchPosition := testNode;
      IF matchLength >= LookAheadSize THEN
        ReplaceNode(testNode, newNode);
        RETURN matchLength;
      END;
    END;
    IF delta >= 0 THEN
      child := Tree[testNode].largerChild
    ELSE
      child := Tree[testNode].smallerChild
    END;
    IF child = Unused THEN
      IF delta >= 0 THEN
        Tree[testNode].largerChild := newNode
      ELSE
        Tree[testNode].smallerChild := newNode
      END;
      Tree[newNode].parent := testNode;
      Tree[newNode].largerChild := Unused;
      Tree[newNode].smallerChild := Unused;
      RETURN matchLength;
    END;
    testNode := child;
  END;
END AddString;

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
  (* Check for document header (magic bytes) *)
  IF (ORD(h.name[0]) = 0F7H) & (ORD(h.name[1]) = 07H) THEN
    (* Skip 32-byte document header *)
    Files.Set(R, Files.Base(R), pos+26);
    ReadHeader(R, h, err);
    RETURN
  END;

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
  (* Handle extensions *)
  IF h.length < 0 THEN
    Files.ReadLInt(R, h.extensions);
    h.length := -h.length;
  ELSE
    h.extensions := 0;
  END;
  IF (h.ratio > 0.0) & (h.ratio < 1000000.0) THEN
    pos := 0; chk := 0;
    WHILE pos < 32 DO
      chk := chk + ORD(h.name[pos]);
      INC(pos)
    END;
    chk := chk + h.length + ENTIER(h.ratio) + (h.time MOD xx) + (h.date MOD xx) + h.extensions;
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

PROCEDURE CreateArchiveHeader(VAR R: Files.Rider);
VAR
  h: Header;  (* Add local header variable *)
BEGIN
  (* Initialize with empty header *)
  h.name := "OberonArchive";
  h.length := 0;
  h.check := 0;
  h.date := 0;
  h.time := 0;
  h.ratio := 0.0;
  h.extensions := 0;
  WriteHeader(R, h);
END CreateArchiveHeader;

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
VAR
  i, lookAheadBytes, currentPosition, replaceCount, matchLength, matchPosition: INTEGER;
  ch: CHAR;
  bytesread: LONGINT;
BEGIN
  Init();
  bytesread := 0;
  currentPosition := 1;
  i := 0;
  WHILE (i < LookAheadSize) & ~Input.eof & (bytesread < maxbytes) DO
    Files.Read(Input, ch);
    INC(bytesread);
    Window[currentPosition+i] := ch;
    (* Maintain mirror for lookahead buffer *)
    IF currentPosition+i < RawLookAheadSize+1 THEN
      Window[currentPosition+i+WindowSize-1] := ch;
    END;
    INC(i)
  END;
  IF Input.eof OR (bytesread >= maxbytes) THEN DEC(i) END;
  lookAheadBytes := i;

  (* Initialize tree with first position *)
  (*
  Tree[TreeRoot].largerChild := currentPosition;
  Tree[currentPosition].parent := TreeRoot;
  Tree[currentPosition].largerChild := Unused;
  Tree[currentPosition].smallerChild := Unused;
  *)
  InitTree(currentPosition);

  matchLength := 0;
  matchPosition := 0;
  WHILE lookAheadBytes > 0 DO
    IF matchLength > lookAheadBytes THEN
      matchLength := lookAheadBytes
    END;
    IF matchLength <= BreakEven THEN
      replaceCount := 1;
      OutputBit(Output, 1);
      OutputBits(Output, ORD(Window[currentPosition]), 8)
    ELSE
      OutputBit(Output, 0);
      OutputBits(Output, matchPosition, IndexBitCount);
      OutputBits(Output, matchLength-(BreakEven+1), LengthBitCount);
      replaceCount := matchLength
    END;
    i := 0;
    WHILE i < replaceCount DO
      DeleteString((currentPosition+LookAheadSize) MOD (WindowSize-1));
      IF ~Input.eof & (bytesread < maxbytes) THEN
        Files.Read(Input, ch);
        INC(bytesread);
        Window[currentPosition+LookAheadSize] := ch;
        Window[(currentPosition+LookAheadSize) MOD (WindowSize-1)] := ch;
      ELSE
        DEC(lookAheadBytes)
      END;
      currentPosition := (currentPosition+1) MOD (WindowSize-1);
      IF currentPosition = 0 THEN currentPosition := WindowSize-1 END;
      IF lookAheadBytes # 0 THEN
        matchLength := AddString(currentPosition, matchPosition)
      END;
      INC(i)
    END
  END;
  OutputBit(Output, 0);
  OutputBits(Output, EndOfStream, IndexBitCount)
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
      (* Maintain mirror for lookahead buffer *)
      IF currentPosition < RawLookAheadSize+1 THEN
        Window[currentPosition+WindowSize-1] := ch;
      END;
      currentPosition := (currentPosition+1) MOD (WindowSize-1);
      IF currentPosition = 0 THEN currentPosition := WindowSize-1 END;
    ELSE
      matchPosition := SHORT(InputBits(Input, IndexBitCount));
      IF matchPosition = EndOfStream THEN EXIT END;
      matchLength := SHORT(InputBits(Input, LengthBitCount));
      INC(matchLength, BreakEven);
      i := 0;
      WHILE i <= matchLength DO
        ch := Window[(matchPosition+i) MOD (WindowSize-1)];
        Files.Write(Output, ch);
        Window[currentPosition] := ch;
        (* Maintain mirror for lookahead buffer *)
        IF currentPosition < RawLookAheadSize+1 THEN
          Window[currentPosition+WindowSize-1] := ch;
        END;
        currentPosition := (currentPosition+1) MOD (WindowSize-1);
        IF currentPosition = 0 THEN currentPosition := WindowSize-1 END;
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
    Files.Register(ArcF);
    Files.Close(ArcF);
    IF err THEN Out.String(err1); Out.Ln END;
  ELSE
    Out.String(archive); Out.String(err2); Out.Ln;
  END;
END Directory;

PROCEDURE Add*(archive: ARRAY OF CHAR; files: FileUtil.FileList);
VAR
  ArcF, AddF: Files.File;
  Ra, RF: Files.Rider;
  h: Header;
  nl: FileUtil.FileList;
  len, startPos, compressedLength: LONGINT;
  archiveExists: BOOLEAN;
  percent: REAL;
BEGIN
  (* Check if archive exists *)
  ArcF := Files.Old(archive);
  archiveExists := (ArcF # NIL);

  IF ~archiveExists THEN
    (* Create new archive *)
    ArcF := Files.New(archive);
    IF ArcF = NIL THEN
      Out.String("Failed to create archive: "); Out.String(archive); Out.Ln;
      RETURN;
    END;
    Files.Set(Ra, ArcF, 0);
  ELSE
    (* Open existing archive *)
    Files.Set(Ra, ArcF, Files.Length(ArcF));
  END;

  nl := files;
  WHILE nl # NIL DO
    AddF := Files.Old(nl.name);
    IF AddF = NIL THEN
      Out.String(nl.name); Out.String(err2); Out.Ln;
    ELSE
      Files.Set(RF, AddF, 0);
      len := Files.Length(AddF);

      (* Remember start position for header update *)
      startPos := Files.Pos(Ra);

      (* Write initial header *)
      COPY(nl.name, h.name);
      h.length := len;
      h.ratio := 0.0; (* Will be updated later *)
      WriteHeader(Ra, h);

      (* Compress and add file content *)
      Compress(RF, Ra, len);
      compressedLength := Files.Pos(Ra) - startPos - 56; (* Header size is 56 bytes *)

      (* Calculate compression ratio *)
      IF len > 0 THEN
        h.ratio := 100.0 * compressedLength / len;
      ELSE
        h.ratio := 0.0;
      END;

      (* Update header with actual ratio *)
      Files.Set(Ra, ArcF, startPos);
      WriteHeader(Ra, h);
      Files.Set(Ra, ArcF, Files.Pos(Ra) + compressedLength);

      Files.Register(AddF);
      Files.Close(AddF);
      Out.String("Added: "); Out.String(nl.name);
      Out.String(" ("); Out.Int(compressedLength, 0); Out.String(" bytes, ");

      (* Output ratio using available Out.Real *)
      percent := h.ratio;
      Out.Real(percent, 2); (* 2 decimal places *)
      Out.String("% ratio)"); Out.Ln;
    END;
    nl := nl.next;
  END;

  (* Write end-of-archive marker *)
  h.name := EOFName;
  h.length := 0;
  h.ratio := 0.0;
  WriteHeader(Ra, h);

  Files.Register(ArcF);
  Files.Close(ArcF);
END Add;

PROCEDURE Extract*(archive: ARRAY OF CHAR; files: FileUtil.FileList);
VAR
  ArcF, AddF: Files.File;
  Ra, RF: Files.Rider;
  h: Header;
  err: BOOLEAN;
  nl: FileUtil.FileList;
  found: BOOLEAN;
BEGIN
  ArcF := Files.Old(archive);
  IF ArcF = NIL THEN
    Out.String(archive); Out.String(err4); Out.Ln;
    RETURN;
  END;

  Files.Set(Ra, ArcF, 0);
  ReadHeader(Ra, h, err);

  WHILE (h.name # EOFName) & ~err DO
    nl := files;
    found := FALSE;

    (* Check all requested files *)
    WHILE (nl # NIL) & ~found DO
      IF h.name = nl.name THEN
        found := TRUE;
        AddF := Files.New(nl.name);
        IF AddF = NIL THEN
          Out.String("Failed to create: "); Out.String(nl.name); Out.Ln;
        ELSE
          Files.Set(RF, AddF, 0);
          Expand(Ra, RF);
          Files.Register(AddF);
          Files.Close(AddF);
          Out.String("Extracted: "); Out.String(nl.name); Out.Ln;
        END;
      END;
      nl := nl.next;
    END;

    (* Skip file if not extracted *)
    IF ~found THEN
      Files.Set(Ra, ArcF, Files.Pos(Ra) + h.length);
    END;

    ReadHeader(Ra, h, err);
  END;
  Files.Register(ArcF);
  Files.Close(ArcF);
END Extract;

PROCEDURE ExtractAll*(archive: ARRAY OF CHAR);
VAR
  ArcF, AddF: Files.File;
  Ra, RF: Files.Rider;
  h: Header;
  err: BOOLEAN;
BEGIN
  ArcF := Files.Old(archive);
  IF ArcF = NIL THEN
    Out.String(archive); Out.String(err4); Out.Ln;
    RETURN;
  END;

  Files.Set(Ra, ArcF, 0);
  ReadHeader(Ra, h, err);

  WHILE (h.name # EOFName) & ~err DO
    AddF := Files.New(h.name);
    IF AddF = NIL THEN
      Out.String("Failed to create: "); Out.String(h.name); Out.Ln;
    ELSE
      Files.Set(RF, AddF, 0);
      Expand(Ra, RF);
      Files.Register(AddF);
      Files.Close(AddF);
      Out.String("Extracted: "); Out.String(h.name); Out.Ln;
    END;

    Files.Set(Ra, ArcF, Files.Pos(Ra) + h.length);
    ReadHeader(Ra, h, err);
  END;

  Files.Register(ArcF);
  Files.Close(ArcF);
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
    Files.Register(ArcF);
    Files.Close(ArcF);
    Files.Register(TmpF);
    Files.Close(TmpF);
    success := FileUtil.DeleteFile(archive);
    success := FileUtil.RenameFile(Temp, archive);
  ELSE
    Out.String(archive); Out.String(err2); Out.Ln;
  END;
END Delete;

BEGIN
END ArcTool.
