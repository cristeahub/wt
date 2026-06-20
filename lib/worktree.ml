let get_worktree_path repo_name branch_name =
  let base = Utils.get_wt_base_dir () in
  let safe_branch = Utils.safe_branch_name branch_name in
  Filename.concat (Filename.concat base repo_name) safe_branch

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
  with Failure _ | Invalid_argument _ ->
    Printf.eprintf "Invalid selection.\n";
    None

let resolve_worktree_path branch_name =
  let matches = find_all_existing_worktrees branch_name in
  match matches with
  | [(_, path)] -> Some path
  | _ :: _ :: _ -> prompt_repo_selection matches branch_name
  | [] -> None

let branch_command branch_name =
  match resolve_worktree_path branch_name with
  | Some path ->
      Printf.printf "%s\n" path
  | None ->
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
          Printf.printf "%s\n" worktree_path
      | (true, false) ->
          (match Git.get_worktree_for_branch branch_name with
          | Some existing_path ->
              Printf.printf "%s\n" existing_path
          | None ->
              Utils.ensure_dir_exists (Filename.dirname worktree_path);
              if Git.add_worktree worktree_path branch_name then begin
                (match Git.get_repo_root () with
                 | Some root -> Utils.copy_wtfiles root worktree_path
                 | None -> ());
                Printf.printf "Created worktree at: %s\n" worktree_path;
                Printf.printf "%s\n" worktree_path
              end else begin
                Printf.eprintf "Error: Failed to create worktree\n";
                exit 1
              end)
      | (false, true) ->
          Printf.eprintf "Warning: Worktree exists at %s but branch '%s' doesn't exist\n"
            worktree_path branch_name;
          Printf.printf "%s\n" worktree_path
      | (false, false) ->
          Utils.ensure_dir_exists (Filename.dirname worktree_path);
          if Git.add_worktree_new_branch worktree_path branch_name then begin
            (match Git.get_repo_root () with
             | Some root -> Utils.copy_wtfiles root worktree_path
             | None -> ());
            Printf.printf "Created branch '%s' and worktree at: %s\n" branch_name worktree_path;
            Printf.printf "%s\n" worktree_path
          end else begin
            Printf.eprintf "Error: Failed to create branch and worktree\n";
            exit 1
          end)

let resolve_git_dir git_dir worktree_path =
  match git_dir with
  | Some _ -> git_dir
  | None -> Git.get_git_common_dir_from_path worktree_path

let path_is_at_or_under parent path =
  let parent_len = String.length parent in
  path = parent ||
  (String.length path > parent_len &&
   String.sub path 0 parent_len = parent &&
   path.[parent_len] = '/')

let remove_worktree_at_path ?git_dir worktree_path =
  if not (Sys.file_exists worktree_path) then begin
    Printf.printf "No worktree found at: %s\n" worktree_path
  end else begin
    let git_dir = resolve_git_dir git_dir worktree_path in
    let removed_by_git =
      match git_dir with
      | Some dir -> Git.remove_worktree_using_git_dir dir worktree_path
      | None -> false
    in
    if (not removed_by_git) && Sys.file_exists worktree_path then begin
      let cmd = Printf.sprintf "rm -rf %s" (Utils.shell_escape worktree_path) in
      let exit_code = Sys.command cmd in
      if exit_code <> 0 then begin
        Printf.eprintf "Error: Failed to remove worktree at %s\n" worktree_path;
        exit 1
      end;
      (match git_dir with
       | Some dir -> ignore (Git.prune_worktrees_using_git_dir dir)
       | None -> ())
    end;
    Printf.printf "Removed worktree at: %s\n" worktree_path
  end

let delete_branch_using_git_dir_and_report git_dir branch_name =
  if Git.delete_branch_using_git_dir git_dir branch_name then
    Printf.printf "Deleted branch: %s\n" branch_name
  else if Git.branch_exists_using_git_dir git_dir branch_name then
    Printf.eprintf "Warning: Failed to delete branch '%s'\n" branch_name
  else
    Printf.printf "Branch '%s' does not exist\n" branch_name

