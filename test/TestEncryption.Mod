MODULE TestEncryption;
IMPORT Out, Crypt0, ArcTool;

BEGIN
  Out.String("Testing encryption setup..."); Out.Ln;

  (* Initialize Crypt0 *)
  Crypt0.Key();

  (* Check if handlers are set *)
  IF Crypt0.Encrypt # NIL THEN
    Out.String("Crypt0.Encrypt is set"); Out.Ln;
  ELSE
    Out.String("ERROR: Crypt0.Encrypt is NIL"); Out.Ln;
  END;

  IF Crypt0.Decrypt # NIL THEN
    Out.String("Crypt0.Decrypt is set"); Out.Ln;
  ELSE
    Out.String("ERROR: Crypt0.Decrypt is NIL"); Out.Ln;
  END;

  (* Try to assign *)
  ArcTool.Encrypt := Crypt0.Encrypt;
  ArcTool.Decrypt := Crypt0.Decrypt;

  Out.String("Assignment successful!"); Out.Ln;
END TestEncryption.
