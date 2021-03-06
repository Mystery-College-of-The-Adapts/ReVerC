(** Program interpreters *)
module Interpreter

open FStar.Set
open SetExtra
open Utils
open BoolExp
open ExprTypes
open Total

(* The main compiler module. Defines two interpreters based on either big step
   or small step style reductions. The interpreters use an interpretation of
   the heap to handle allocation and assignment of new Boolean values.
   There are currently three main interpretations: Boolean values (i.e. program
   evaluation), Boolean expressions (classical Boolean circuits), and
   reversible circuits.
   Correctness is proven by proving that two states which are equal under the
   given semantics (eval function) remain equal after an allocation or
   assignment. *)

(* A representation of program heap (which is Bool-typed) *)
noeq type interpretation (state:eqtype) =
  { alloc  : state -> Tot (int * state);
    assign : state -> int -> boolExp -> Tot state;
    eval   : state -> Total.state -> int -> Tot bool }

(* Values of the language *)
val isVal : gexp:gExpr -> Tot bool (decreases %[gexp;1])
val isVal_lst : lst:list gExpr -> Tot bool (decreases %[lst;0])
let rec isVal tm = match tm with
  | UNIT          -> true
  | LAMBDA (s, ty, t) -> true
  | LOC i         -> true
  | ARRAY lst     -> isVal_lst lst
  | _             -> false
and isVal_lst lst = match lst with
  | [] -> true
  | (LOC l)::xs -> isVal_lst xs
  | _ -> false

val isBexp : gExpr -> Tot bool
let isBexp tm = match tm with
  | LOC i     -> true
  | BEXP bexp -> true
  | BOOL b    -> true
  | _         -> false

type config     (state:Type) = gExpr * state
type valconfig  (state:Type) = c:(config state){isVal (fst c)}
type listconfig (state:Type) = (list gExpr) * state

val get_bexp : gexp:gExpr{isBexp gexp} -> Tot boolExp
let get_bexp gexp = match gexp with
  | LOC i     -> BVar i
  | BEXP bexp -> bexp
  | BOOL b    -> if b then BNot BFalse else BFalse

(* Small-step evaluator *)
val step : #state:eqtype -> c:config state -> interpretation state ->
  Tot (result (config state)) (decreases %[(fst c);1])
val step_lst : #state:eqtype -> c:listconfig state -> interpretation state ->
  Tot (result (listconfig state)) (decreases %[(fst c);0])