let delete_branch_and_report branch_name =
  if Git.delete_branch branch_name then
    Printf.printf "Deleted branch: %s\n" branch_name
  else if Git.branch_exists branch_name then
    Printf.eprintf "Warning: Failed to delete branch '%s'\n" branch_name
  else
    Printf.printf "Branch '%s' does not exist\n" branch_name

let delete_command branch_name =
  match resolve_worktree_path branch_name with
  | Some path ->
      remove_worktree_at_path path
  | None ->
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

let delete_worktree_and_branch ?git_dir worktree_path branch_name =
  let git_dir = resolve_git_dir git_dir worktree_path in

  let cwd = Sys.getcwd () in
  if path_is_at_or_under worktree_path cwd then begin
    Printf.eprintf "Error: Cannot delete worktree while inside it. Please cd elsewhere first.\n";
    exit 1
  end;

  remove_worktree_at_path ?git_dir worktree_path;

  match git_dir with
  | Some dir -> delete_branch_using_git_dir_and_report dir branch_name
  | None ->
      Printf.eprintf "Warning: Could not delete branch '%s' (git dir not found)\n" branch_name

let delete_both_command branch_name =
  match resolve_worktree_path branch_name with
  | Some path ->
      delete_worktree_and_branch path branch_name
  | None ->
      if Git.is_inside_git_repo () then begin
        let repo_name = match Git.get_repo_name () with
          | Some name -> name
          | None ->
              Printf.eprintf "Error: Could not determine repository name\n";
              exit 1
        in

        let worktree_path = get_worktree_path repo_name branch_name in

        let current_branch = Git.get_current_branch () in
        if current_branch = branch_name then begin
          Printf.eprintf "Error: Cannot delete the currently checked out branch '%s'\n" branch_name;
          exit 1
        end;

        remove_worktree_at_path worktree_path;
        delete_branch_and_report branch_name
      end else begin
        Printf.eprintf "Error: No worktree found for branch '%s'\n" branch_name;
        exit 1
      end

let contains_case_insensitive needle haystack =
  try
    let _ = Str.search_forward (Str.regexp_string_case_fold needle) haystack 0 in
    true
  with Not_found -> false

let repo_name_matches name repo =
  if String.contains name '_' then
    false
  else
    let stored_name = String.map (fun c -> if c = '/' then '_' else c) name in
    if stored_name = repo then true
    else contains_case_insensitive stored_name repo

let repo_command name =
  let base_dir = Utils.get_wt_base_dir () in
  if not (Sys.file_exists base_dir) then begin
    Printf.eprintf "No repo or worktree '%s' found.\n" name;
    exit 1
  end;

  let repos = Utils.list_dir base_dir
    |> List.filter (Utils.is_repo_dir base_dir) in

  let repo_matches =
    let exact_name = String.map (fun c -> if c = '/' then '_' else c) name in
    let exact =
      if String.contains name '_' then []
      else List.filter (fun r -> r = exact_name) repos
    in
    if exact <> [] then exact
    else List.filter (repo_name_matches name) repos
  in

  match repo_matches with
  | _ :: _ ->
      List.iter (fun repo ->
        Printf.printf "%s\n" (Filename.concat base_dir repo)
      ) (List.sort String.compare repo_matches)
  | [] ->
      let worktree_entries = List.concat_map (fun repo ->
        let repo_path = Filename.concat base_dir repo in
        Utils.list_dir repo_path
        |> List.filter_map (fun encoded_branch ->
          let branch_path = Filename.concat repo_path encoded_branch in
          if Sys.is_directory branch_path then
            Some (repo, Utils.decode_branch_name encoded_branch, branch_path)
          else
            None)
      ) repos in
      let worktree_matches =
        let exact = List.filter (fun (_, branch, _) -> branch = name) worktree_entries in
        if exact <> [] then exact
        else List.filter (fun (_, branch, _) -> contains_case_insensitive name branch) worktree_entries
      in
      match worktree_matches with
      | [] ->
          Printf.eprintf "No repo or worktree '%s' found.\n" name;
          exit 1
      | matches ->
          matches
          |> List.sort (fun (repo_a, branch_a, _) (repo_b, branch_b, _) ->
            match String.compare repo_a repo_b with
            | 0 -> String.compare branch_a branch_b
            | n -> n)
          |> List.iter (fun (_, _, path) -> Printf.printf "%s\n" path)

