MODULE oarc;
IMPORT Args, Out, ArcTool, FileUtil, Modules, Crypt0;

VAR
  cmd: ARRAY 32 OF CHAR;
  archive: ARRAY 256 OF CHAR;
  i, argCount: INTEGER;
  files: FileUtil.FileList;
  lastFile: FileUtil.FileList;
  arg: ARRAY 256 OF CHAR;
  detailed: BOOLEAN;
  encrypted: BOOLEAN;
  encryptKey: ARRAY 64 OF CHAR;
  cipherType: ARRAY 64 OF CHAR;

PROCEDURE ShowHelp;
BEGIN
  Out.String("Oberon Arc Utility"); Out.Ln;
  Out.String("Commands:"); Out.Ln;
  Out.String("  list <archive> [-d]                              List archive contents"); Out.Ln;
  Out.String("  add <archive> [-c cipher] [-e key] <files>       Add files (optionally encrypted)"); Out.Ln;
  Out.String("  extract <archive> [-c cipher] [-e key] [files]   Extract files"); Out.Ln;
  Out.String("  extractall <archive> [-c cipher] [-e key]        Extract all files"); Out.Ln;
  Out.String("  delete <archive> <files>                         Delete files from archive"); Out.Ln;
  Out.Ln;
  Out.String("Options:"); Out.Ln;
  Out.String("  -d          Show detailed information (list command)"); Out.Ln;
  Out.String("  -c cipher   Select encryption cipher (default: mod)"); Out.Ln;
  Out.String("  -e key      Enable encryption with specified key"); Out.Ln;
  Out.Ln;
  Out.String("Available ciphers:"); Out.Ln;
  Out.String("  mod         Parks-Miller PRNG with modular arithmetic (default)"); Out.Ln;
  Out.String("              - Uses: ciphertext = (plaintext + keystream) MOD 256"); Out.Ln;
  Out.String("  heidelberg  Voyager project cipher of Crypt0.Mod (has a bug with 1-char keys!)"); Out.Ln;
  Out.String("              - Same as 'mod' but with keylen = Length(key)-1"); Out.Ln;
  Out.String("              - WARNING: Crashes with single-character passwords"); Out.Ln;
  Out.String("              - Use only for compatibility with Voyager archives"); Out.Ln;
  Out.String("  xor         XOR stream cipher"); Out.Ln;
  Out.String("              - Uses: ciphertext = plaintext XOR keystream"); Out.Ln;
  Out.String("  s3          Simple key-based cipher from ETH Oberon System 3 CompressCrypt.Mod"); Out.Ln;
  Out.String("              - Uses: ciphertext = plaintext +/- key[i MOD keylen]"); Out.Ln;
  Out.Ln;
  Out.String("Examples:"); Out.Ln;
  Out.String("  oarc add archive.arc -e mypassword file1.txt file2.txt"); Out.Ln;
  Out.String("  oarc extract archive.arc -c heidelberg -e oldkey file1.txt"); Out.Ln;
END ShowHelp;

PROCEDURE ParseOptions(VAR i: INTEGER);
(* Parse options for commands that support encryption *)
BEGIN
  WHILE i < argCount DO
    Args.Get(i, arg);
    IF arg[0] = '-' THEN (* Only process options starting with '-' *)
      IF arg = "-c" THEN
        INC(i);
        IF i < argCount THEN
          Args.Get(i, cipherType);
          INC(i);
        ELSE
          Out.String("Error: -c option requires a cipher name"); Out.Ln;
          HALT(1);
        END;
      ELSIF arg = "-e" THEN
        encrypted := TRUE;
        INC(i);
        IF i < argCount THEN
          Args.Get(i, encryptKey);
          INC(i);
        ELSE
          Out.String("Error: -e option requires a key"); Out.Ln;
          HALT(1);
        END;
      ELSIF arg = "-d" THEN
        detailed := TRUE;
        INC(i);
      ELSE
        Out.String("Unknown option: "); Out.String(arg); Out.Ln;
        HALT(1);
      END;
    ELSE (* Non-option argument found, stop processing options *)
      RETURN
    END;
  END;
END ParseOptions;

PROCEDURE SetupEncryption;
BEGIN
  IF encrypted THEN
    Crypt0.Key();  (* Initialize basic encryption *)
    Crypt0.SetCipher(cipherType); (* Select cipher algorithm *)

    (* Pass the procedures to ArcTool *)
    ArcTool.Encrypt := Crypt0.Encrypt;
    ArcTool.Decrypt := Crypt0.Decrypt;

    (* Set the encryption key *)
    ArcTool.SetEncryption(encryptKey);

    Out.String("Using cipher: "); Out.String(cipherType);
    Out.String(" with key: "); Out.String(encryptKey); Out.Ln;
  END;
