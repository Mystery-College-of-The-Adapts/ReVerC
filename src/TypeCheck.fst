(** Type checker *)
module TypeCheck

open Partial
open Utils
open BoolExp
open ExprTypes

(* Type checking is really a misnomer -- we don't type check
   in the sense of preventing run-time errors. Type checking
   in ReVer is really a static analysis to infer array bounds
   and allow the compiler to allocate space for every
   register statically. Type inference serves as a useful
   way to frame the problem, with the added benefit that the
   framework may be used later to better effect when features
   are added *)

type ctxt = Partial.t string gType

type wellTypedCtxt : ctxt -> string -> gType -> Type =
  | Ctxt_zero : s:string -> ty:gType -> xs:ctxt -> wellTypedCtxt ((s, ty)::xs) s ty
  | Ctxt_succ : s:string -> ty:gType -> x:(string * gType){~(fst x = s)} -> xs:ctxt ->
                wellTypedCtxt xs s ty ->
                wellTypedCtxt (x::xs) s ty

type subType : gType -> gType -> Type =
  | Sub_refl : #t1:gType -> subType t1 t1
  | Sub_arry : n:nat -> m:fin n -> subType (GArray n) (GArray m)
  | Sub_lam  : #t1:gType -> #t2:gType -> #s1:gType -> #s2:gType ->
               subType s1 t1 ->
               subType t2 s2 ->
               subType (GFun (t1, t2)) (GFun (s1, s2))

type wellTyped : ctxt -> gExpr -> gType -> Type =
  | Wt_let : #ctx:ctxt -> #s:string -> #t1:gExpr -> #t2:gExpr -> #ty1:gType -> #ty2:gType ->
             wellTyped ctx t1 ty1 ->
             wellTyped ((s, ty1)::ctx) t2 ty2 ->
             wellTyped ctx (LET (s, t1, t2)) ty2
  | Wt_lam : #ctx:ctxt -> #s:string -> #ty1:gType -> #t:gExpr -> #ty2:gType ->
             wellTyped ((s, ty1)::ctx) t ty2 ->
             wellTyped ctx (LAMBDA (s, ty1, t)) (GFun (ty1, ty2))
  | Wt_apl : #ctx:ctxt -> #t1:gExpr -> #t2:gExpr -> #ty1:gType -> #ty2:gType -> #ty3:gType ->
             wellTyped ctx t1 (GFun (ty1, ty2)) ->
             wellTyped ctx t2 ty3 ->
             subType ty3 ty1 ->
             wellTyped ctx (APPLY (t1, t2)) ty2
  | Wt_ite : #ctx:ctxt -> #t1:gExpr -> #t2:gExpr -> #t3:gExpr -> #ty1:gType -> #ty2:gType -> #ty3:gType ->
             wellTyped ctx t1 GBool ->
             wellTyped ctx t2 ty1 ->
             wellTyped ctx t3 ty2 ->
             subType ty1 ty3 ->
             subType ty2 ty3 ->
             wellTyped ctx (IFTHENELSE (t1, t2, t3)) ty3
  | Wt_seq : #ctx:ctxt -> #t1:gExpr -> #t2:gExpr -> #ty:gType ->
             wellTyped ctx t1 GUnit ->
             wellTyped ctx t2 ty ->
             wellTyped ctx (SEQUENCE (t1, t2)) ty
  | Wt_ass : #ctx:ctxt -> #t1:gExpr -> #t2:gExpr ->
             wellTyped ctx t1 GBool ->
             wellTyped ctx t2 GBool ->
             wellTyped ctx (ASSIGN (t1, t2)) GUnit
  | Wt_unt : #ctx:ctxt -> wellTyped ctx UNIT GUnit
  | Wt_xor : #ctx:ctxt -> #t1:gExpr -> #t2:gExpr ->
             wellTyped ctx t1 GBool ->
             wellTyped ctx t2 GBool ->
             wellTyped ctx (XOR (t1, t2)) GBool
  | Wt_and : #ctx:ctxt -> #t1:gExpr -> #t2:gExpr ->
             wellTyped ctx t1 GBool ->
             wellTyped ctx t2 GBool ->
             wellTyped ctx (AND (t1, t2)) GBool
  | Wt_bl  : #ctx:ctxt -> b:bool -> wellTyped ctx (BOOL b) GBool
  | Wt_apn : #ctx:ctxt -> #t1:gExpr -> #t2:gExpr -> #n:nat -> #m:nat ->
             wellTyped ctx t1 (GArray n) ->
             wellTyped ctx t2 (GArray m) ->
             wellTyped ctx (APPEND (t1, t2)) (GArray (n + m))
  | Wt_rot : #ctx:ctxt -> #t:gExpr -> #n:nat -> i:fin n ->
             wellTyped ctx t (GArray n) ->
             wellTyped ctx (ROT (i, t)) (GArray n)
  | Wt_slc : #ctx:ctxt -> #t:gExpr -> #n:nat -> i:nat -> j:nat{i <= j && j < n} ->
             wellTyped ctx t (GArray n) ->
             wellTyped ctx (SLICE (t, i, j)) (GArray (j - i))
  | Wt_arz : #ctx:ctxt -> wellTyped ctx (ARRAY []) (GArray 0)
  | Wt_ars : #ctx:ctxt -> #t:gExpr -> #ts:list gExpr -> #n:nat ->
             wellTyped ctx t GBool ->
             wellTyped ctx (ARRAY ts) (GArray n) ->
             wellTyped ctx (ARRAY (t::ts)) (GArray (n+1))
  | Wt_gta : #ctx:ctxt -> #t:gExpr -> #n:nat -> i:fin n ->
             wellTyped ctx t (GArray n) ->
             wellTyped ctx (GET_ARRAY (t, i)) GBool
  | Wt_get : #ctx:ctxt -> #s:string -> #ty:gType ->
             wellTypedCtxt ctx s ty ->
             wellTyped ctx (VAR s) ty
  | Wt_ast : #ctx:ctxt -> #t:gExpr ->
             wellTyped ctx t GBool ->
             wellTyped ctx (ASSERT t) GUnit
  | Wt_loc : #ctx:ctxt -> i:int ->
             wellTyped ctx (LOC i) GBool
  | Wt_bex : #ctx:ctxt -> bexp:boolExp ->
             wellTyped ctx (BEXP bexp) GBool

