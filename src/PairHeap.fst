module PairHeap

(* PairHeap - An implementation of pairing heaps (see wikipedia).
              There are no duplicates allowed, and proven properties include
              that all operations preserve the heap property (get min is the
              min). Note that the is_heap property isn't this exactly -- is_heap
              means the root is less than the root of each subheap. It is later
              proven that this property implies the heap property. *)

open FStar.List
open Util

// Pairing heaps with no duplicate elements
type heap 'a =
  | Empty
  | Heap of 'a * list (heap 'a)
type intHeap = heap int

val subheaps : hp:intHeap{~(is_Empty hp)} -> Tot (list intHeap)
let subheaps hp = match hp with
  | Heap (r, lst) -> lst

val merge : intHeap -> intHeap -> Tot intHeap
let merge hp1 hp2 = match (hp1, hp2) with
  | (Empty, _) -> hp2
  | (_, Empty) -> hp1
  | (Heap (r1, h1), Heap (r2, h2)) ->
    if r1 = r2 then      Heap (r1, (h2@h1))
    else if r1 < r2 then Heap (r1, (hp2::h1))
    else                 Heap (r2, (hp1::h2))

val insert : intHeap -> int -> Tot intHeap
let insert hp i = merge hp (Heap (i, []))

val mergePairs : list intHeap -> Tot intHeap
let rec mergePairs hplst = match hplst with
  | [] -> Empty
  | x::[] -> x
  | x::y::xs -> merge (merge x y) (mergePairs xs)

val deleteMin : hp:intHeap{~(is_Empty hp)} -> Tot intHeap
let deleteMin hp = match hp with
  | Heap (_, lst) -> mergePairs lst

val getMin : hp:intHeap{~(is_Empty hp)} -> Tot int
let getMin hp = match hp with
  | Heap (r, _) -> r

val mem : int -> hp:intHeap -> Tot bool (decreases %[hp;1])
val mem_lst : int -> l:(list intHeap) -> Tot bool (decreases %[l;0])
let rec mem i hp = match hp with
  | Empty -> false
  | Heap (r, lst) -> i = r || mem_lst i lst
and mem_lst i lst = match lst with
  | [] -> false
  | x::xs -> mem i x || mem_lst i xs

val elts : intHeap -> Tot (set int)
let elts hp = fun i -> mem i hp

// -------------------------------------------------- Heap properties
// Experimental inductive version -- commented out for ocaml extraction
(*
type lt_heap : int -> intHeap -> Type =
  | Leq_Empty : i:int ->
                lt_heap i Empty
  | Leq_Heap  : i:int ->
                r:int{i < r} ->
                lst:list intHeap ->
                lt_heap i (Heap r lst)

type minheap : intHeap -> Type =
  | E_Heap : minheap Empty
  | H_Heap : r:int ->
             lst:list intHeap ->
             ht:(forall hp. List.mem hp lst ==> minheap hp /\ lt_heap r hp) ->
             minheap (Heap r lst)
*)

// Computational version
val leq_heap : i:int -> hp:intHeap -> Tot bool
let leq_heap i hp = match hp with
  | Empty -> true
  | Heap (j, _) -> i < j

val is_heap : hp:intHeap -> Tot bool (decreases %[hp;1])
val is_heap_list : l:(list intHeap) -> Tot bool (decreases %[l;0])
let rec is_heap hp = match hp with
  | Empty -> true
  | Heap (i, lst) -> (is_heap_list lst) && (for_allT (leq_heap i) lst)
and is_heap_list lst = match lst with
  | [] -> true
  | x::xs -> (is_heap x) && (is_heap_list xs)

// Operations are heap preserving
val is_heap_app : l1:list intHeap -> l2:list intHeap ->
  Lemma (requires (is_heap_list l1 /\ is_heap_list l2))
        (ensures  (is_heap_list (l1@l2)))
let rec is_heap_app l1 l2 = match l1 with
  | [] -> ()
  | x::xs -> is_heap_app xs l2

val leq_heap_trans : i:int -> j:int -> l:list intHeap ->
  Lemma (requires (i <= j /\ for_allT (leq_heap j) l))
        (ensures  (for_allT (leq_heap i) l))
let rec leq_heap_trans i j l = match l with
  | [] -> ()
  | x::xs -> leq_heap_trans i j xs

val leq_heap_app : i:int -> l1:list intHeap -> l2:list intHeap ->
  Lemma (requires (for_allT (leq_heap i) l1 /\ for_allT (leq_heap i) l2))
        (ensures  (for_allT (leq_heap i) (l1@l2)))
