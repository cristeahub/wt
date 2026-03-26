(** Shared utility functions for wt *)

(* Shell-escape a string by wrapping in single quotes and escaping embedded single quotes *)
let shell_escape s =
  "'" ^ String.concat "'\\''" (String.split_on_char '\'' s) ^ "'"

(* Encode a branch name for safe filesystem use.
   Uses underscore escaping: '_' -> '__', '/' -> '_'
   (e.g. branches "feature/auth" and "feature_auth" map to distinct paths). *)
let safe_branch_name branch_name =
  let buf = Buffer.create (String.length branch_name) in
  String.iter (fun c ->
    match c with
    | '_' -> Buffer.add_string buf "__"
    | '/' -> Buffer.add_char buf '_'
    | _ -> Buffer.add_char buf c
  ) branch_name;
  Buffer.contents buf

let get_wt_base_dir () =
  let home = Sys.getenv "HOME" in
  Filename.concat (Filename.concat (Filename.concat home ".local") "share") "wt"

let ensure_dir_exists path =
  if not (Sys.file_exists path) then
    let rec mkdir_p path =
      let parent = Filename.dirname path in
      if parent <> path && not (Sys.file_exists parent) then
        mkdir_p parent;
      if not (Sys.file_exists path) then
        Unix.mkdir path 0o755
    in
    mkdir_p path

let run_command cmd =
  let ic = Unix.open_process_in cmd in
  let rec read_lines acc =
    match input_line ic with
    | line -> read_lines (line :: acc)
    | exception End_of_file ->
        ignore (Unix.close_process_in ic);
        List.rev acc
  in
  read_lines []

let run_command_status ?(quiet=true) cmd =
  let redirect = if quiet then " >/dev/null 2>&1" else " 2>/dev/null" in
  let exit_code = Sys.command (cmd ^ redirect) in
  exit_code = 0

let run_command_output cmd =
  let ic = Unix.open_process_in cmd in
  let output = Buffer.create 256 in
  (try
     while true do
       Buffer.add_char output (input_char ic)
     done
   with End_of_file -> ());
  ignore (Unix.close_process_in ic);
  String.trim (Buffer.contents output)

let read_file path =
  if Sys.file_exists path then
    let ic = open_in path in
    let n = in_channel_length ic in
    let s = really_input_string ic n in
    close_in ic;
    Some (String.trim s)
  else
    None

let write_file path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

let list_dir path =
  if Sys.file_exists path && Sys.is_directory path then
    Array.to_list (Sys.readdir path)
  else
    []

(* Directories in the wt base dir that are internal, not repos *)
let internal_dirs = ["docker"; "sessions"]

let is_repo_dir base_dir name =
  (not (List.mem name internal_dirs)) &&
  Sys.is_directory (Filename.concat base_dir name)

(* Decode an underscore-escaped branch name back to the original.
   Reverses safe_branch_name: '__' -> '_', single '_' -> '/' *)
let decode_branch_name encoded =
  let len = String.length encoded in
  let buf = Buffer.create len in
  let i = ref 0 in
  while !i < len do
    if !i + 1 < len && encoded.[!i] = '_' && encoded.[!i + 1] = '_' then begin
      Buffer.add_char buf '_';
      i := !i + 2
    end else if encoded.[!i] = '_' then begin
      Buffer.add_char buf '/';
      i := !i + 1
    end else begin
      Buffer.add_char buf encoded.[!i];
      i := !i + 1
    end
  done;
  Buffer.contents buf
