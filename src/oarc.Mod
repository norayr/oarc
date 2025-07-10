MODULE oarc;
IMPORT Args, Out, ArcTool, FileUtil, Modules;

VAR
  cmd: ARRAY 32 OF CHAR;
  archive: ARRAY 256 OF CHAR;
  i, argCount: INTEGER;
  files: FileUtil.FileList;
  lastFile: FileUtil.FileList;
  arg: ARRAY 256 OF CHAR;
  detailed: BOOLEAN;

PROCEDURE ShowHelp;
BEGIN
  Out.String("Oberon Arc Utility for Linux");
  Out.Ln;
  Out.String("Commands:"); Out.Ln;
  Out.String("  list <archive> [-d]       List archive contents"); Out.Ln;
  Out.String("  add <archive> <files>     Add files to archive");  Out.Ln;
  Out.String("  extract <archive> [files] Extract files from archive");  Out.Ln;
  Out.String("  extractall <archive>      Extract all files");     Out.Ln;
  Out.String("  delete <archive> <files>  Delete files from archive");    Out.Ln;
  Out.Ln;
END ShowHelp;

BEGIN
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
    detailed := FALSE;
    IF i < argCount THEN  (* Changed from <= to < *)
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

    (* Get file list *)
    files := NIL;
    WHILE i < argCount DO  (* Changed from <= to < *)
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

    ArcTool.Add(archive, files);

  ELSIF cmd = "extract" THEN
    (* Get archive name *)
    IF i > argCount THEN
      Out.String("Error: missing archive name"); Out.Ln;
      RETURN;
    END;
    Args.Get(i, archive);
    INC(i);

    (* Get file list *)
    files := NIL;
    WHILE i < argCount DO  (* Changed from <= to < *)
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
      ArcTool.ExtractAll(archive)
    ELSE
      ArcTool.Extract(archive, files)
    END;

  ELSIF cmd = "extractall" THEN
    (* Get archive name *)
    IF i > argCount THEN
      Out.String("Error: missing archive name"); Out.Ln;
      RETURN;
    END;
    Args.Get(i, archive);
    ArcTool.ExtractAll(archive);

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
    WHILE i < argCount DO  (* Changed from <= to < *)
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