END SetupEncryption;

BEGIN
  (* Initialize defaults *)
  cipherType := "mod"; (* Default cipher *)
  encrypted := FALSE;
  detailed := FALSE;
  encryptKey := "";

  argCount := Modules.ArgCount;
  IF argCount < 2 THEN
    ShowHelp;
    RETURN;
  END;

  (* Get the command *)
  Args.Get(1, cmd);
  i := 2;

  IF cmd = "list" THEN
    (* Get archive name *)
    IF i > argCount THEN
      Out.String("Error: missing archive name"); Out.Ln;
      RETURN;
    END;
    Args.Get(i, archive);
    INC(i);

    (* Handle options *)
    ParseOptions(i);  (* Only -d is relevant for list *)
    ArcTool.Directory(archive, detailed);

  ELSIF cmd = "add" THEN
    (* Get archive name *)
    IF i > argCount THEN
      Out.String("Error: missing archive name"); Out.Ln;
      RETURN;
    END;
    Args.Get(i, archive);
    INC(i);

    (* Parse options (-c and -e) *)
    ParseOptions(i);

    (* Get file list *)
    files := NIL;
    WHILE i < argCount DO
      Args.Get(i, arg);
      IF files = NIL THEN
        files := FileUtil.NewFileNode(arg);
        lastFile := files;
      ELSE
        lastFile.next := FileUtil.NewFileNode(arg);
        lastFile := lastFile.next;
      END;
      INC(i);
    END;

    IF files = NIL THEN
      Out.String("Error: no files specified"); Out.Ln;
      RETURN;
    END;

    (* Set up encryption if requested *)
    SetupEncryption();
    ArcTool.Add(archive, files);

    (* Clear encryption *)
    IF encrypted THEN
      ArcTool.ClearEncryption();
    END;

  ELSIF cmd = "extract" THEN
    (* Get archive name *)
    IF i > argCount THEN
      Out.String("Error: missing archive name"); Out.Ln;
      RETURN;
    END;
    Args.Get(i, archive);
    INC(i);

    (* Parse options (-c and -e) *)
    ParseOptions(i);

    (* Get file list *)
    files := NIL;
    WHILE i < argCount DO
      Args.Get(i, arg);
      IF files = NIL THEN
        files := FileUtil.NewFileNode(arg);
        lastFile := files;
      ELSE
        lastFile.next := FileUtil.NewFileNode(arg);
        lastFile := lastFile.next;
      END;
      INC(i);
    END;

    (* Set up decryption if requested *)
    SetupEncryption();

    IF files = NIL THEN
      ArcTool.ExtractAll(archive)
    ELSE
      ArcTool.Extract(archive, files)
    END;

    (* Clear decryption *)
    IF encrypted THEN
      ArcTool.ClearEncryption();
    END;

  ELSIF cmd = "extractall" THEN
    (* Get archive name *)
    IF i > argCount THEN
      Out.String("Error: missing archive name"); Out.Ln;
      RETURN;
    END;
    Args.Get(i, archive);
    INC(i);

    (* Parse options (-c and -e) *)
    ParseOptions(i);

    (* Set up decryption if requested *)
    SetupEncryption();

    ArcTool.ExtractAll(archive);

    (* Clear decryption *)
    IF encrypted THEN
      ArcTool.ClearEncryption();
    END;

  ELSIF cmd = "delete" THEN
    (* Get archive name *)
    IF i > argCount THEN
      Out.String("Error: missing archive name"); Out.Ln;
      RETURN;
    END;
    Args.Get(i, archive);
    INC(i);

    (* Get file list *)
    files := NIL;
    WHILE i < argCount DO
      Args.Get(i, arg);
      IF files = NIL THEN
        files := FileUtil.NewFileNode(arg);
        lastFile := files;
      ELSE
        lastFile.next := FileUtil.NewFileNode(arg);
        lastFile := lastFile.next;
      END;
      INC(i);
    END;

    IF files = NIL THEN
      Out.String("Error: no files specified"); Out.Ln;
      RETURN;
    END;

    ArcTool.Delete(archive, files);

  ELSE
    Out.String("Unknown command: "); Out.String(cmd); Out.Ln;
    ShowHelp;
  END;
END oarc.
