(* Copyright (c) 2021-2022 Logic Magicians Software *)
MODULE Environment;
IMPORT SYSTEM, Kernel;

CONST (* Operations *)
  svcLookup = 0;                (* Lookup and return length. *)
  svcCopy   = 1;                (* Copy value. *)

TYPE (* VMSVC structures. *)
  SVCEnvDesc = RECORD (Kernel.VMServiceDesc)
    op  : LONGINT;
    key : Kernel.ADDRESS;       (* Address of variable name. *)
  END;

  SVCEnvLookupDesc = RECORD (SVCEnvDesc)
    len   : LONGINT; (* Length of env. variable value; 0X excluded. *)
    found : BOOLEAN; (* FALSE => variable not present. *)
  END;

  SVCEnvCopyDesc = RECORD (SVCEnvDesc)
    addr : Kernel.ADDRESS;
    n    : LONGINT;
  END;

TYPE
  (* The Text type is used to refer the value of an environment
   * variable.  It is an arbitrary length ASCIIZ value.
   *)
  Text* = POINTER TO ARRAY OF CHAR;

  (* Elements is a type that is used to reference the elements of
   * a Text that have been split on a separator character.
   * For example:
   *
   *  SKL_SEARCH_PATH="/tmp:/var:/homes"
   *
   *)
  Elements* = POINTER TO ARRAY OF Text;

  KV = POINTER TO KVDesc;       (* Key / Value *)
  KVDesc = RECORD
    next  : KV;
    prev  : KV;
    key   : Text;
    value : Text;
  END;

VAR
  env : KV;


PROCEDURE SVCLookup(VAR key : ARRAY OF CHAR;
                    VAR len : LONGINT) : BOOLEAN;
  VAR
    svc : SVCEnvLookupDesc;
BEGIN
  svc.op  := svcLookup;
  svc.key := SYSTEM.ADR(key);
  Kernel.VMService(Kernel.VMSVCEnvironment, svc);
  IF svc.found THEN
    len := svc.len;
  END;
  RETURN svc.found;
END SVCLookup;


PROCEDURE SVCCopy(VAR key : ARRAY OF CHAR; val : Text);
  VAR
    svc : SVCEnvCopyDesc;
BEGIN
  svc.op   := svcCopy;
  svc.key  := SYSTEM.ADR(key);
  svc.addr := SYSTEM.ADR(val^);
  svc.n    := LEN(val^) - 1; (* Copy at most n - 1 chars; then 0X terminate. *)
  Kernel.VMService(Kernel.VMSVCEnvironment, svc);
END SVCCopy;


PROCEDURE remove(kv : KV);
BEGIN
  kv.next.prev := kv.prev;
  kv.prev.next := kv.next;
  kv.next      := NIL;
  kv.prev      := NIL;
END remove;


PROCEDURE add(kv : KV);
BEGIN
  env.next.prev := kv;
  kv.next       := env.next;
  env.next      := kv;
  kv.prev       := env;
END add;


(* Finds 'key' if it's in the local cache and moves it
 * to the head of the list.
 *
 * Returns NIL if it's not in the cache.
 *)
PROCEDURE find(VAR (* R/O *) key : ARRAY OF CHAR) : KV;
  VAR
    kv   : KV;
    done : BOOLEAN;
BEGIN
  kv := env.next;
  WHILE kv # env DO
    IF kv.key^ = key THEN
      (* Put 'kv' at the head of the list because it will probably be
       * looked up again and it will be found faster.
       *)
      remove(kv);
      add(kv);
      RETURN kv;
    END;
    kv := kv.next;
  END;
  RETURN NIL;
END find;


(* Delete an environment entry.
 *
 * The entry value is set to NIL, but the cache entry is not deleted.
 * If it was deleted, the next lookup may find it in the host OS'
 * environment again.  Removing only the value ensures it's never found
 * again, until it's recreated.
 *)
PROCEDURE Delete*(key : ARRAY OF CHAR);
  VAR
    kv : KV;
BEGIN
  kv := find(key);
  IF kv # NIL THEN
    kv.value := NIL;
  END;
END Delete;


PROCEDURE Set*(key : ARRAY OF CHAR; value : ARRAY OF CHAR);
  VAR
    kv : KV;
    v  : Text;
BEGIN
  kv := find(key);
  IF kv = NIL THEN
    (* Not found;  create it and set value. *)
    NEW(kv);
    NEW(kv.key, LEN(key));
    NEW(kv.value, LEN(value));
    COPY(key, kv.key^);
    COPY(value, kv.value^);
  ELSE
    (* Variable in cache.  Replace value. *)
    NEW(v, LEN(value));
    COPY(value, v^);
    kv.value := v;
  END;
END Set;

PROCEDURE Lookup*(key : ARRAY OF CHAR) : Text;
  VAR
    len : LONGINT;
    v : Text;
    kv : KV;
BEGIN
  kv := find(key);
  IF kv = NIL THEN
    (* Not in local cache; check host OS. *)
    IF SVCLookup(key, len) THEN
      (* Host OS has a value. *)
      NEW(kv);
      NEW(kv.value, len + 1);
      NEW(kv.key, LEN(key));
      COPY(key, kv.key^);
      SVCCopy(key, kv.value);
      add(kv);
      RETURN kv.value;
    ELSE
      (* Host OS does not have a value.  Signal no value at all. *)
      RETURN NIL;
    END;
  ELSE
    RETURN kv.value;
  END;
END Lookup;


PROCEDURE Split*(v : Text; separator : CHAR) : Elements;
  VAR
    elem : Elements;
    vv   : Text;
    ch   : CHAR;
    beg  : INTEGER;
    end  : INTEGER;
    cnt  : INTEGER;

  PROCEDURE CreateText(v : Text; beg, end (* [beg, end) *) : INTEGER) : Text;
    VAR
      res : Text;
      i   : INTEGER;
  BEGIN
    NEW(res, end - beg + 1);
    i := 0;
    WHILE beg < end DO
      res[i] := v[beg];
      INC(beg);
      INC(i);
    END;
    res[i] := 0X;
    RETURN res;
  END CreateText;

BEGIN
  IF v # NIL THEN
    (* Count separators and allocate main array. *)
    beg := 0;
    end := 0;
    cnt := 0;
    LOOP
      ch := v[end];
      IF ch = separator THEN
        IF end > beg (* [beg, end) *) THEN
          INC(cnt);
        END;
        beg := end + 1;
      END;
      IF ch = 0X THEN
        IF end > beg THEN
          INC(cnt);
        END;
        EXIT;
      END;
      INC(end);
    END;

    IF cnt > 0 THEN
      NEW(elem, cnt);
      
      end := 0;
      beg := 0;
      cnt := 0;
      LOOP
        ch := v[end];
        IF (ch = 0X) OR (ch = separator) THEN
          IF end - beg > 0 THEN
            (* Do not store 0-length elements. *)
            elem[cnt] := CreateText(v, beg, end);
            INC(cnt)
          END;
          beg := end + 1;
        END;
        INC(end);
        IF ch = 0X THEN
          EXIT;
        END;
      END;
      RETURN elem;
    ELSE
      RETURN NIL;                 (* No data found. *)
    END;
  ELSE
    RETURN NIL;
  END;
END Split;

BEGIN
  NEW(env);                     (* Dummy header. *)
  env.next  := env;
  env.prev  := env;
  env.key   := NIL;
  env.value := NIL;
END Environment.