val subtype : t1:gType -> t2:gType -> Tot bool
val suptype : t1:gType -> t2:gType -> Tot bool
let rec subtype t1 t2 = if t1 = t2 then true else match (t1, t2) with
  | (GArray i, GArray j) -> j <= i
  | (GConst t1, GConst t2) -> subtype t1 t2
  | (GFun (t1, t2), GFun (s1, s2)) -> (suptype t1 s1) && (subtype t2 s2)
  | _ -> false
and suptype t1 t2 = if t1 = t2 then true else match (t1, t2) with
  | (GArray i, GArray j) -> j >= i
  | (GConst t1, GConst t2) -> suptype t1 t2
  | (GFun (t1, t2), GFun (s1, s2)) -> (subtype t1 s1) && (suptype t2 s2)
  | _ -> false

val welltyctx_imp_findctx : ctx:ctxt -> s:string -> ty:gType -> wellTypedCtxt ctx s ty ->
  Lemma (find ctx s = Some ty)
let rec welltyctx_imp_findctx ctx s ty h = match h with
  | Ctxt_zero s ty xs -> ()
  | Ctxt_succ s ty x xs h' -> welltyctx_imp_findctx xs s ty h'

val findctx_imp_welltyctx : ctx:ctxt -> s:string -> ty:gType -> h:unit{find ctx s = Some ty} ->
  wellTypedCtxt ctx s ty
let rec findctx_imp_welltyctx ctx s ty h = match ctx with
  | (x,y)::xs -> if x = s && y = ty
    then Ctxt_zero s ty xs
    else Ctxt_succ s ty (x,y) xs (findctx_imp_welltyctx xs s ty ())

(* Type inference *)
type iExp =
  | ILit   of int
  | IVar   of int
  | IPlus  of iExp * iExp
  | IMinus of iExp

type tExp =
  | TUnit
  | TBool
  | TVar   of int
  | TArray of iExp
  | TArrow of tExp * tExp

