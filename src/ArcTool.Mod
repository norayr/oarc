MODULE ArcTool;
IMPORT Files, FileUtil, Out, Platform, Strings, SYSTEM;

CONST
  BufferSize- = 4096;
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

 (* extension bits *)
  encryption = 0;  (* bit 0 in extensions set means file is encrypted *)

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
    extensions: SET
  END;
  EnumProc = PROCEDURE (h: Header; VAR stop: BOOLEAN);

  (* now crypt related type *)

  CryptProc* = PROCEDURE (VAR Rin: Files.Rider; nIn: LONGINT;
                          VAR Rout: Files.Rider; key: ARRAY OF CHAR;
                          VAR res: INTEGER);

  (*CryptProc* = Crypt0.CryptProc;*)

VAR
  Buffer: ARRAY BufferSize OF CHAR;
  Window: ARRAY WindowSize+RawLookAheadSize+1 OF CHAR;
  Tree: ARRAY WindowSize+1 OF Node;
  CurBitNr-, Len-, maxLen-: LONGINT;
  CurByte-: LONGINT;
  BufferPtr: LONGINT;
  Err: BOOLEAN;
  help: INTEGER;

  (* and crypt related variables *)
  Decrypt*, Encrypt*: CryptProc;
  curKey: ARRAY 64 OF CHAR;


(* and crypt related procedures *)

PROCEDURE SetLen*(l: LONGINT);
BEGIN
  Len := l
END SetLen;

PROCEDURE SetMaxLen*(l: LONGINT);
BEGIN
  maxLen := l
END SetMaxLen;

PROCEDURE SetBufferPtr*(l: LONGINT);
BEGIN
  BufferPtr := l
END SetBufferPtr;

PROCEDURE SetCurBitNr*(l: LONGINT);
BEGIN
  CurBitNr := l
END SetCurBitNr;

PROCEDURE SetCurByte*(l: LONGINT);
BEGIN
  CurByte := l;
END SetCurByte;

PROCEDURE SetEncryption*(key: ARRAY OF CHAR);
BEGIN
  COPY(key, curKey)
END SetEncryption;

PROCEDURE SetDecryption*(key: ARRAY OF CHAR);
BEGIN
  COPY(key, curKey)
END SetDecryption;

PROCEDURE ClearEncryption*;
BEGIN
  curKey := "";
  Decrypt := NIL;
  Encrypt := NIL
END ClearEncryption;

