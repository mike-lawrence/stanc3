(* Code for optimization passes on the MIR *)
open Core_kernel
open Mir

let create_function_inline_map {stmt; _} =
  (* We only add the first definition for each function to the inline map.
   This will make sure we do not inline recursive functions. *)
  let f accum {stmt; _} =
    match stmt with
    | FunDef {fdname; fdargs; fdbody; _} -> (
      match
        Map.add accum ~key:fdname
          ~data:(List.map ~f:(fun (_, name, _) -> name) fdargs, fdbody.stmt)
      with
      | `Ok m -> m
      | `Duplicate -> accum )
    | _ -> Errors.fatal_error ()
  in
  match stmt with
  | Assignment (_, _)
   |TargetPE _
   |NRFunApp (_, _)
   |Check _ | Break | Continue | Return _ | Skip
   |IfElse (_, _, _)
   |While (_, _)
   |For _ | Block _ | Decl _ | FunDef _ ->
      Errors.fatal_error ()
  | SList l -> List.fold l ~init:Map.Poly.empty ~f

let replace_fresh_local_vars s = s

(* TODO *)

let substitute_args _ _ b = b

(* TODO *)

let handle_early_returns b = b

(* TODO: could do something like create a loop with a single
iteration so we can use control operators like break *)

let map_no_loc l = List.map ~f:(fun s -> {stmt= s; sloc= ""}) l
let slist_no_loc l = SList (map_no_loc l)

