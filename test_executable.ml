open Core_kernel

let binary = Sys.argv.(1)
let args = Array.(sub Sys.argv ~pos:2 ~len:(length Sys.argv - 2))
let _ = Array.stable_sort ~compare:String.compare args;

Array.iter ~f:(fun arg ->
    let cmd = "./" ^ binary ^ " " ^ arg in
    Printf.printf "$ %s\n" cmd;
    let stdout, _, stderr = Unix.open_process_full cmd (Array.create ~len:0 "") in
    let chns = [stdout; stderr] in
    let out = List.map ~f:In_channel.input_lines chns in
    List.iter ~f:In_channel.close chns;
    List.iter ~f:(List.iter ~f:(Printf.printf "%s\n")) out;
    Printf.printf "\n"
  ) args
