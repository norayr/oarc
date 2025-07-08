MODULE FileUtil;
IMPORT Files, UnixFS, Out, Strings, SYSTEM;

TYPE
  FileList* = POINTER TO FileListNode;
  FileListNode* = RECORD
    name*: ARRAY 256 OF CHAR;
    next*: FileList;
  END;

PROCEDURE NewFileNode*(name: ARRAY OF CHAR): FileList;
VAR node: FileList;
BEGIN
  NEW(node);
  COPY(name, node.name);
  node.next := NIL;
  RETURN node;
END NewFileNode;

PROCEDURE FileExists*(name: ARRAY OF CHAR): BOOLEAN;
BEGIN
  RETURN UnixFS.ExistsByName(name);
END FileExists;

PROCEDURE CreateDirectory*(path: ARRAY OF CHAR): BOOLEAN;
BEGIN
  RETURN UnixFS.mkDir(path);
END CreateDirectory;

PROCEDURE DeleteFile*(name: ARRAY OF CHAR): BOOLEAN;
VAR res: INTEGER;
BEGIN
  Files.Delete(name, res);
  RETURN res = 0;
END DeleteFile;

PROCEDURE RenameFile*(oldName, newName: ARRAY OF CHAR): BOOLEAN;
VAR res: INTEGER;
BEGIN
  Files.Rename(oldName, newName, res);
  RETURN res = 0;
END RenameFile;

PROCEDURE GetFileSize*(name: ARRAY OF CHAR): LONGINT;
VAR f: Files.File; r: Files.Rider; size: LONGINT;
BEGIN
  f := Files.Old(name);
  IF f # NIL THEN
    Files.Set(r, f, 0);
    size := Files.Length(f);
    Files.Close(f);
    RETURN size;
  END;
  RETURN -1;
END GetFileSize;

PROCEDURE GetFileList*(files: FileList): FileList;
BEGIN
  RETURN files;
END GetFileList;

END FileUtil.