(* tree procedures *)
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
  i := 0;
  WHILE i + BufferSize <= len DO
    Files.ReadBytes(Ri, Buffer, BufferSize);
    Files.WriteBytes(Ro, Buffer, BufferSize);
    INC(i, BufferSize);
  END;
  IF i < len THEN
    Files.ReadBytes(Ri, Buffer, len - i);
    Files.WriteBytes(Ro, Buffer, len - i);
  END;
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
    Files.ReadSet(R, h.extensions);
    h.length := -h.length;
  ELSE
    h.extensions := {};
  END;
  IF (h.ratio > 0.0) & (h.ratio < 1000000.0) THEN
    pos := 0; chk := 0;
    WHILE pos < 32 DO
      chk := chk + ORD(h.name[pos]);
      INC(pos)
    END;
    h.name[31] := 0X; (* Ensure null termination *)
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
  WHILE (i < 32) & (h.name[i] # 0X) DO
    h.check := h.check + ORD(h.name[i]);
    INC(i)
  END;
  WHILE i < 32 DO
    h.name[i] := 0X; INC(i)
  END;
  Platform.GetClock(h.time, h.date);
  h.check := h.check + h.length + (h.time MOD xx) + (h.date MOD xx) + ENTIER(h.ratio);
  Files.WriteBytes(R, h.name, 32);
  IF h.extensions # {} THEN
    Files.WriteLInt(R, -h.length);
  ELSE
    Files.WriteLInt(R, h.length);
  END;
  Files.WriteLInt(R, h.check);
  Files.WriteLInt(R, h.date);
  Files.WriteLInt(R, h.time);
  Files.WriteReal(R, h.ratio);
  IF h.extensions # {} THEN
    Files.WriteSet(R, h.extensions);
  END;
END WriteHeader;

PROCEDURE InputBit(VAR R: Files.Rider): LONGINT;
VAR h: LONGINT;
BEGIN
  IF CurBitNr = 7 THEN
    IF BufferPtr = BufferSize THEN
      Files.ReadBytes(R, Buffer, BufferSize);
      INC(Len, BufferSize - R.res); (* Account for partial reads *)
      IF Len >= maxLen + BufferSize THEN Err := TRUE END;
      BufferPtr := 0
    END;
    CurByte := ORD(Buffer[BufferPtr]);
    INC(BufferPtr)
  END;
  h := ASH(CurByte, -CurBitNr) MOD 2;
  DEC(CurBitNr);
  IF CurBitNr < 0 THEN CurBitNr := 7 END;
  RETURN h
END InputBit;

PROCEDURE FlushBits*(VAR R: Files.Rider);
BEGIN
  IF CurBitNr # 7 THEN
    Buffer[BufferPtr] := CHR(CurByte);
    INC(BufferPtr);
    CurBitNr := 7;
    CurByte := 0;
  END;
  IF BufferPtr > 0 THEN
    Files.WriteBytes(R, Buffer, BufferPtr);
    INC(Len, BufferPtr);
    BufferPtr := 0;
  END;
END FlushBits;

PROCEDURE InputBits(VAR R: Files.Rider; count: LONGINT): LONGINT;
VAR i, h: LONGINT;
BEGIN
  h := 0;
  i := count-1;
  WHILE i >= 0 DO
    IF CurBitNr = 7 THEN
      IF BufferPtr = BufferSize THEN
        Files.ReadBytes(R, Buffer, BufferSize);
        INC(Len, BufferSize - R.res); (* Account for partial reads *)
        IF Len >= maxLen + BufferSize THEN Err := TRUE END;
        BufferPtr := 0
      END;
      CurByte := ORD(Buffer[BufferPtr]);
      INC(BufferPtr)
    END;
    IF ASH(CurByte, -CurBitNr) MOD 2 = 1 THEN
      h := h + ASH(1, i)
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
    CurByte := CurByte + ASH(1, CurBitNr)
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
    IF ASH(h, -i) MOD 2 = 1 THEN
      CurByte := CurByte + ASH(1, CurBitNr)
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

PROCEDURE Compress*(VAR Input, Output: Files.Rider; maxbytes: LONGINT);
VAR
  i, lookAheadBytes, currentPosition, replaceCount, matchLength, matchPosition: INTEGER;
  ch: CHAR;
  bytesread: LONGINT;
  validRead: BOOLEAN;
BEGIN
  Init();
  bytesread := 0;
  currentPosition := 1;
  i := 0;

  (* Read initial lookahead buffer *)
  WHILE (i < LookAheadSize) & (bytesread < maxbytes) DO
    Files.Read(Input, ch);
    IF ~Input.eof THEN
      (* Successful read *)
      INC(bytesread);
      Window[currentPosition+i] := ch;
      IF currentPosition+i < RawLookAheadSize+1 THEN
        Window[currentPosition+i+WindowSize-1] := ch;
      END;
      INC(i)
    ELSE
      (* EOF reached, exit loop *)
      bytesread := maxbytes; (* Force loop exit *)
    END
  END;
  lookAheadBytes := i;  (* No DEC(i) needed! *)

  (* Initialize tree with first position *)
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

      (* Try to read next byte *)
      validRead := FALSE;
      IF bytesread < maxbytes THEN
        Files.Read(Input, ch);
        IF ~Input.eof THEN
          INC(bytesread);
          Window[currentPosition+LookAheadSize] := ch;
          Window[(currentPosition+LookAheadSize) MOD (WindowSize-1)] := ch;
          validRead := TRUE
        END
      END;

      IF ~validRead THEN
        DEC(lookAheadBytes)
      END;

      currentPosition := (currentPosition+1) MOD (WindowSize-1);
      IF lookAheadBytes # 0 THEN
        matchLength := AddString(currentPosition, matchPosition)
      END;
      INC(i)
    END
  END;
  OutputBit(Output, 0);
  OutputBits(Output, EndOfStream, IndexBitCount);
  FlushBits(Output);
END Compress;

PROCEDURE Expand*(VAR Input, Output: Files.Rider);
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
    ELSE
      matchPosition := SHORT(InputBits(Input, IndexBitCount));
      IF matchPosition = EndOfStream THEN EXIT END;
      matchLength := SHORT(InputBits(Input, LengthBitCount));
      INC(matchLength, BreakEven);  (* Not BreakEven+1 *)
      i := 0;
      WHILE i <= matchLength DO  (* Use <= not < *)
        ch := Window[matchPosition+i];
        Files.Write(Output, ch);
        Window[currentPosition] := ch;
        (* Maintain mirror for lookahead buffer *)
        IF currentPosition < RawLookAheadSize+1 THEN
          Window[currentPosition+WindowSize-1] := ch;
        END;
        currentPosition := (currentPosition+1) MOD (WindowSize-1);
        INC(i)
      END
    END;
    IF Err THEN RETURN END
  END
END Expand;

PROCEDURE Directory*(archive: ARRAY OF CHAR; detailed: BOOLEAN);
VAR
  ArcF: Files.File;
  R: Files.Rider;
  h: Header;
  err: BOOLEAN;
  encryptedCount, totalCount: INTEGER;
BEGIN
  ArcF := Files.Old(archive);
  IF ArcF # NIL THEN
    encryptedCount := 0;
    totalCount := 0;
    Files.Set(R, ArcF, 0);
    ReadHeader(R, h, err);
    WHILE (h.name # EOFName) & ~err DO
      Out.String(h.name);
      IF encryption IN h.extensions THEN  (* Check encryption bit *)
        Out.String(" [ENCRYPTED]");
        INC(encryptedCount);
      END;
      IF detailed THEN
        Out.String("  Size: "); Out.Int(h.length, 0);
        Out.String("  Ratio: "); Out.Real(h.ratio, 0); Out.String("%");
      END;
      Out.Ln;
      INC(totalCount);
      Files.Set(R, ArcF, Files.Pos(R) + h.length);
      ReadHeader(R, h, err)
    END;
    Files.Close(ArcF);

    IF encryptedCount > 0 THEN
      Out.Ln;
      Out.String("Note: "); Out.Int(encryptedCount, 0);
      Out.String(" of "); Out.Int(totalCount, 0);
      Out.String(" files are encrypted.");
      Out.Ln;
    END;

    IF err THEN Out.String(err1); Out.Ln END;
  ELSE
    Out.String(archive); Out.String(err2); Out.Ln;
  END;
END Directory;

PROCEDURE Add*(archive: ARRAY OF CHAR; files: FileUtil.FileList);
VAR
  ArcF, AddF, tempFile, tempFile2: Files.File;
  Ra, RF, Rtemp, Rtemp2: Files.Rider;
  h: Header;
  nl: FileUtil.FileList;
  len, pos, eofPos, savePos, encLen: LONGINT;
  archiveExists: BOOLEAN;
  err: BOOLEAN;
  addL, ha: FileUtil.FileList;
  found: BOOLEAN;
  changed: BOOLEAN;
  tempName, tempName2: ARRAY 256 OF CHAR;
  res: INTEGER;
  success: BOOLEAN;
  i: INTEGER;
BEGIN
  changed := FALSE;
  ArcF := Files.Old(archive);
  archiveExists := (ArcF # NIL);

  IF ~archiveExists THEN
    ArcF := Files.New(archive);
    IF ArcF = NIL THEN RETURN END;
    Files.Set(Ra, ArcF, 0);
    eofPos := 0;
    addL := NIL;
  ELSE
    (* Build list of existing files and find EOF position *)
    addL := NIL;
    Files.Set(Ra, ArcF, 0);
    pos := 0;
    ReadHeader(Ra, h, err);
    WHILE (h.name # EOFName) & ~err DO
      (* Add to existing files list *)
      ha := FileUtil.NewFileNode(h.name);
      ha.next := addL;
      addL := ha;

      (* Move to next entry *)
      pos := Files.Pos(Ra) + h.length;
      Files.Set(Ra, ArcF, pos);
      ReadHeader(Ra, h, err);
    END;

    IF err THEN
      Out.String("Error reading archive"); Out.Ln;
      Files.Close(ArcF);
      RETURN;
    END;

    (* Remember EOF position - we'll write new entries here *)
    eofPos := pos;
  END;

  (* Position at EOF location to add new files *)
  Files.Set(Ra, ArcF, eofPos);

  (* Add new files *)
  nl := files;
  WHILE nl # NIL DO
    (* Check for duplicates *)
    ha := addL;
    found := FALSE;
    WHILE (ha # NIL) & ~found DO
      found := (ha.name = nl.name);
      ha := ha.next;
    END;

    IF found THEN
      Out.String("Warning: "); Out.String(nl.name);
      Out.String(" already exists in archive"); Out.Ln;
    ELSE
      AddF := Files.Old(nl.name);
      IF AddF = NIL THEN
        Out.String("    "); Out.String(nl.name); Out.String(err2); Out.Ln;
      ELSE
        success := TRUE;
        Files.Set(RF, AddF, 0);
        len := Files.Length(AddF);

        (* Generate unique temp name *)
        tempName := Temp;
        Files.Delete(tempName, res);
        tempFile := Files.New(tempName);
        IF tempFile = NIL THEN
          Out.String("Failed to create temp file"); Out.Ln;
          Files.Close(AddF);
          success := FALSE;
        END;

        IF success THEN
          Files.Set(Rtemp, tempFile, 0);

          (* Compress to temporary file *)
          Len := 0;
          BufferPtr := 0;
          CurBitNr := 7;
          CurByte := 0;
          Compress(RF, Rtemp, len);
          Files.Close(AddF);

          (* Register temp file to ensure all data is flushed *)
          Files.Register(tempFile);

          (* Write header with final values *)
          COPY(nl.name, h.name);
          h.extensions := {};

          (* Set encryption bit if using encryption *)
          IF (curKey # "") & (Encrypt # NIL) THEN
            INCL(h.extensions, encryption);
          END;

          (* Handle encryption if enabled *)
          IF (curKey # "") & (Encrypt # NIL) & (encryption IN h.extensions) THEN
            (* Create another temp file for encrypted data *)
            COPY(tempName, tempName2);
            i := 0;
            WHILE tempName2[i] # 0X DO INC(i) END;
            tempName2[i] := '2'; tempName2[i+1] := 0X;

            tempFile2 := Files.New(tempName2);
            IF tempFile2 = NIL THEN
              Out.String("Failed to create encryption temp file"); Out.Ln;
              Files.Close(tempFile);
              Files.Delete(tempName, res);
              success := FALSE;
            ELSE
              Files.Set(Rtemp, tempFile, 0);
              Files.Set(Rtemp2, tempFile2, 0);

              (* Encrypt the compressed data *)
              Encrypt(Rtemp, Len, Rtemp2, curKey, res);

              IF res = Done THEN
                Files.Register(tempFile2);
                encLen := Files.Length(tempFile2);

                (* Write header with encrypted length *)
                h.length := encLen;
                IF len > 0 THEN
                  h.ratio := 100.0 * encLen / len;
                ELSE
                  h.ratio := 100.0;
                END;
                WriteHeader(Ra, h);

                (* Copy encrypted data to archive *)
                Files.Set(Rtemp2, tempFile2, 0);
                CopyFrom(Rtemp2, Ra, encLen);

                Files.Close(tempFile2);
                Files.Delete(tempName2, res);

                Out.String("Added (encrypted): "); Out.String(nl.name);
                Out.String(" ("); Out.Int(encLen, 0); Out.String(" bytes, ");
                Out.Real(h.ratio, 2); Out.String("% ratio)"); Out.Ln;
              ELSE
                Out.String("Encryption failed for: "); Out.String(nl.name); Out.Ln;
                Files.Close(tempFile2);
                Files.Delete(tempName2, res);
                success := FALSE;
              END;
            END;

            Files.Close(tempFile);
            Files.Delete(tempName, res);
          ELSE
            (* No encryption - write header and copy compressed data directly *)
            h.length := Len;
            IF len > 0 THEN
              h.ratio := 100.0 * Len / len;
            ELSE
              h.ratio := 100.0;
            END;
            WriteHeader(Ra, h);

            Files.Set(Rtemp, tempFile, 0);
            CopyFrom(Rtemp, Ra, Len);
            Files.Close(tempFile);
            Files.Delete(tempName, res);

            Out.String("Added: "); Out.String(nl.name);
            Out.String(" ("); Out.Int(Len, 0); Out.String(" bytes, ");
            Out.Real(h.ratio, 2); Out.String("% ratio)"); Out.Ln;
          END;

          IF success THEN
            changed := TRUE;
            (* Add to tracking list AFTER successful addition *)
            ha := FileUtil.NewFileNode(nl.name);
            ha.next := addL;
            addL := ha;
          END;
        END;
      END;
    END;
    nl := nl.next;
  END;

  Files.Register(ArcF);  (* Always register to save changes *)
  Files.Close(ArcF);
END Add;

PROCEDURE Extract*(archive: ARRAY OF CHAR; files: FileUtil.FileList);
VAR
  ArcF, AddF, tempFile: Files.File;
  Ra, RF, Rtemp: Files.Rider;
  h: Header;
  err: BOOLEAN;
  nl: FileUtil.FileList;
  found: BOOLEAN;
  pos: LONGINT;
  res: INTEGER;
BEGIN
  ArcF := Files.Old(archive);
  IF ArcF = NIL THEN
    Out.String(archive); Out.String(err4); Out.Ln;
    RETURN;
  END;

  Files.Set(Ra, ArcF, 0);
  ReadHeader(Ra, h, err);

  WHILE (h.name # EOFName) & ~err DO
    pos := Files.Pos(Ra);
    nl := files;
    found := FALSE;

    (* Check all requested files *)
    WHILE (nl # NIL) & ~found DO
      IF h.name = nl.name THEN
        found := TRUE;

        (* Check for encryption *)
        IF encryption IN h.extensions THEN
          IF (curKey = "") OR (Decrypt = NIL) THEN
            Out.String("Cannot extract encrypted file: ");
            Out.String(nl.name);
            Out.String(" (encryption key needed)"); Out.Ln;
          ELSE
            (* Decrypt then expand *)
            AddF := Files.New(nl.name);
            IF AddF = NIL THEN
              Out.String("Failed to create: "); Out.String(nl.name); Out.Ln;
            ELSE
              (* Create temp file for decrypted data *)
              tempFile := Files.New("");
              IF tempFile # NIL THEN
                Files.Set(Rtemp, tempFile, 0);

                (* Decrypt from archive to temp file *)
                Decrypt(Ra, h.length, Rtemp, curKey, res);

                IF res = Done THEN
                  Files.Register(tempFile);
                  Files.Set(RF, AddF, 0);

                  (* Initialize expansion state *)
                  Len := 0;
                  BufferPtr := BufferSize;
                  CurBitNr := 7;
                  CurByte := 0;
                  maxLen := Files.Length(tempFile);

                  (* Expand from temp file to output *)
                  Files.Set(Rtemp, tempFile, 0);
                  Expand(Rtemp, RF);

                  Files.Register(AddF);
                  Files.Close(AddF);
                  Files.Close(tempFile);

                  Out.String("Extracted (decrypted): ");
                  Out.String(nl.name); Out.Ln;
                ELSE
                  Out.String("Decryption failed for: ");
                  Out.String(nl.name);
                  Out.String(" (wrong key?)"); Out.Ln;
                  Files.Close(AddF);
                  Files.Close(tempFile);
                END;
              ELSE
                Out.String("Failed to create temp file for decryption"); Out.Ln;
                Files.Close(AddF);
              END;
            END;
          END;
        ELSE
          (* Not encrypted - normal extraction *)
          AddF := Files.New(nl.name);
          IF AddF = NIL THEN
            Out.String("Failed to create: "); Out.String(nl.name); Out.Ln;
          ELSE
            Files.Set(RF, AddF, 0);

            (* Initialize expansion state *)
            Len := 0;
            BufferPtr := BufferSize;
            CurBitNr := 7;
            CurByte := 0;
            maxLen := h.length;

            Expand(Ra, RF);
            Files.Register(AddF);
            Files.Close(AddF);
            Out.String("Extracted: "); Out.String(nl.name); Out.Ln;
          END;
        END;
      END;
      nl := nl.next;
    END;

    (* Move to next entry *)
    Files.Set(Ra, ArcF, pos + h.length);
    ReadHeader(Ra, h, err);
  END;

  Files.Close(ArcF);
END Extract;

PROCEDURE ExtractAll*(archive: ARRAY OF CHAR);
VAR
  ArcF, AddF, tempFile: Files.File;
  Ra, RF, Rtemp: Files.Rider;
  h: Header;
  err: BOOLEAN;
  pos: LONGINT;
  res: INTEGER;
  skippedCount: INTEGER;
BEGIN
  ArcF := Files.Old(archive);
  IF ArcF = NIL THEN
    Out.String(archive); Out.String(err4); Out.Ln;
    RETURN;
  END;

  skippedCount := 0;
  Files.Set(Ra, ArcF, 0);
  ReadHeader(Ra, h, err);

  WHILE (h.name # EOFName) & ~err DO
    pos := Files.Pos(Ra);

    (* Check for encryption *)
    IF encryption IN h.extensions THEN
      IF (curKey = "") OR (Decrypt = NIL) THEN
        Out.String("Skipping encrypted file: ");
        Out.String(h.name);
        Out.String(" (encryption key needed)"); Out.Ln;
        INC(skippedCount);
      ELSE
        (* Decrypt then expand *)
        AddF := Files.New(h.name);
        IF AddF = NIL THEN
          Out.String("Failed to create: "); Out.String(h.name); Out.Ln;
        ELSE
          (* Create temp file for decrypted data *)
          tempFile := Files.New("");
          IF tempFile # NIL THEN
            Files.Set(Rtemp, tempFile, 0);

            (* Decrypt from archive to temp file *)
            Decrypt(Ra, h.length, Rtemp, curKey, res);

            IF res = Done THEN
              Files.Register(tempFile);
              Files.Set(RF, AddF, 0);

              (* Initialize expansion state *)
              Len := 0;
              BufferPtr := BufferSize;
              CurBitNr := 7;
              CurByte := 0;
              maxLen := Files.Length(tempFile);

              (* Expand from temp file to output *)
              Files.Set(Rtemp, tempFile, 0);
              Expand(Rtemp, RF);

              Files.Register(AddF);
              Files.Close(AddF);
              Files.Close(tempFile);

              Out.String("Extracted (decrypted): ");
              Out.String(h.name); Out.Ln;
            ELSE
              Out.String("Decryption failed for: ");
              Out.String(h.name);
              Out.String(" (wrong key?)"); Out.Ln;
              Files.Close(AddF);
              Files.Close(tempFile);
              INC(skippedCount);
            END;
          ELSE
            Out.String("Failed to create temp file for decryption"); Out.Ln;
            Files.Close(AddF);
            INC(skippedCount);
          END;
        END;
      END;
    ELSE
      (* Not encrypted - normal extraction *)
      AddF := Files.New(h.name);
      IF AddF = NIL THEN
        Out.String("Failed to create: "); Out.String(h.name); Out.Ln;
      ELSE
        Files.Set(RF, AddF, 0);

        (* Initialize expansion state *)
        Len := 0;
        BufferPtr := BufferSize;
        CurBitNr := 7;
        CurByte := 0;
        maxLen := h.length;

        Expand(Ra, RF);
        Files.Register(AddF);
        Files.Close(AddF);
        Out.String("Extracted: "); Out.String(h.name); Out.Ln;
      END;
    END;

    (* Move to next entry *)
    Files.Set(Ra, ArcF, pos + h.length);
    ReadHeader(Ra, h, err);
  END;

  Files.Close(ArcF);

  IF skippedCount > 0 THEN
    Out.Ln;
    Out.String("Note: Skipped "); Out.Int(skippedCount, 0);
    Out.String(" file(s). ");
    IF (curKey = "") OR (Decrypt = NIL) THEN
      Out.String("Encryption key required for extraction.");
    ELSE
      Out.String("Decryption failed (wrong key?).");
    END;
    Out.Ln;
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
  found: BOOLEAN;
  deleted: BOOLEAN;
  tempName: ARRAY 256 OF CHAR;
  res: INTEGER;
  i: INTEGER;
BEGIN
  ArcF := Files.Old(archive);
  IF ArcF = NIL THEN
    Out.String(archive); Out.String(err2); Out.Ln;
    RETURN;
  END;

  (* Create temp file with unique name *)
  COPY(Temp, tempName);
  i := 0;
  WHILE tempName[i] # 0X DO INC(i) END;
  tempName[i] := '.'; tempName[i+1] := 'd'; tempName[i+2] := 'e';
  tempName[i+3] := 'l'; tempName[i+4] := 0X;

  Files.Delete(tempName, res); (* Clean up any old temp file *)

  TmpF := Files.New(tempName);
  IF TmpF = NIL THEN
    Out.String("Failed to create temporary file"); Out.Ln;
    Files.Close(ArcF);
    RETURN;
  END;

  Files.Set(Rt, TmpF, 0);
  Files.Set(Ra, ArcF, 0);
  deleted := FALSE;

  ReadHeader(Ra, h, err);
  WHILE (h.name # EOFName) & ~err DO
    pos := Files.Pos(Ra);

    (* Check if this file should be deleted *)
    nl := files;
    found := FALSE;
    WHILE (nl # NIL) & ~found DO
      IF h.name = nl.name THEN
        found := TRUE;
        deleted := TRUE;
        Out.String("Deleted: "); Out.String(h.name); Out.Ln;
      END;
      nl := nl.next;
    END;

    IF ~found THEN
      (* Copy this entry to temp file *)
      WriteHeader(Rt, h);
      Files.Set(Ra, ArcF, pos);
      CopyFrom(Ra, Rt, h.length);
      Files.Set(Ra, ArcF, pos + h.length); (* Reset position for next read *)
    ELSE
      (* Skip this entry *)
      Files.Set(Ra, ArcF, pos + h.length);
    END;

    ReadHeader(Ra, h, err);
  END;

  IF err THEN
    Out.String(err1); Out.Ln;
    Files.Close(ArcF);
    Files.Close(TmpF);
    Files.Delete(tempName, res);
    RETURN;
  END;

  (* Close and save temp file *)
  Files.Register(TmpF);
  Files.Close(TmpF);
  Files.Close(ArcF);

  IF deleted THEN
    (* Try to delete original - may fail if file is cached *)
    Files.Delete(archive, res);
    (* Don't worry about delete errors - rename will overwrite anyway *)

    (* Rename temp to original - this atomically replaces the file *)
    Files.Rename(tempName, archive, res);
    IF res # 0 THEN
      (* This is the real error we care about *)
      Out.String("Error: could not update archive (error ");
      Out.Int(res, 0); Out.String(")"); Out.Ln;
      Out.String("Updated archive saved as: "); Out.String(tempName); Out.Ln;
    END;
  ELSE
    (* No files were deleted, remove temp file *)
    Files.Delete(tempName, res);
    Out.String("No matching files found for deletion"); Out.Ln;
  END;
END Delete;

BEGIN
  curKey := "";
  Decrypt := NIL;
  Encrypt := NIL;
END ArcTool.
