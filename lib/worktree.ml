(** Worktree management module *)

let get_worktree_path repo_name branch_name =
  let base = Utils.get_wt_base_dir () in
  let safe_branch = Utils.safe_branch_name branch_name in
  Filename.concat (Filename.concat base repo_name) safe_branch

(* Returns list of (repo_name, worktree_path) for all repos that have this branch *)
let find_all_existing_worktrees branch_name =
  let base_dir = Utils.get_wt_base_dir () in
  let safe_branch = Utils.safe_branch_name branch_name in
  if not (Sys.file_exists base_dir) then []
  else
    let repos = Utils.list_dir base_dir in
    let matches = List.filter_map (fun repo ->
      if not (Utils.is_repo_dir base_dir repo) then None
      else
        let wt_path = Filename.concat (Filename.concat base_dir repo) safe_branch in
        if Sys.file_exists wt_path && Sys.is_directory wt_path then
          Some (repo, wt_path)
        else
          None
    ) repos in
    List.sort (fun (a, _) (b, _) -> String.compare a b) matches

(* Prompt user to select from multiple repos *)
let prompt_repo_selection matches branch_name =
  Printf.eprintf "Branch '%s' exists in multiple repos:\n\n" branch_name;
  List.iteri (fun i (repo, path) ->
    Printf.eprintf "  %d) %s -> %s\n" (i + 1) repo path
  ) matches;
  Printf.eprintf "\nSelect [1-%d]: %!" (List.length matches);
  try
    let input = String.trim (input_line stdin) in
    let choice = int_of_string input in
    if choice >= 1 && choice <= List.length matches then
      Some (snd (List.nth matches (choice - 1)))
    else begin
      Printf.eprintf "Invalid selection.\n";
      None
    end
  with _ ->
    Printf.eprintf "Invalid selection.\n";
    None

