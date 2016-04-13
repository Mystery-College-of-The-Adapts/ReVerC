(** Functional sets *)
module Set

type set<'a when 'a:comparison>  = Set<'a>

let mem          = Set.contains
let empty        = Set.empty
let singleton    = Set.singleton
let union        = Set.union
let intersection = Set.intersect
let ins          = Set.add
