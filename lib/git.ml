(** Git utility functions for wt CLI tool *)

let is_inside_git_repo () =
  Utils.run_command_status "git rev-parse --is-inside-work-tree"

let get_repo_root () =
  if is_inside_git_repo () then
    Some (Utils.run_command_output "git rev-parse --show-toplevel")
  else
    None

let get_repo_name () =
  match get_repo_root () with
  | Some root -> Some (Filename.basename root)
  | None -> None

let branch_exists branch_name =
  Utils.run_command_status (Printf.sprintf "git show-ref --verify --quiet refs/heads/%s" (Utils.shell_escape branch_name))

let create_branch branch_name =
  Utils.run_command_status (Printf.sprintf "git branch %s" (Utils.shell_escape branch_name))

let delete_branch branch_name =
  Utils.run_command_status (Printf.sprintf "git branch -D %s" (Utils.shell_escape branch_name))

let delete_branch_from_path path branch_name =
  Utils.run_command_status (Printf.sprintf "git -C %s branch -D %s" (Utils.shell_escape path) (Utils.shell_escape branch_name))

let get_current_branch () =
  Utils.run_command_output "git branch --show-current"

let get_current_branch_from_path path =
  Utils.run_command_output (Printf.sprintf "git -C %s branch --show-current" (Utils.shell_escape path))

let branch_exists_from_path path branch_name =
  Utils.run_command_status (Printf.sprintf "git -C %s show-ref --verify --quiet refs/heads/%s" (Utils.shell_escape path) (Utils.shell_escape branch_name))

let get_git_common_dir_from_path path =
  (* Use --absolute-git-dir to get an absolute path that works after worktree removal *)
  let result = Utils.run_command_output (Printf.sprintf "git -C %s rev-parse --absolute-git-dir 2>/dev/null" (Utils.shell_escape path)) in
  if result = "" then None
  else
    (* For worktrees, --absolute-git-dir returns .git/worktrees/<name>, we need the parent .git dir *)
    let git_dir = result in
    (* Check if it's a worktree git dir (contains /worktrees/) *)
    if String.length git_dir > 11 then
      try
        let idx = ref (-1) in
        for i = 0 to String.length git_dir - 11 do
          if String.sub git_dir i 11 = "/worktrees/" then idx := i
        done;
        if !idx >= 0 then Some (String.sub git_dir 0 !idx)
        else Some git_dir
      with _ -> Some git_dir
    else Some git_dir

let delete_branch_using_git_dir git_dir branch_name =
  Utils.run_command_status (Printf.sprintf "git --git-dir=%s branch -D %s" (Utils.shell_escape git_dir) (Utils.shell_escape branch_name))

let worktree_exists path =
  let worktrees = Utils.run_command "git worktree list --porcelain" in
  List.exists (fun line ->
    String.length line > 9 &&
    String.sub line 0 9 = "worktree " &&
    String.sub line 9 (String.length line - 9) = path
  ) worktrees

let add_worktree path branch_name =
  Utils.run_command_status (Printf.sprintf "git worktree add %s %s 2>/dev/null" (Utils.shell_escape path) (Utils.shell_escape branch_name))

let add_worktree_new_branch path branch_name =
  Utils.run_command_status (Printf.sprintf "git worktree add -b %s %s 2>/dev/null" (Utils.shell_escape branch_name) (Utils.shell_escape path))

let remove_worktree path =
  Utils.run_command_status (Printf.sprintf "git worktree remove --force %s 2>/dev/null" (Utils.shell_escape path))

let remove_worktree_using_git_dir git_dir path =
  Utils.run_command_status (Printf.sprintf "git --git-dir=%s worktree remove --force %s 2>/dev/null" (Utils.shell_escape git_dir) (Utils.shell_escape path))

let prune_worktrees_using_git_dir git_dir =
  Utils.run_command_status (Printf.sprintf "git --git-dir=%s worktree prune 2>/dev/null" (Utils.shell_escape git_dir))

let list_worktrees () =
  Utils.run_command "git worktree list"

let get_worktree_for_branch branch_name =
  let worktrees = Utils.run_command "git worktree list --porcelain" in
  let rec find_worktree lines current_path =
    match lines with
    | [] -> None
    | line :: rest ->
        if String.length line > 9 && String.sub line 0 9 = "worktree " then
          let path = String.sub line 9 (String.length line - 9) in
          find_worktree rest (Some path)
        else if String.length line > 7 && String.sub line 0 7 = "branch " then
          let branch = String.sub line 7 (String.length line - 7) in
          let branch_short =
            if String.length branch > 11 && String.sub branch 0 11 = "refs/heads/" then
              String.sub branch 11 (String.length branch - 11)
            else
              branch
          in
          if branch_short = branch_name then
            current_path
          else
            find_worktree rest None
        else
          find_worktree rest current_path
  in
  find_worktree worktrees None