let rec step #s (tm, st) interp = match tm with
  | LET (x, t1, t2) ->
    if isVal t1
    then Val (substgExpr t2 x t1, st)
    else bindT (step (t1, st) interp) (fun (t1', st') -> Val (LET (x, t1', t2), st'))
  | APPLY (t1, t2) ->
    if not (isVal t1) then
      bindT (step (t1, st) interp) (fun (t1', st') -> Val (APPLY (t1', t2), st'))
    else if not (isVal t2) then
      bindT (step (t2, st) interp) (fun (t2', st') -> Val (APPLY (t1, t2'), st'))
    else
      begin match t1 with
        | LAMBDA (x, ty, t) -> Val (substgExpr t x t2, st)
        | _ -> Err (String.strcat "Cannot reduce application: " (show tm))
      end
  | SEQUENCE (t1, t2) ->
    if not (isVal t1) then
      bindT (step (t1, st) interp) (fun (t1', st') -> Val (SEQUENCE (t1', t2), st'))
    else
      begin match t1 with
        | UNIT -> Val (t2, st)
        | _ -> Err (String.strcat "Cannot reduce sequence: " (show tm))
      end
  | ASSIGN (t1, t2) ->
    if not (isVal t1) then
      bindT (step (t1, st) interp) (fun (t1', st') -> Val (ASSIGN (t1', t2), st'))
    else if not (isBexp t2) then
      bindT (step (t2, st) interp) (fun (t2', st') -> Val (ASSIGN (t1, t2'), st'))
    else
      begin match t1 with
        | LOC l -> Val (UNIT, interp.assign st l (get_bexp t2))
        | _ -> Err (String.strcat "Cannot reduce assignment: " (show tm))
      end
  | XOR (t1, t2) ->
    if not (isBexp t1) then
      bindT (step (t1, st) interp) (fun (t1', st') -> Val (XOR (t1', t2), st'))
    else if not (isBexp t2) then
      bindT (step (t2, st) interp) (fun (t2', st') -> Val (XOR (t1, t2'), st'))
    else
      Val (BEXP (BXor (get_bexp t1, get_bexp t2)), st)
  | AND (t1, t2) ->
    if not (isBexp t1) then
      bindT (step (t1, st) interp) (fun (t1', st') -> Val (AND (t1', t2), st'))
    else if not (isBexp t2) then
      bindT (step (t2, st) interp) (fun (t2', st') -> Val (AND (t1, t2'), st'))
    else
      Val (BEXP (BAnd (get_bexp t1, get_bexp t2)), st)
  | BOOL b ->
    let bexp = if b then BNot BFalse else BFalse in
      Val (BEXP bexp, st)
  | APPEND (t1, t2) ->
    if not (isVal t1) then
      bindT (step (t1, st) interp) (fun (t1', st') -> Val (APPLY (t1', t2), st'))
    else if not (isVal t2) then
      bindT (step (t2, st) interp) (fun (t2', st') -> Val (APPLY (t1, t2'), st'))
    else
      begin match (t1, t2) with
        | (ARRAY l, ARRAY l') -> Val (ARRAY (l@l'), st)
        | _ -> Err (String.strcat "Cannot reduce append: " (show tm))
      end
  | ROT (i, t) ->
    if not (isVal t) then
      bindT (step (t, st) interp) (fun (t', st') -> Val (ROT (i, t'), st'))
    else
      begin match t with
        | ARRAY lst ->
          if (0 <= i && i < FStar.List.Tot.length lst) then
            Val (ARRAY (rotate lst i), st)
          else
            Err (String.strcat "Array out of bounds: " (show tm))
        | _ -> Err (String.strcat "Cannot reduce rotation: " (show tm))
      end
  | SLICE (t, i, j) ->
    if not (isVal t) then
      bindT (step (t, st) interp) (fun (t', st') -> Val (SLICE (t', i, j), st'))
    else
      begin match t with
        | ARRAY lst ->
          if (0 <= i && i <= j && j < FStar.List.Tot.length lst) then
            Val (ARRAY (slice lst i j), st)
          else
            Err (String.strcat "Array out of bounds: " (show tm))
        | _ -> Err (String.strcat "Cannot reduce slice: " (show tm))
      end
  | ARRAY lst -> admit()
    (* NOTE: fix this eventually. In the old version of F* this worked
         bindT (step_lst (lst, st) (fun c -> step c interp)) (fun (lst, st') -> Val (ARRAY lst, st'))
       However, with decidable and propositional equality now in F*, the interpretation type
       doesn't support decidable type equality in general, so F* fails to type check the mutual
       recursive application here. Can't find another solution that works -- local definitions
       don't appear to support totality proofs or for that matter mutual recursion, and I can't get
       F* to infer that the x in ARRAY (x::xs) is a subterm so direct recursion is out. It'll have to
       be left like this until I can get some help from the dev team *)
  | GET_ARRAY (t, i) ->
    if not (isVal t) then
      bindT (step (t, st) interp) (fun (t', st') -> Val (GET_ARRAY (t', i), st'))
    else
      begin match t with
        | ARRAY lst ->
          if (0 <= i && i < FStar.List.Tot.length lst) then
            Val (nthT lst i, st)
          else
            Err (String.strcat "Array out of bounds: " (show tm))
        | _ -> Err (String.strcat "Cannot reduce array index: " (show tm))
      end
  | ASSERT t ->
    if not (isVal t) then
      bindT (step (t, st) interp) (fun (t', st') -> Val (ASSERT t', st'))
    else
      begin match t with
        | LOC l -> Val (UNIT, st)
        | _ -> Err (String.strcat "Cannot reduce assertion: " (show tm))
      end
  | BEXP bexp ->
    let (l, st') = interp.alloc st in 
    let st''     = interp.assign st' l (BXor (BVar l, bexp)) in
      Val (LOC l, st'')
  | _ -> Err (String.strcat "No rule applies: " (show tm))
and step_lst #s (lst, st) interp = match lst with
  | [] -> Val ([], st)
  | x::xs ->
    if not (isVal x) then admit()
      (* See note above
           bindT (step (x, st) interp) (fun (x', st') -> Val (x'::xs, st')) *)
    else
      bindT (step_lst (xs, st) interp) (fun (xs', st') -> Val (x::xs', st'))

(* Big-step evaluator. More efficient but not (proven) total *)
(* NOTE: commented out due to decidable equality issues as above. Not currently used anyway
val eval_rec : #state:eqtype -> config state -> interpretation state -> result (config state)
val eval_to_bexp : #state:eqtype -> config state -> interpretation state -> result (config state)
let rec eval_rec #s (tm, st) interp = match tm with
  | LET (x, t1, t2) ->
    bind (eval_rec (t1, st) interp) (fun (v1, st') ->
      eval_rec (substgExpr t2 x v1, st') interp)
  | LAMBDA (x, ty, t) -> Val (tm, st)
  | APPLY (t1, t2) ->
    bind (eval_rec (t1, st) interp)  (fun (v1, st') ->
    bind (eval_rec (t2, st') interp) (fun (v2, st'') ->
    begin match v1 with
      | LAMBDA (x, ty, t) -> eval_rec (substgExpr t x v2, st'') interp
      | _ -> Err (String.strcat "LHS is not a lambda: " (show tm))
    end))
  | SEQUENCE (t1, t2) ->
    bind (eval_rec (t1, st) interp)  (fun (v1, st') ->
      eval_rec (t2, st') interp)
  | ASSIGN (t1, t2) ->
    bind (eval_rec (t1, st) interp)  (fun (v1, st') ->
    bind (eval_rec (t2, st') interp) (fun (v2, st'') ->
    begin match (v1, v2) with
      | (LOC l, BEXP bexp) -> Val (UNIT, interp.assign st' l bexp)
      | _ -> Err (String.strcat "Invalid parameters: " (show tm))
    end))
  | XOR _ | AND _ | BOOL _ ->
    bind (eval_to_bexp (tm, st) interp) (fun c -> eval_rec c interp)
  | APPEND (t1, t2) ->
    bind (eval_rec (t1, st) interp)  (fun (v1, st') ->
    bind (eval_rec (t2, st') interp) (fun (v2, st'') ->
    begin match (v1, v2) with
      | (ARRAY l1, ARRAY l2) -> Val (ARRAY (l1@l2), st'')
      | _ -> Err (String.strcat "Append of non-array argument: " (show tm))
    end))
  | ROT (i, t) ->
    bind (eval_rec (t, st) interp) (fun (v, st') ->
    begin match v with
      | ARRAY lst ->
        if (0 <= i && i < FStar.List.Tot.length lst)
        then Val (ARRAY (rotate lst i), st')
        else Err (String.strcat "Rotation out of array bounds: " (show tm))
      | _ -> Err (String.strcat "Rotation of non-array argument: " (show tm))
    end)
  | SLICE (t, i, j) ->
    bind (eval_rec (t, st) interp) (fun (v, st') ->
    begin match v with
      | ARRAY lst ->
        if (0 <= i && i <= j && j < FStar.List.Tot.length lst)
        then Val (ARRAY (slice lst i j), st')
        else Err (String.strcat "Invalid slice bounds: " (show tm))
      | _ -> Err (String.strcat "Slice of non-array argument: " (show tm))
    end)
  | ARRAY tlst ->
    let f (acc, st) t =
      bind (eval_rec (t, st) interp) (fun (v, st') ->
      begin match v with
        | LOC l -> Val (v::acc, st')
        | _ -> Err (String.strcat "Array argument not boolean: " (show t))
      end)
    in
    bind (foldM f ([], st) tlst) (fun (llst, st') ->
      Val (ARRAY (FStar.List.Tot.rev llst), st'))
  | GET_ARRAY (t, i) ->
    bind (eval_rec (t, st) interp) (fun (v, st') ->
    begin match v with
      | ARRAY lst ->
        if (0 <= i && i < FStar.List.Tot.length lst) then
          match FStar.List.Tot.nth lst i with
            | Some (LOC l) -> Val (LOC l, st')
            | Some _ -> Err ("Impossible")
            | None -> Err (String.strcat "Array out of bounds: " (show tm))
        else Err (String.strcat "Array out of bounds: " (show tm))
      | _ -> Err (String.strcat "Invalid parameters: " (show tm))
    end)
  | VAR x -> Val (tm, st)
  | ASSERT t ->
    bind (eval_rec (t, st) interp) (fun (v, st') ->
    begin match v with
      | LOC l -> Val (UNIT, st')
      | _ -> Err (String.strcat "Assert of non-boolean argument: " (show tm))
    end)
  | BEXP bexp ->
    let (l, st') = interp.alloc st in 
    let st''     = interp.assign st l (BXor (BVar l, bexp)) in
      Val (LOC l, st')
  | _ -> Err (String.strcat "Unimplemented case: " (show tm))
and eval_to_bexp #s (tm, st) interp = match tm with
  | XOR (x, y) ->
    bind (eval_to_bexp (x, st) interp)  (fun (x', st') ->
    bind (eval_to_bexp (y, st') interp) (fun (y', st'') ->
    match (x', y') with
      | (BEXP b, BEXP b') -> Val (BEXP (BXor (b, b')), st'')
      | _ -> Err (String.strcat "Could not reduce parameters to booleans: " (show tm))))
  | AND (x, y) ->
    bind (eval_to_bexp (x, st) interp)  (fun (x', st') ->
    bind (eval_to_bexp (y, st') interp) (fun (y', st'') ->
    match (x', y') with
      | (BEXP b, BEXP b') -> Val (BEXP (BAnd (b, b')), st'')
      | _ -> Err (String.strcat "Could not reduce parameters to booleans: " (show tm))))
  | BOOL b ->
    if b then Val (BEXP (BNot BFalse), st) else  Val (BEXP BFalse, st)
  | _ ->
    bind (eval_rec (tm, st) interp) (fun (v, st') ->
    match v with
      | LOC l -> Val (BEXP (BVar l), st')
      | _ -> Err (String.strcat "Could not reduce expression to boolean: " (show tm)))
*)

(** Interpretation domains *)

(* Boolean (standard) interpretation -- for running a Revs program *)
type boolState = int * (Total.t int bool)

val boolInit   : boolState
val boolAlloc  : boolState -> Tot (int * boolState)
val boolAssign : boolState -> int -> boolExp -> Tot boolState
val boolEval   : boolState -> state -> int -> Tot bool

let boolInit = (0, constMap false)
let boolAlloc (top, st) = (top, (top + 1, update st top false))
let boolAssign (top, st) l bexp = (top, update st l (evalBexp bexp st))
let boolEval (top, st) ivals i = lookup st i

let boolInterp = {
  alloc = boolAlloc;
  assign = boolAssign;
  eval = boolEval
}

val substVal : v:gExpr{isVal v} -> st:boolState -> Tot gExpr
val substVal_lst : v:(list gExpr){isVal_lst v} -> st:boolState -> Tot (list gExpr)
let rec substVal v st = match v with
  | UNIT | LAMBDA _ -> v
  | LOC l -> BOOL (lookup (snd st) l)
  | ARRAY lst -> ARRAY (substVal_lst lst st)
and substVal_lst lst st = match lst with
  | [] -> []
  | (LOC l)::xs -> (BOOL (lookup (snd st) l))::(substVal_lst xs st)

let rec evalBool (gexp, st) =
  if isVal gexp then prettyPrint (substVal gexp st)
  else match step (gexp, st) boolInterp with
    | Err s -> [s]
    | Val c' -> evalBool c'

let eval gexp = evalBool (gexp, boolInit)

(** Verification utilities *)

type alloc_preservation 
  (#s1:eqtype) 
  (#s2:eqtype) 
  (i1:interpretation s1) 
  (i2:interpretation s2) 
  (p:s1 -> s2 -> Total.t int bool -> Type) =
    forall st1 st2 init. p st1 st2 init ==> p (snd (i1.alloc st1)) (snd (i2.alloc st2)) init

type assign_preservation 
  (#s1:eqtype) 
  (#s2:eqtype) 
  (i1:interpretation s1) 
  (i2:interpretation s2) 
  (p:s1 -> s2 -> Total.t int bool -> Type) =
    forall st1 st2 i bexp init. p st1 st2 init ==> p (i1.assign st1 i bexp) (i2.assign st2 i bexp) init

(* DISCLAIMER: In theory this is trivial, but the lack of an equivalence between universal quantifiers
   and function types in F* makes this difficult. The use of predicates here also seems to be causing
   a strange problem with proving totality that I can't get around. 
   For the time being we'll have separate proofs for each interpretation, but it should be noted that
   each proof follows identically to the generic version, modulo these technical issues with F* *)

(*
val step_preservation : 
  #s1:eqtype -> #s2:eqtype -> i1:interpretation s1 -> i2:interpretation s2 ->
  p:(s1 -> s2 -> Total.t int bool -> Type) ->
  h1:alloc_preservation i1 i2 p ->
  h2:assign_preservation i1 i2 p ->
  gexp:gExpr -> st1:s1 -> st2:s2 -> init:Total.t int bool ->
  Lemma (requires (p st1 st2 init))
        (ensures
          (is_Err (step (gexp, st1) i1) /\ is_Err (step (gexp, st2) i2)) \/
          (is_Val (step (gexp, st1) i1) /\ is_Val (step (gexp, st2) i2) /\ 
	    p (snd (getVal (step (gexp, st1) i1))) (snd (getVal (step (gexp, st2) i2))) init))
  (decreases %[gexp;1])
val step_preservation_lst : 
  #s1:eqtype -> #s2:eqtype -> i1:interpretation s1 -> i2:interpretation s2 ->
  p:(s1 -> s2 -> Total.t int bool -> Type) ->
  h1:alloc_preservation i1 i2 p ->
  h2:assign_preservation i1 i2 p ->
  lst:list gExpr -> st1:s1 -> st2:s2 -> init:Total.t int bool ->
  Lemma (requires (p st1 st2 init))
        (ensures
          (is_Err (step_lst (lst, st1) i1) /\ is_Err (step_lst (lst, st2) i2)) \/
          (is_Val (step_lst (lst, st1) i1) /\ is_Val (step_lst (lst, st2) i2) /\ 
	    p (snd (getVal (step_lst (lst, st1) i1))) (snd (getVal (step_lst (lst, st2) i2))) init))
  (decreases %[lst;0])

(* F* compiler complains this is not total, no idea what's happening
let rec step_preservation #s1 #s2 i1 i2 p h1 h2 gexp st1 st2 init = match gexp with
  | LET (x, t1, t2) -> step_preservation i1 i2 p h1 h2 t1 st1 st2 init
  | LAMBDA (x, ty, t) -> ()
  | APPLY (t1, t2) ->
    step_preservation i1 i2 p h1 h2 t1 st1 st2 init;
    step_preservation i1 i2 p h1 h2 t2 st1 st2 init
  | SEQUENCE (t1, t2) ->
    step_preservation i1 i2 p h1 h2 t1 st1 st2 init;
    step_preservation i1 i2 p h1 h2 t2 st1 st2 init
  | ASSIGN (t1, t2) ->
    step_preservation i1 i2 p h1 h2 t1 st1 st2 init;
    step_preservation i1 i2 p h1 h2 t2 st1 st2 init;
    if (isVal t1 && isBexp t2) then
      begin match t1 with
        | LOC l -> () //h2 something stopped working with the hypothesis
        | _ -> ()
      end 
  | XOR (t1, t2) ->
    step_preservation i1 i2 p h1 h2 t1 st1 st2 init;
    step_preservation i1 i2 p h1 h2 t2 st1 st2 init
  | AND (t1, t2) ->
    step_preservation i1 i2 p h1 h2 t1 st1 st2 init;
    step_preservation i1 i2 p h1 h2 t2 st1 st2 init
  | BOOL b -> ()
  | APPEND (t1, t2) ->
    step_preservation i1 i2 p h1 h2 t1 st1 st2 init;
    step_preservation i1 i2 p h1 h2 t2 st1 st2 init
  | ROT (i, t) ->
    step_preservation i1 i2 p h1 h2 t st1 st2 init
  | SLICE (t, i, j) ->
    step_preservation i1 i2 p h1 h2 t st1 st2 init
  | ARRAY lst -> () // Until the mutual recursion can be solved
  | GET_ARRAY (t, i) ->
    step_preservation i1 i2 p h1 h2 t st1 st2 init
  | ASSERT t ->
    step_preservation i1 i2 p h1 h2 t st1 st2 init
  | BEXP bexp -> () //h1; h2
  | _ -> ()
and step_preservation_lst #s1 #s2 i1 i2 p h1 h2 lst st1 st2 init = match lst with
  | [] -> ()
  | x::xs -> () // Again, mutual recursion issue
    //step_preservation i1 i2 p h1 h2 x st1 st2 init;
    //step_preservation_lst i1 i2 p h1 h2 xs st1 st2 init
*)