let rec inline_function_statement fim {stmt; sloc} =
  { stmt=
      ( match stmt with
      | Assignment (e1, e2) ->
          let sl1, e1 = inline_function_expression fim e1 in
          let sl2, e2 = inline_function_expression fim e2 in
          slist_no_loc (sl1 @ sl2 @ [Assignment (e1, e2)])
      | TargetPE e ->
          let s, e = inline_function_expression fim e in
          slist_no_loc (s @ [TargetPE e])
      | NRFunApp (s, es) ->
          let se_list = List.map ~f:(inline_function_expression fim) es in
          let s_list = List.concat (List.map ~f:fst se_list) in
          let es = List.map ~f:snd se_list in
          slist_no_loc
            ( s_list
            @ [ ( match Map.find fim s with
                | None -> NRFunApp (s, es)
                | Some (args, b) ->
                    let b = replace_fresh_local_vars b in
                    substitute_args args es b ) ] )
      | Check {ccfunname; ccvid; cctype; ccargs} ->
          let se_list = List.map ~f:(inline_function_expression fim) ccargs in
          let s_list = List.concat (List.map ~f:fst se_list) in
          let es = List.map ~f:snd se_list in
          slist_no_loc (s_list @ [Check {ccfunname; ccvid; cctype; ccargs= es}])
      | Return e -> (
        match e with
        | None -> Return None
        | Some e ->
            let s, e = inline_function_expression fim e in
            slist_no_loc (s @ [Return (Some e)]) )
      | IfElse (e, s1, s2) ->
          let s, e = inline_function_expression fim e in
          slist_no_loc
            ( s
            @ [ IfElse
                  ( e
                  , inline_function_statement fim s1
                  , Option.map ~f:(inline_function_statement fim) s2 ) ] )
      | While (e, s) ->
          let s', e = inline_function_expression fim e in
          slist_no_loc
            ( s'
            @ [ While
                  ( e
                  , { stmt=
                        SList
                          ([inline_function_statement fim s] @ map_no_loc s')
                    ; sloc= "" } ) ] )
      | For {loopvar; lower; upper; body} ->
          let s_lower, lower = inline_function_expression fim lower in
          let s_upper, upper = inline_function_expression fim upper in
          slist_no_loc
            ( s_lower @ s_upper
            @ [ For
                  { loopvar
                  ; lower
                  ; upper
                  ; body=
                      { stmt=
                          SList
                            ( [inline_function_statement fim body]
                            @ map_no_loc s_upper )
                      ; sloc= "" } } ] )
      | Block l -> Block (List.map l ~f:(inline_function_statement fim))
      | SList l -> SList (List.map l ~f:(inline_function_statement fim))
      | FunDef _ -> Errors.fatal_error ()
      | Decl r -> Decl r
      | Skip -> Skip
      | Break -> Break
      | Continue -> Continue )
  ; sloc }

and inline_function_expression fim e =
  match e with
  | Var x -> ([], Var x)
  | Lit (t, v) -> ([], Lit (t, v))
  | FunApp (s, es) -> (
      let se_list = List.map ~f:(inline_function_expression fim) es in
      let s_list = List.concat (List.map ~f:fst se_list) in
      let es = List.map ~f:snd se_list in
      match Map.find fim s with
      | None -> ([], FunApp (s, es))
      | Some (args, b) ->
          let b = replace_fresh_local_vars b in
          let x = Util.gensym () in
          (s_list @ [substitute_args args es b], Var x) )
  | BinOp (e1, op, e2) ->
      let sl1, e1 = inline_function_expression fim e1 in
      let sl2, e2 = inline_function_expression fim e2 in
      (sl1 @ sl2, BinOp (e1, op, e2))
  | TernaryIf (e1, e2, e3) ->
      let sl1, e1 = inline_function_expression fim e1 in
      let sl2, e2 = inline_function_expression fim e2 in
      let sl3, e3 = inline_function_expression fim e3 in
      ( sl1
        @ [ IfElse
              ( e1
              , {stmt= slist_no_loc sl2; sloc= ""}
              , Some {stmt= slist_no_loc sl3; sloc= ""} ) ]
      , TernaryIf (e1, e2, e3) )
  | Indexed (e, i_list) ->
      let sl, e = inline_function_expression fim e in
      let si_list = List.map ~f:(inline_function_index fim) i_list in
      let i_list = List.map ~f:snd si_list in
      let s_list = List.concat (List.map ~f:fst si_list) in
      (sl @ s_list, Indexed (e, i_list))

and inline_function_index fim i =
  match i with
  | All -> ([], All)
  | Single e ->
      let sl, e = inline_function_expression fim e in
      (sl, Single e)
  | Upfrom e ->
      let sl, e = inline_function_expression fim e in
      (sl, Upfrom e)
  | Downfrom e ->
      let sl, e = inline_function_expression fim e in
      (sl, Downfrom e)
  | Between (e1, e2) ->
      let sl1, e1 = inline_function_expression fim e1 in
      let sl2, e2 = inline_function_expression fim e2 in
      (sl1 @ sl2, Between (e1, e2))
  | MultiIndex e ->
      let sl, e = inline_function_expression fim e in
      (sl, MultiIndex e)

let function_inlining (mir : stmt_loc prog) =
  let function_inline_map = create_function_inline_map mir.functionsb in
  { functionsb= mir.functionsb
  ; datavars= mir.datavars
  ; tdatab=
      ( fst mir.tdatab
      , inline_function_statement function_inline_map (snd mir.tdatab) )
  ; modelb=
      ( fst mir.modelb
      , inline_function_statement function_inline_map (snd mir.modelb) )
  ; gqb=
      (fst mir.gqb, inline_function_statement function_inline_map (snd mir.gqb))
  ; prog_name= mir.prog_name
  ; prog_path= mir.prog_path }

(* Let's do a simple CSE pass,
ideally expressed as a visitor with a separate visit() function? *)
(*
open Core_kernel
open Mir

let _counter = ref 0;;
let gensym =
  fun () ->
    _counter := (!_counter) + 1;
    String.concat ["sym"; (string_of_int !_counter)];;

let rec count_subtrees_rec fnapp2sym e =
  match e with
  | FnApp(_, args) ->
    let _ = List.map args ~f:(count_subtrees_rec fnapp2sym) in
    Hashtbl.Poly.update fnapp2sym e ~f:(function Some(i) -> i+1 | None -> 1)
  | _ -> ()

let count_subtrees e = let fnapp2sym = Hashtbl.Poly.create () in
  count_subtrees_rec fnapp2sym e;
  fnapp2sym

let%expect_test "count_subtrees" =
  let dict = count_subtrees (FnApp("plus",
                                   [FnApp("plus", [Lit(Int, "2"); Lit(Int, "3")]);
                                    FnApp("plus", [Lit(Int, "2"); Lit(Int, "3")])])) in
  print_s [%sexp (Hashtbl.Poly.to_alist dict : (expr * int) list)];
  [%expect{|
    (((FnApp plus ((Lit Int 2) (Lit Int 3))) 2)
     ((FnApp plus
       ((FnApp plus ((Lit Int 2) (Lit Int 3)))
        (FnApp plus ((Lit Int 2) (Lit Int 3)))))
      1)) |}]

let filter_dups fnapp2sym =
  let dups = Hashtbl.Poly.filter fnapp2sym ~f:(fun x -> x > 1) in
  Hashtbl.Poly.map dups ~f:(fun _ -> gensym ())

let add_assigns dups e =
  if Hashtbl.Poly.is_empty dups then e
  else
    Hashtbl.Poly.fold dups ~init:[e] ~f:(fun ~key:ast_node ~data:var l ->
        AssignExpr(var, ast_node) :: l)
    |> ExprList

let%expect_test "add_assigns" =
  let ast_node = (FnApp("plus", [Lit(Int, "2")])) in
  let dups = Hashtbl.Poly.of_alist_exn [(Var "hi"), "lo"] in
  print_s [%sexp ((add_assigns dups ast_node) : expr)];
  [%expect{| (ExprList ((AssignExpr lo (Var hi)) (FnApp plus ((Lit Int 2))))) |}]

let rec replace_usages dups e = match Hashtbl.Poly.find dups e with
  | Some(sym) -> Var sym
  | None -> (match e with
      | FnApp(fname, args) -> FnApp(fname, List.map args
                                      ~f:(replace_usages dups))
      | x -> x)

let%expect_test "replace_usages" =
  let e = (FnApp("p", [Lit(Int, "2")])) in
  let dups = Hashtbl.Poly.of_alist_exn [e, "sup"] in
  print_s [%sexp ((replace_usages dups e) : expr)];
  [%expect{| (Var sup) |}]

let cse e = let dups = filter_dups (count_subtrees e) in
  add_assigns dups (replace_usages dups e)

let optimize e =
  e |> Peep.run_peephole_opts |> cse

let%expect_test _ =
  print_s [%sexp
    ((optimize
        (FnApp("plus",
               [FnApp("log", [FnApp("minus", [Lit(Int, "1"); (Var "hi")])]);
                FnApp("log", [FnApp("minus", [Lit(Int, "1"); (Var "hi")])])])))
     : expr)];
  [%expect{|
      (ExprList
       ((AssignExpr sym1 (FnApp log1m ((Var hi))))
        (FnApp plus ((Var sym1) (Var sym1))))) |}]
*)

(* XXX
   Todos to make code gen as good as Stan 2 codegen
   1. Turn all autodiff types on vardecls in data block to data type
   2. CSE
   3. loop-invariant code motion
*)
