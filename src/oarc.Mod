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

PROCEDURE ShowHelp;
BEGIN
  Out.String("Oberon Arc Utility"); Out.Ln;
  Out.String("Commands:"); Out.Ln;
  Out.String("  list <archive> [-d]              List archive contents"); Out.Ln;
  Out.String("  add <archive> [-e key] <files>   Add files (optionally encrypted)"); Out.Ln;
  Out.String("  extract <archive> [-e key] [files] Extract files"); Out.Ln;
  Out.String("  extractall <archive> [-e key]    Extract all files"); Out.Ln;
  Out.String("  delete <archive> <files>         Delete files from archive"); Out.Ln;
  Out.Ln;
  Out.String("Options:"); Out.Ln;
  Out.String("  -d        Show detailed information (list command)"); Out.Ln;
  Out.String("  -e key    Use encryption with specified key"); Out.Ln;
  Out.Ln;
END ShowHelp;

PROCEDURE ParseEncryptionOption(VAR i: INTEGER): BOOLEAN;
(* Returns TRUE if encryption option found and parsed *)
BEGIN
  IF (i < argCount) THEN
    Args.Get(i, arg);
    IF arg = "-e" THEN
      INC(i);
      IF i < argCount THEN
        Args.Get(i, encryptKey);
        INC(i);
        RETURN TRUE;
      ELSE
        Out.String("Error: -e option requires a key"); Out.Ln;
        HALT(1);
      END;
    END;
  END;
  RETURN FALSE;
END ParseEncryptionOption;

BEGIN
  argCount := Modules.ArgCount;
  IF argCount < 2 THEN
    ShowHelp;
    RETURN;
  END;

  (* Initialize *)
  encrypted := FALSE;
  encryptKey := "";

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
    detailed := FALSE;
    IF i < argCount THEN
      Args.Get(i, arg);
      IF arg = "-d" THEN
        detailed := TRUE;
        INC(i);
      END;
    END;

    ArcTool.Directory(archive, detailed);

  ELSIF cmd = "add" THEN
    (* Get archive name *)
    IF i > argCount THEN
      Out.String("Error: missing archive name"); Out.Ln;
      RETURN;
    END;
    Args.Get(i, archive);
    INC(i);

    (* Check for encryption option *)
    encrypted := ParseEncryptionOption(i);

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
    IF encrypted THEN
      Crypt0.Key();  (* Install encryption handlers - this sets Crypt0.Encrypt and Crypt0.Decrypt *)
      (* Now they should be initialized, so we can copy them *)
      ArcTool.Encrypt := Crypt0.Encrypt;
      ArcTool.Decrypt := Crypt0.Decrypt;
      ArcTool.SetEncryption(encryptKey);
    END;

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

    (* Check for encryption option *)
    encrypted := ParseEncryptionOption(i);

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
    IF encrypted THEN
      Crypt0.Key();  (* Initialize Crypt0 module *)
      (* Now pass the procedures to ArcTool *)
      ArcTool.Encrypt := Crypt0.Encrypt;
      ArcTool.Decrypt := Crypt0.Decrypt;
      ArcTool.SetDecryption(encryptKey);
    END;

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

    (* Check for encryption option *)
    encrypted := ParseEncryptionOption(i);

    (* Set up decryption if requested *)
    IF encrypted THEN
      Crypt0.Key();  (* Initialize Crypt0 module *)
      (* Now pass the procedures to ArcTool *)
      ArcTool.Encrypt := Crypt0.Encrypt;
      ArcTool.Decrypt := Crypt0.Decrypt;
      ArcTool.SetDecryption(encryptKey);
    END;

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