let rec leq_heap_app i l1 l2 = match l1 with
  | [] -> ()
  | x::xs -> leq_heap_app i xs l2

val swap_root : h:intHeap{not (is_Empty h)} -> i:int -> Tot intHeap
let swap_root h i = match h with
  | Heap (r, lst) -> Heap (i, lst)

val merge_heap : h1:intHeap{is_heap h1} -> h2:intHeap{is_heap h2} -> Lemma (is_heap (merge h1 h2))
let merge_heap hp1 hp2 = match (hp1, hp2) with
  | (Empty, _) | (_, Empty) -> ()
  | (Heap (r1, h1), Heap (r2, h2)) ->
    if r1 = r2 then (
      is_heap_app h2 h1;
      leq_heap_trans r1 r2 h2;
      leq_heap_app r1 h2 h1
    ) else ()

val insert_heap : h:intHeap{is_heap h} -> i:int -> Lemma (is_heap (insert h i))
let insert_heap _ _ = ()

val mergePairs_heap : lst:(list intHeap) ->
  Lemma (requires (is_heap_list lst))
        (ensures (is_heap (mergePairs lst)))
let rec mergePairs_heap lst = match lst with
  | [] -> ()
  | x::[] -> ()
  | x::y::xs ->
    merge_heap x y;
    mergePairs_heap xs;
    merge_heap (merge x y) (mergePairs xs)

val deleteMin_heap : h:intHeap{~(is_Empty h)} ->
  Lemma (requires (is_heap h))
        (ensures (is_heap (deleteMin h)))
let deleteMin_heap hp = match hp with
  | Heap (_, lst) -> mergePairs_heap lst

val leq_tree_trans : i:int -> j:int ->
  Lemma (requires (i <= j))
        (ensures (forall h. (is_heap (Heap (j, [h]))) ==> (is_heap (Heap (i, [h])))))
let leq_tree_trans i j = ()

type leq_all (i:int) (hp:intHeap) = forall j. mem j hp ==> i <= j

val leq_all_trans : i:int -> j:int -> hp:intHeap ->
  Lemma (requires (i <= j /\ leq_all j hp))
        (ensures  (leq_all i hp))
let leq_all_trans i j hp = ()

// Membership
val mem_app : l1:list intHeap -> l2:list intHeap ->
  Lemma (requires true)
        (ensures  (forall i. mem_lst i (l1@l2) <==> mem_lst i l1 \/ mem_lst i l2))
let rec mem_app l1 l2 = match l1 with
  | [] -> ()
  | x::xs -> mem_app xs l2

val mem_merge : h1:intHeap -> h2:intHeap ->
  Lemma (requires true)
        (ensures (forall i. mem i (merge h1 h2) <==> mem i h1 \/ mem i h2))
let mem_merge h1 h2 = match (h1, h2) with
  | (Empty, _) -> ()
  | (_, Empty) -> ()
  | (Heap (r1, h1), Heap (r2, h2)) ->
    if r1 = r2 then mem_app h2 h1
    else ()

val mem_mergePairs : l:(list intHeap) ->
  Lemma (requires true)
        (ensures  (forall i. mem i (mergePairs l) <==> mem_lst i l))
let rec mem_mergePairs l = match l with
  | [] -> ()
  | x::[] -> ()
  | x::y::xs -> mem_merge x y; mem_mergePairs xs; mem_merge (merge x y) (mergePairs xs)

val mem_insert : h:intHeap -> i:int ->
  Lemma (requires true)
        (ensures (forall j. mem j (insert h i) <==> j = i \/ mem j h))
let mem_insert h i = mem_merge h (Heap (i, []))

// Correctness
val leq_is_min : i:int -> h:intHeap{is_heap h} ->
  Lemma (requires (leq_heap i h))
        (ensures  (forall j. mem j h ==> i < j))
  (decreases %[h;1])
val leq_is_min_list : i:int -> l:(list intHeap){is_heap_list l} ->
  Lemma (requires (for_allT (leq_heap i) l))
        (ensures  (forall j. mem_lst j l ==> i < j))
  (decreases %[l;0])
let rec leq_is_min i h = match h with
  | Empty -> ()
  | Heap (r, l) -> leq_heap_trans i r l; leq_is_min_list i l
and leq_is_min_list i l = match l with
  | [] -> ()
  | x::xs -> leq_is_min i x; leq_is_min_list i xs

// No duplicates
val deleteMin_not_in_heap : h:intHeap{is_heap h /\ ~(is_Empty h)} ->
  Lemma (not (mem (getMin h) (deleteMin h)))
let deleteMin_not_in_heap h = match h with
  | Heap (r, lst) -> leq_is_min_list r lst; mem_mergePairs lst