val normalize : iExp -> iExp
let rec normalize iexp = match iexp with
  | IMinus x ->
    begin match normalize x with
      | IMinus x'    -> x'
      | ILit i       -> ILit (-i)
      | IPlus (x, y) -> IPlus (normalize (IMinus x), normalize (IMinus y))
      | x'           -> IMinus x'
    end
  | IPlus (x, y) ->
    begin match (normalize x, normalize y) with
      | (IVar i, y') | (y', IVar i)       -> IPlus (IVar i, y')
      | (ILit i, ILit j)                  -> ILit (i+j)
      | (IPlus (IVar i, x'), y')
      | (y', IPlus (IVar i, x'))          -> IPlus (IVar i, IPlus (x', y'))
      | (IPlus (IMinus (IVar i), x'), y')
      | (y', IPlus (IMinus (IVar i), x')) -> IPlus (IMinus (IVar i), IPlus (x', y'))
      | (x', y')                          -> IPlus (x', y')
    end
  | _ -> iexp

val totExp : gType -> Tot tExp
let rec totExp ty = match ty with
  | GUnit -> TUnit
  | GBool -> TBool
  | GVar i -> TVar i
  | GArray n -> TArray (ILit n)
  | GConst ty -> totExp ty
  | GFun (ty1, ty2) -> TArrow (totExp ty1, totExp ty2)

val togType : tExp -> gType
let rec togType texp = match texp with
  | TUnit -> GUnit
  | TBool -> GBool
  | TVar i -> GVar i
  | TArray iexp ->
    begin match normalize iexp with
      | ILit n -> GArray n
      | _ -> GArray 0
    end
  | TArrow (texp1, texp2) -> GFun (togType texp1, togType texp2)

(* Constraints (equality or less than) over type expressions *)
type constraint =
  | ICons of iExp * iExp
  | TCons of tExp * tExp

type ctxt' = Partial.t string tExp

val inferTypes : int -> ctxt' -> tm:gExpr -> Tot (int * list constraint * list constraint * tExp) (decreases %[tm;0])
val inferTypes_lst : int -> ctxt' -> l:list gExpr -> Tot (int * list constraint * list constraint) (decreases %[l;1])
let rec inferTypes top ctx gexp = match gexp with
  | LET (x, t1, t2) ->
    let (top', ec1, lc1, ty1) = inferTypes top ctx t1 in
    let (top'', ec2, lc2, ty2) = inferTypes top' ((x, ty1)::ctx) t2 in
        (top'', ec1@ec2, lc1@lc2, ty2)
  | LAMBDA (x, ty, t) ->
    let (top', ec1, lc1, ty1) = inferTypes top ((x, (totExp ty))::ctx) t in
        (top', ec1, lc1, TArrow (totExp ty, ty1))
  | APPLY (t1, t2) ->
    let (top', ec1, lc1, ty1) = inferTypes top ctx t1 in
    let (top'', ec2, lc2, ty2) = inferTypes top' ctx t2 in
    let e = TCons (ty1, TArrow (TVar top'', TVar (top''+1))) in
    let c = TCons (ty2, TVar top'') in
      (top''+2, e::(ec1@ec2), c::(lc1@lc2), TVar (top''+1))
  | IFTHENELSE (t1, t2, t3) ->
    let (top', ec1, lc1, ty1) = inferTypes top ctx t1 in
    let (top'', ec2, lc2, ty2) = inferTypes top' ctx t2 in
    let (top''', ec3, lc3, ty3) = inferTypes top'' ctx t3 in
    let e1 = TCons (ty1, TBool) in
    let e2 = TCons (ty2, TVar top''') in
    let e3 = TCons (ty3, TVar top''') in
      (top'''+1, e1::e2::e3::(ec1@ec2@ec3), lc1@lc2, TVar top''')
  | SEQUENCE (t1, t2) ->
    let (top', ec1, lc1, ty1) = inferTypes top ctx t1 in
    let (top'', ec2, lc2, ty2) = inferTypes top' ctx t2 in
    let e1 = TCons (ty1, TUnit) in
      (top'', e1::(ec1@ec2), lc1@lc2, ty2)
  | ASSIGN (t1, t2) ->
    let (top', ec1, lc1, ty1) = inferTypes top ctx t1 in
    let (top'', ec2, lc2, ty2) = inferTypes top' ctx t2 in
    let e1 = TCons (ty1, TBool) in
    let e2 = TCons (ty2, TBool) in
      (top'', e1::e2::(ec1@ec2), lc1@lc2, TUnit)
  | VAR x -> begin match find ctx x with
    | None -> (top, [], [], TUnit)
    | Some ty -> (top, [], [], ty)
  end
  | UNIT -> (top, [], [], TUnit)
  | BOOL b -> (top, [], [], TBool)
  | XOR (t1, t2) | AND (t1, t2) ->
    let (top', ec1, lc1, ty1) = inferTypes top ctx t1 in
    let (top'', ec2, lc2, ty2) = inferTypes top' ctx t2 in
    let e1 = TCons (ty1, TBool) in
    let e2 = TCons (ty2, TBool) in
      (top'', e1::e2::(ec1@ec2), lc1@lc2, TBool)
  | ARRAY tlst ->
    let (top', ec, lc) = inferTypes_lst top ctx tlst in
      (top', ec, lc, TArray (ILit (FStar.List.Tot.length tlst)))
  | GET_ARRAY (t, i) ->
    let (top', ec1, lc1, ty1) = inferTypes top ctx t in
    let e1 = TCons (ty1, TArray (IVar top')) in
    let l1 = ICons (ILit (i+1), IVar top') in
      (top'+1, e1::ec1, l1::lc1, TBool)
  | APPEND (t1, t2) ->
    let (top', ec1, lc1, ty1) = inferTypes top ctx t1 in
    let (top'', ec2, lc2, ty2) = inferTypes top' ctx t2 in
    let e1 = TCons (ty1, TArray (IVar top'')) in
    let e2 = TCons (ty2, TArray (IVar (top''+1))) in
    let e3 = ICons (IVar (top''+2), IPlus (IVar top'', IVar (top''+1))) in
      (top''+3, e1::e2::e3::(ec1@ec2), lc1@lc2, TArray (IVar (top''+2)))
  | ROT (i, t) ->
    let (top', ec1, lc1, ty1) = inferTypes top ctx t in
    let e1 = TCons (ty1, TArray (IVar top')) in
    let l1 = ICons (ILit (i+1), IVar top') in
      (top'+1, e1::ec1, l1::lc1, TArray (IVar top'))
  | SLICE (t, i, j) ->
    let (top', ec1, lc1, ty1) = inferTypes top ctx t in
    let e1 = TCons (ty1, TArray (IVar top')) in
    let l1 = ICons (ILit (j+1), IVar top') in
      (top'+1, e1::ec1, l1::lc1, TArray (ILit (j - i + 1)))
  | ASSERT t ->
    let (top', ec1, lc1, ty1) = inferTypes top ctx t in
    let e1 = TCons (ty1, TBool) in
      (top', e1::ec1, lc1, TUnit)
  | LOC i -> (top, [], [], TBool)
  | BEXP bexp -> (top, [], [], TBool)
  | _ -> (top, [], [], TUnit)
and inferTypes_lst top ctx lst = match lst with
  | [] -> (top, [], [])
  | x::xs ->
    let (top', ec1, lc1, ty1) = inferTypes top ctx x in
    let (top'', ec2, lc2) = inferTypes_lst top' ctx xs in
    let e1 = TCons (ty1, TBool) in
      (top'', e1::(ec1@ec2), lc1@lc2)


let rec substiExp i iexp x = match x with
  | ILit j -> ILit j
  | IVar j -> if i = j then iexp else IVar j
  | IMinus x -> substiExp i iexp x
  | IPlus (x, y) -> IPlus (substiExp i iexp x, substiExp i iexp y)

let rec substtExp i texp x = match x with
  | TUnit -> TUnit
  | TBool -> TBool
  | TVar j -> if i = j then texp else TVar j
  | TArray iexp -> TArray iexp
  | TArrow (x, y) -> TArrow (substtExp i texp x, substtExp i texp y)

let rec substiExpIntExp i iexp x = match x with
  | TArray iexp' -> TArray (substiExp i iexp iexp')
  | TArrow (x, y) -> TArrow (substiExpIntExp i iexp x, substiExpIntExp i iexp y)
  | _ -> x

let rec iSubst i iexp cons = match cons with
  | [] -> []
  | (ICons (c1, c2))::xs -> (ICons (substiExp i iexp c1, substiExp i iexp c2))::(iSubst i iexp xs)
  | (TCons (c1, c2))::xs -> (TCons (substiExpIntExp i iexp c1, substiExpIntExp i iexp c2))::(iSubst i iexp xs)

let rec tSubst i texp cons = match cons with
  | [] -> []
  | (TCons (c1, c2))::xs -> (TCons (substtExp i texp c1, substtExp i texp c2))::(tSubst i texp xs)
  | x::xs -> x::(tSubst i texp xs)

let rec mergeLower iexp j bnds = match bnds with
  | [] -> Some iexp
  | (ICons (iexp', IVar h))::xs -> 
    if h = j then 
      begin match (normalize iexp, normalize iexp') with
        | (ILit x, ILit y) -> mergeLower (ILit (max x y)) j xs
        | (IVar x, IVar y) -> if x = y then mergeLower (IVar x) j xs else None
        | _ -> None
      end
    else 
      mergeLower iexp j xs
  | _::xs -> mergeLower iexp j xs

let rec unify_bnds top bnds subs = 
  match bnds with
  | [] -> Some subs
  | (ICons (i1, i2))::xs ->
    begin match (normalize i1, normalize i2) with
      | (iexp, IVar j) ->
        begin match (mergeLower iexp j xs) with
          | Some sub -> unify_bnds top (iSubst j sub xs) (iSubst j sub subs)
          | None -> unify_bnds top (xs @ [ICons (iexp, IVar j)]) subs
        end
      | (ILit x, ILit y) -> if x <= y then unify_bnds top xs subs else None
      | (iexp, iexp') -> unify_bnds top (xs @ [ICons (iexp, iexp')]) subs
    end
  | (TCons (t1, t2))::xs ->
    begin match (t1, t2) with
      | (TVar i, TUnit) | (TUnit, TVar i) -> unify_bnds top (tSubst i TUnit xs) (tSubst i TUnit subs)
      | (TVar i, TBool) | (TBool, TVar i) -> unify_bnds top (tSubst i TBool xs) (tSubst i TBool subs)
      | (TVar i, TArray iexp) -> 
          let sub = TArray (IVar top) in
            unify_bnds (top+1) 
                       (tSubst i sub ((ICons (iexp, IVar top))::xs)) 
                       ((TCons (TVar i, sub))::(tSubst i sub subs))
      | (TArray iexp, TVar i) -> 
          let sub = TArray (IVar top) in
            unify_bnds (top+1) 
                       (tSubst i sub ((ICons (IVar top, iexp))::xs)) 
                       ((TCons (TVar i, sub))::(tSubst i sub subs))
      | (TVar i, TArrow (t1, t2)) -> 
          let sub = TArrow (TVar top, TVar (top+1)) in
            unify_bnds (top+2) 
                       (tSubst i sub ((TCons (t1, TVar top))::(TCons (TVar (top+1), t2))::xs)) 
                       ((TCons (TVar i, sub))::(tSubst i sub subs))
      | (TArrow (t1, t2), TVar i) -> 
          let sub = TArrow (TVar top, TVar (top+1)) in
            unify_bnds (top+2) 
                       (tSubst i sub ((TCons (TVar top, t1))::(TCons (t2, TVar (top+1)))::xs)) 
                       ((TCons (TVar i, sub))::(tSubst i sub subs))
      | (TVar i, TVar j) -> unify_bnds top (xs @ [TCons (t1, t2)]) subs
      | (TUnit, TUnit) -> unify_bnds top xs subs
      | (TBool, TBool) -> unify_bnds top xs subs
      | (TArray iexp, TArray iexp') -> unify_bnds top ((ICons (iexp', iexp))::xs) subs
      | (TArrow (t1, t2), TArrow (s1, s2)) -> unify_bnds top ((TCons (s1, t1))::(TCons (t2, s2))::xs) subs
      | _ -> None
    end

let rec unify_eq top eqs bnds subs = match eqs with
  | [] -> unify_bnds top bnds subs
  | (ICons (i1, i2))::xs ->
    begin match (normalize i1, normalize i2) with
      | (IVar i, iexp)
      | (iexp, IVar i) -> unify_eq top (iSubst i iexp xs) (iSubst i iexp bnds) (iSubst i iexp subs)
      | (ILit i, ILit j) -> if i = j then unify_eq top xs bnds subs else None
      | (IPlus (IVar i, y), iexp) | (iexp, IPlus (IVar i, y)) ->
        let sub = IPlus (IMinus y, iexp) in
          unify_eq top (iSubst i sub eqs) (iSubst i sub bnds) (iSubst i sub subs)
      | (IPlus (IMinus (IVar i), y), iexp) | (iexp, IPlus (IMinus (IVar i), y)) ->
        let sub = IPlus (y, iexp) in
          unify_eq top (iSubst i sub eqs) (iSubst i sub bnds) (iSubst i sub subs)
      | _ -> None
    end
  | (TCons (t1, t2))::xs ->
    begin match (t1, t2) with
      | (TVar i, ty)
      | (ty, TVar i) -> unify_eq top (tSubst i ty xs) (tSubst i ty bnds) ((TCons (TVar i, ty))::(tSubst i ty subs))
      | (TUnit, TUnit) -> unify_eq top xs bnds subs
      | (TBool, TBool) -> unify_eq top xs bnds subs
      | (TArray iexp, TArray iexp') -> unify_eq top ((ICons (iexp, iexp'))::xs) bnds subs
      | (TArrow (t1, t2), TArrow (s1, s2)) -> unify_eq top ((TCons (t1, s1))::(TCons (t2, s2))::xs) bnds subs
      | _ -> None
    end

let rec applySubs subs tm = match subs with
  | [] -> tm
  | (TCons (TVar i, texp))::xs -> applySubs xs (substTyIngExpr tm i (togType texp))
  | _ -> failwith "impossible"

let annotate tm =
  let (top, eqs, bnds, typ) = inferTypes 0 [] tm in
  let res = unify_eq top eqs bnds [] in
    match res with
      | None -> Err "Could not infer types"
      | Some subs -> Val (applySubs subs tm)