let branch_command branch_name =
  (* First check if we already have worktrees for this branch anywhere *)
  let matches = find_all_existing_worktrees branch_name in
  match matches with
  | [(_, path)] ->
      (* Single match, just return the path *)
      Printf.printf "%s\n" path
  | _ :: _ :: _ ->
      (* Multiple matches, let user select *)
      (match prompt_repo_selection matches branch_name with
      | Some path -> Printf.printf "%s\n" path
      | None -> exit 1)
  | [] ->
      (* No existing worktree found, check if we're in a git repo to create one *)
      if not (Git.is_inside_git_repo ()) then begin
        Printf.eprintf "Error: Not inside a git repository\n";
        exit 1
      end;

      let repo_name = match Git.get_repo_name () with
        | Some name -> name
        | None ->
            Printf.eprintf "Error: Could not determine repository name\n";
            exit 1
      in

      let worktree_path = get_worktree_path repo_name branch_name in
      let branch_exists = Git.branch_exists branch_name in
      let worktree_exists = Sys.file_exists worktree_path in

      (match (branch_exists, worktree_exists) with
      | (true, true) ->
          (* Both exist, just print the path to navigate to *)
          Printf.printf "%s\n" worktree_path
      | (true, false) ->
          (* Branch exists but no worktree in wt directory *)
          (* First check if branch is already checked out somewhere *)
          (match Git.get_worktree_for_branch branch_name with
          | Some existing_path ->
              (* Branch is already checked out, navigate there *)
              Printf.printf "%s\n" existing_path
          | None ->
              (* Branch not checked out anywhere, safe to create worktree *)
              Utils.ensure_dir_exists (Filename.dirname worktree_path);
              if Git.add_worktree worktree_path branch_name then begin
                Printf.printf "Created worktree at: %s\n" worktree_path;
                Printf.printf "%s\n" worktree_path
              end else begin
                Printf.eprintf "Error: Failed to create worktree\n";
                exit 1
              end)
      | (false, true) ->
          (* Worktree exists but branch doesn't - unusual state, inform user *)
          Printf.eprintf "Warning: Worktree exists at %s but branch '%s' doesn't exist\n"
            worktree_path branch_name;
          Printf.printf "%s\n" worktree_path
      | (false, false) ->
          (* Neither exists, create both *)
          Utils.ensure_dir_exists (Filename.dirname worktree_path);
          if Git.add_worktree_new_branch worktree_path branch_name then begin
            Printf.printf "Created branch '%s' and worktree at: %s\n" branch_name worktree_path;
            Printf.printf "%s\n" worktree_path
          end else begin
            Printf.eprintf "Error: Failed to create branch and worktree\n";
            exit 1
          end)

(* Extract repo and branch names from a worktree path *)
let extract_repo_branch_from_path worktree_path =
  let base_dir = Utils.get_wt_base_dir () in
  let base_len = String.length base_dir in
  let path_len = String.length worktree_path in
  if path_len > base_len + 1 &&
     String.sub worktree_path 0 base_len = base_dir then
    (* Path is like: base_dir/repo/branch *)
    let relative = String.sub worktree_path (base_len + 1) (path_len - base_len - 1) in
    match String.index_opt relative '/' with
    | Some idx ->
        let repo = String.sub relative 0 idx in
        let branch = String.sub relative (idx + 1) (String.length relative - idx - 1) in
        Some (repo, branch)
    | None -> None
  else
    None

(* Helper to remove worktree at a given path, works both inside and outside git repos *)
let remove_worktree_at_path worktree_path =
  if not (Sys.file_exists worktree_path) then begin
    Printf.printf "No worktree found at: %s\n" worktree_path
  end else begin
    (* Get git dir before removing the worktree *)
    let git_dir = Git.get_git_common_dir_from_path worktree_path in
    (* Remove the directory using shell-safe quoting *)
    let cmd = Printf.sprintf "rm -rf %s" (Utils.shell_escape worktree_path) in
    ignore (Sys.command cmd);
    (* Prune to clean up git's worktree tracking *)
    (match git_dir with
     | Some dir -> ignore (Git.prune_worktrees_using_git_dir dir)
     | None -> ());
    Printf.printf "Removed worktree at: %s\n" worktree_path;
    (* Remove associated Docker container if any *)
    (match extract_repo_branch_from_path worktree_path with
     | Some (repo, branch) ->
         ignore (Docker.force_remove_container repo branch)
     | None -> ())
  end

let delete_command branch_name =
  (* First check for existing worktrees with this branch name *)
  let matches = find_all_existing_worktrees branch_name in
  match matches with
  | [(_, path)] ->
      (* Single match, delete it *)
      remove_worktree_at_path path
  | _ :: _ :: _ ->
      (* Multiple matches, let user select *)
      (match prompt_repo_selection matches branch_name with
      | Some path -> remove_worktree_at_path path
      | None -> exit 1)
  | [] ->
      (* No existing worktree found, try current repo if we're in one *)
      if Git.is_inside_git_repo () then begin
        let repo_name = match Git.get_repo_name () with
          | Some name -> name
          | None ->
              Printf.eprintf "Error: Could not determine repository name\n";
              exit 1
        in
        let worktree_path = get_worktree_path repo_name branch_name in
        remove_worktree_at_path worktree_path
      end else begin
        Printf.eprintf "Error: No worktree found for branch '%s'\n" branch_name;
        exit 1
      end

(* Helper for delete_both that handles worktree and branch deletion *)
let delete_worktree_and_branch worktree_path branch_name =
  (* Get git common dir BEFORE removing worktree *)
  let git_dir = Git.get_git_common_dir_from_path worktree_path in
  let branch_exists = Git.branch_exists_from_path worktree_path branch_name in

  (* Check if we're currently inside the worktree we're deleting *)
  let cwd = Sys.getcwd () in
  if String.length cwd >= String.length worktree_path &&
     String.sub cwd 0 (String.length worktree_path) = worktree_path then begin
    Printf.eprintf "Error: Cannot delete worktree while inside it. Please cd elsewhere first.\n";
    exit 1
  end;

  (* Remove worktree (handles git unregistration) *)
  remove_worktree_at_path worktree_path;

  (* Then delete the branch using the git dir we saved *)
  if branch_exists then begin
    match git_dir with
    | Some dir ->
        if Git.delete_branch_using_git_dir dir branch_name then
          Printf.printf "Deleted branch: %s\n" branch_name
        else
          Printf.eprintf "Warning: Failed to delete branch '%s'\n" branch_name
    | None ->
        Printf.eprintf "Warning: Could not delete branch '%s' (git dir not found)\n" branch_name
  end else
    Printf.printf "Branch '%s' does not exist\n" branch_name

let delete_both_command branch_name =
  (* First check for existing worktrees with this branch name *)
  let matches = find_all_existing_worktrees branch_name in
  match matches with
  | [(_, path)] ->
      (* Single match, delete it and branch *)
      delete_worktree_and_branch path branch_name
  | _ :: _ :: _ ->
      (* Multiple matches, let user select *)
      (match prompt_repo_selection matches branch_name with
      | Some path -> delete_worktree_and_branch path branch_name
      | None -> exit 1)
  | [] ->
      (* No existing worktree found, try current repo if we're in one *)
      if Git.is_inside_git_repo () then begin
        let repo_name = match Git.get_repo_name () with
          | Some name -> name
          | None ->
              Printf.eprintf "Error: Could not determine repository name\n";
              exit 1
        in

        let worktree_path = get_worktree_path repo_name branch_name in
        let branch_exists = Git.branch_exists branch_name in

        let current_branch = Git.get_current_branch () in
        if current_branch = branch_name then begin
          Printf.eprintf "Error: Cannot delete the currently checked out branch '%s'\n" branch_name;
          exit 1
        end;

        (* Remove worktree first if it exists *)
        remove_worktree_at_path worktree_path;

        (* Then delete the branch *)
        if branch_exists then begin
          if Git.delete_branch branch_name then
            Printf.printf "Deleted branch: %s\n" branch_name
          else begin
            Printf.eprintf "Warning: Failed to delete branch '%s'\n" branch_name
          end
        end else
          Printf.printf "Branch '%s' does not exist\n" branch_name
      end else begin
        Printf.eprintf "Error: No worktree found for branch '%s'\n" branch_name;
        exit 1
      end

let list_command () =
  let base_dir = Utils.get_wt_base_dir () in
  if not (Sys.file_exists base_dir) then begin
    Printf.printf "No worktrees found.\n";
    exit 0
  end;

  let repos = Utils.list_dir base_dir
    |> List.filter (Utils.is_repo_dir base_dir) in
  if repos = [] then begin
    Printf.printf "No worktrees found.\n";
    exit 0
  end;

  List.iter (fun repo ->
    let repo_path = Filename.concat base_dir repo in
    Printf.printf "%s:\n" repo;
    let branches = Utils.list_dir repo_path in
    List.iter (fun branch ->
      let branch_path = Filename.concat repo_path branch in
      if Sys.is_directory branch_path then
        Printf.printf "  %s -> %s\n" (Utils.decode_branch_name branch) branch_path
    ) (List.sort String.compare branches)
  ) (List.sort String.compare repos)