let group_entries_by_repo entries =
  let sorted =
    List.sort (fun (repo_a, _, _) (repo_b, _, _) -> String.compare repo_a repo_b) entries
  in
  let rec aux current_repo current_entries groups = function
    | [] ->
        (match current_repo with
         | None -> List.rev groups
         | Some repo -> List.rev ((repo, List.rev current_entries) :: groups))
    | ((repo, _, _) as entry) :: rest ->
        (match current_repo with
         | Some current when current = repo ->
             aux current_repo (entry :: current_entries) groups rest
         | Some current ->
             aux (Some repo) [entry] ((current, List.rev current_entries) :: groups) rest
         | None ->
             aux (Some repo) [entry] groups rest)
  in
  aux None [] [] sorted

let delete_all_command () =
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

  let entries = List.concat_map (fun repo ->
    let repo_path = Filename.concat base_dir repo in
    let branches = Utils.list_dir repo_path in
    List.filter_map (fun encoded ->
      let branch_path = Filename.concat repo_path encoded in
      if Sys.is_directory branch_path then
        Some (repo, Utils.decode_branch_name encoded, branch_path)
      else
        None
    ) branches
  ) repos in

  if entries = [] then begin
    Printf.printf "No worktrees found.\n";
    exit 0
  end;

  Printf.printf "This will delete ALL worktrees and their branches:\n\n";
  List.iter (fun (repo, branch, path) ->
    Printf.printf "  %s: %s -> %s\n" repo branch path
  ) entries;
  Printf.printf "\nAre you sure? [y/N]: %!";
  let input = try String.trim (input_line stdin) with End_of_file -> "" in
  if input <> "y" && input <> "Y" then begin
    Printf.printf "Aborted.\n";
    exit 0
  end;

  group_entries_by_repo entries
  |> List.iter (fun (_repo, repo_entries) ->
    let git_dir =
      List.find_map (fun (_, _, worktree_path) ->
        Git.get_git_common_dir_from_path worktree_path
      ) repo_entries
    in
    List.iter (fun (_, branch_name, worktree_path) ->
      delete_worktree_and_branch ?git_dir worktree_path branch_name
    ) repo_entries
  )

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

  let repo_entries = List.filter_map (fun repo ->
    let repo_path = Filename.concat base_dir repo in
    let branches = Utils.list_dir repo_path in
    let entries = List.filter_map (fun branch ->
      let branch_path = Filename.concat repo_path branch in
      if Sys.is_directory branch_path && Utils.list_dir branch_path <> [] then
        Some (branch, branch_path)
      else
        None
    ) branches in
    match entries with
    | [] -> None
    | entries -> Some (repo, List.sort (fun (a, _) (b, _) -> String.compare a b) entries)
  ) repos in

  if repo_entries = [] then begin
    Printf.printf "No worktrees found.\n";
    exit 0
  end;

  List.iter (fun (repo, entries) ->
    Printf.printf "%s:\n" repo;
    List.iter (fun (branch, branch_path) ->
      Printf.printf "  %s -> %s\n" (Utils.decode_branch_name branch) branch_path
    ) entries
  ) (List.sort (fun (a, _) (b, _) -> String.compare a b) repo_entries)
