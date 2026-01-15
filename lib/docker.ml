(** Docker container management for wt worktrees *)

let image_name = "wt/polyglot"
let image_tag = "latest"
let full_image_name = image_name ^ ":" ^ image_tag

let get_wt_docker_dir () =
  Filename.concat (Utils.get_wt_base_dir ()) "docker"

(* Token file path - stored in wt's data directory *)
let get_token_file () =
  Filename.concat (Utils.get_wt_base_dir ()) "token"

(* Env file path - sourced inside containers for secrets *)
let get_env_file () =
  Filename.concat (Utils.get_wt_base_dir ()) "env"

(* Per-worktree session directory for isolated Claude config *)
let get_session_dir repo_name branch_name =
  let base = Filename.concat (Utils.get_wt_base_dir ()) "sessions" in
  Filename.concat (Filename.concat base repo_name) branch_name

(* Get the .claude directory for a worktree session *)
let get_claude_session_dir repo_name branch_name =
  Filename.concat (get_session_dir repo_name branch_name) ".claude"

(* Get the .claude.json file for a worktree session *)
let get_claude_session_json repo_name branch_name =
  Filename.concat (get_session_dir repo_name branch_name) ".claude.json"

(* Get parent repo's .git directory from worktree path.
   Worktrees have a .git file (not directory) containing:
   gitdir: /path/to/repo/.git/worktrees/<name>
   We need the parent .git directory for mounting in Docker. *)
let get_parent_git_dir worktree_path =
  let git_file = Filename.concat worktree_path ".git" in
  match Utils.read_file git_file with
  | Some content ->
      (* Parse "gitdir: /path/to/.git/worktrees/<name>" *)
      let prefix = "gitdir: " in
      if String.length content > String.length prefix &&
         String.sub content 0 (String.length prefix) = prefix then
        let gitdir = String.sub content (String.length prefix)
          (String.length content - String.length prefix) in
        (* gitdir is like /path/to/.git/worktrees/<name>, find /worktrees/ and extract parent *)
        let worktrees_marker = "/worktrees/" in
        let rec find_marker str pos =
          if pos + String.length worktrees_marker > String.length str then None
          else if String.sub str pos (String.length worktrees_marker) = worktrees_marker then
            Some (String.sub str 0 pos)
          else find_marker str (pos + 1)
        in
        find_marker gitdir 0
      else None
  | None -> None

(* Load OAuth token from file *)
let load_token () =
  Utils.read_file (get_token_file ())

(* Save OAuth token to file *)
let save_token token =
  let wt_dir = Utils.get_wt_base_dir () in
  Utils.ensure_dir_exists wt_dir;
  Utils.write_file (get_token_file ()) token;
  Unix.chmod (get_token_file ()) 0o600;
  (* Also write env file for container sourcing *)
  let env_file = get_env_file () in
  Utils.write_file env_file (Printf.sprintf "export CLAUDE_CODE_OAUTH_TOKEN=%s\n" (Utils.shell_escape token));
  Unix.chmod env_file 0o600

(* Check if token is configured *)
let has_token () =
  match load_token () with
  | Some t -> t <> ""
  | None -> false

(* Try to extract a fresh OAuth token from macOS Keychain *)
let try_extract_keychain_token () =
  try
    let ic = Unix.open_process_in
      "security find-generic-password -s 'Claude Code-credentials' -w 2>/dev/null" in
    let output = Buffer.create 1024 in
    (try
       while true do
         Buffer.add_char output (input_char ic)
       done
     with End_of_file -> ());
    let status = Unix.close_process_in ic in
    match status with
    | Unix.WEXITED 0 ->
        let json = String.trim (Buffer.contents output) in
        let re = Str.regexp {|"claudeAiOauth"[^}]*"accessToken"[ \t\n]*:[ \t\n]*"\([^"]*\)"|} in
        (try
           ignore (Str.search_forward re json 0);
           let token = Str.matched_group 1 json in
           if token <> "" then Some token else None
         with Not_found -> None)
    | _ -> None
  with
  | Unix.Unix_error _ | Sys_error _ | Not_found -> None

(* Refresh token from Keychain before docker operations *)
let refresh_token () =
  match try_extract_keychain_token () with
  | Some token -> save_token token
  | None -> ()

(* Generate container name from repo and branch *)
let get_container_name repo_name branch_name =
  let safe_branch = String.map (fun c ->
    if c = '/' then '-'
    else if c = '_' then '-'
    else if c = '%' then '-'
    else c
  ) branch_name in
  Printf.sprintf "wt-%s-%s" repo_name safe_branch

(* Check if Docker is available *)
let docker_available () =
  Utils.run_command_status ~quiet:false "docker info"

(* Check if image exists *)
let image_exists () =
  Utils.run_command_status ~quiet:false (Printf.sprintf "docker image inspect %s" full_image_name)

(* Build the base image *)
let build_image dockerfile_dir =
  Printf.printf "Building Docker image %s...\n%!" full_image_name;
  let timestamp = string_of_float (Unix.time ()) in
  let cmd = Printf.sprintf "docker build --build-arg CLAUDE_CACHE_BUST=%s -t %s %s"
    timestamp full_image_name dockerfile_dir in
  let exit_code = Sys.command cmd in
  if exit_code = 0 then begin
    Printf.printf "Image built successfully.\n";
    true
  end else begin
    Printf.eprintf "Error: Failed to build Docker image\n";
    false
  end

(* Get container status: Running, Stopped, or NotFound *)
type container_status = Running | Stopped | NotFound

let get_container_status container_name =
  let running = Utils.run_command_output
    (Printf.sprintf "docker ps -q -f name=^%s$" container_name) in
  if running <> "" then Running
  else begin
    let exists = Utils.run_command_output
      (Printf.sprintf "docker ps -aq -f name=^%s$" container_name) in
    if exists <> "" then Stopped
    else NotFound
  end

(* Start or create container for a worktree *)
let start_container repo_name branch_name worktree_path =
  refresh_token ();
  let container_name = get_container_name repo_name branch_name in
  let claude_dir = get_claude_session_dir repo_name branch_name in
  let claude_json = get_claude_session_json repo_name branch_name in
  let env_file = get_env_file () in

  (* Ensure per-worktree session directory exists *)
  Utils.ensure_dir_exists claude_dir;

  (* Ensure per-worktree .claude.json has onboarding completed and /workspace trusted *)
  let needs_patch = match Utils.read_file claude_json with
    | Some content ->
        not (try ignore (Str.search_forward (Str.regexp_string "hasCompletedOnboarding") content 0); true
             with Not_found -> false)
    | None -> true
  in
  if needs_patch then begin
    (* Merge onboarding fields into existing file, or create fresh *)
    let base = match Utils.read_file claude_json with
      | Some content when String.length content > 2 ->
          (* Insert onboarding fields after opening brace *)
          Str.replace_first (Str.regexp "^{")
            "{\"numStartups\":1,\"hasCompletedOnboarding\":true,\"installMethod\":\"native\","
            content
      | _ ->
          "{\"numStartups\":1,\"hasCompletedOnboarding\":true,\"installMethod\":\"native\",\"projects\":{\"/workspace\":{\"hasTrustDialogAccepted\":true,\"hasCompletedProjectOnboarding\":true,\"projectOnboardingSeenCount\":1}}}"
    in
    Utils.write_file claude_json base
  end;

  (* Build env file mount if token is configured *)
  let env_mount = if Sys.file_exists env_file then
    Printf.sprintf "-v %s:/home/dev/.wt-env:ro" env_file
  else "" in

  match get_container_status container_name with
  | Running ->
      Printf.printf "Container %s is already running.\n" container_name;
      true
  | Stopped ->
      Printf.printf "Starting stopped container %s...\n" container_name;
      Utils.run_command_status ~quiet:false (Printf.sprintf "docker start %s" container_name)
  | NotFound ->
      Printf.printf "Creating container %s...\n" container_name;
      (* Get parent .git directory for worktree support.
         Git worktrees have a .git file pointing to /path/to/repo/.git/worktrees/<name>.
         We need to mount the parent repo's .git dir at the same absolute path inside
         the container so git commands work correctly. *)
      let git_mount = match get_parent_git_dir worktree_path with
        | Some git_dir -> Printf.sprintf "-v %s:%s:ro" git_dir git_dir
        | None -> ""
      in
      let cmd = Printf.sprintf
        "docker run -d --name %s \
         -u dev \
         -e HOME=/home/dev \
         -e USER=dev \
         -e TERM=xterm-256color \
         -v %s:/workspace \
         -v %s:/home/dev/.claude \
         -v %s:/home/dev/.claude.json \
         %s \
         %s \
         -w /workspace \
         %s \
         sleep infinity"
        container_name
        worktree_path
        claude_dir
        claude_json
        env_mount
        git_mount
        full_image_name
      in
      if Utils.run_command_status ~quiet:false cmd then begin
        Printf.printf "Container %s started.\n" container_name;
        if not (has_token ()) then
          Printf.printf "Note: No Claude token configured. Run 'wt login' to authenticate.\n";
        true
      end else begin
        Printf.eprintf "Error: Failed to create container\n";
        false
      end

(* Stop a container *)
let stop_container repo_name branch_name =
  let container_name = get_container_name repo_name branch_name in
  match get_container_status container_name with
  | Running ->
      Printf.printf "Stopping container %s...\n" container_name;
      if Utils.run_command_status ~quiet:false (Printf.sprintf "docker stop %s" container_name) then begin
        Printf.printf "Container stopped.\n";
        true
      end else begin
        Printf.eprintf "Error: Failed to stop container\n";
        false
      end
  | Stopped ->
      Printf.printf "Container %s is already stopped.\n" container_name;
      true
  | NotFound ->
      Printf.printf "Container %s does not exist.\n" container_name;
      true

(* Remove a container *)
let remove_container repo_name branch_name =
  let container_name = get_container_name repo_name branch_name in
  match get_container_status container_name with
  | Running ->
      Printf.eprintf "Error: Container %s is running. Stop it first.\n" container_name;
      false
  | Stopped ->
      Printf.printf "Removing container %s...\n" container_name;
      if Utils.run_command_status ~quiet:false (Printf.sprintf "docker rm %s" container_name) then begin
        Printf.printf "Container removed.\n";
        true
      end else begin
        Printf.eprintf "Error: Failed to remove container\n";
        false
      end
  | NotFound ->
      Printf.printf "Container %s does not exist.\n" container_name;
      true

(* Force remove a container (stops it first if running) *)
let force_remove_container repo_name branch_name =
  let container_name = get_container_name repo_name branch_name in
  match get_container_status container_name with
  | Running ->
      Printf.printf "Stopping and removing container %s...\n" container_name;
      if Utils.run_command_status ~quiet:false (Printf.sprintf "docker rm -f %s" container_name) then begin
        Printf.printf "Container removed.\n";
        true
      end else begin
        Printf.eprintf "Warning: Failed to remove container %s\n" container_name;
        false
      end
  | Stopped ->
      Printf.printf "Removing container %s...\n" container_name;
      if Utils.run_command_status ~quiet:false (Printf.sprintf "docker rm %s" container_name) then begin
        Printf.printf "Container removed.\n";
        true
      end else begin
        Printf.eprintf "Warning: Failed to remove container %s\n" container_name;
        false
      end
  | NotFound ->
      true

(* Execute a command in container *)
let exec_in_container repo_name branch_name cmd_args interactive =
  refresh_token ();
  let container_name = get_container_name repo_name branch_name in
  match get_container_status container_name with
  | Running ->
      let it_flag = if interactive then "-it" else "" in
      let escaped_args = Utils.shell_escape ("[ -f /home/dev/.wt-env ] && source /home/dev/.wt-env; " ^ cmd_args) in
      let cmd = Printf.sprintf "docker exec %s -u dev -e HOME=/home/dev -e USER=dev -w /workspace %s bash -c %s"
        it_flag container_name escaped_args in
      Sys.command cmd
  | Stopped ->
      Printf.eprintf "Error: Container %s is not running. Start it first.\n" container_name;
      1
  | NotFound ->
      Printf.eprintf "Error: Container %s does not exist. Start it first.\n" container_name;
      1

(* Open interactive shell in container *)
let shell_in_container repo_name branch_name =
  refresh_token ();
  let container_name = get_container_name repo_name branch_name in
  match get_container_status container_name with
  | Running ->
      let cmd = Printf.sprintf "docker exec -it -u dev -e HOME=/home/dev -e USER=dev -w /workspace %s bash -c '[ -f /home/dev/.wt-env ] && source /home/dev/.wt-env; exec bash'" container_name in
      Sys.command cmd
  | Stopped ->
      Printf.eprintf "Error: Container %s is not running. Start it first.\n" container_name;
      1
  | NotFound ->
      Printf.eprintf "Error: Container %s does not exist. Start it first.\n" container_name;
      1

(* Get status string for display *)
let status_string repo_name branch_name =
  let container_name = get_container_name repo_name branch_name in
  match get_container_status container_name with
  | Running -> Printf.sprintf "Container %s: running" container_name
  | Stopped -> Printf.sprintf "Container %s: stopped" container_name
  | NotFound -> Printf.sprintf "Container %s: not created" container_name

(* List all wt containers *)
let list_containers () =
  let cmd = "docker ps -a --filter 'name=^wt-' --format '{{.Names}}\t{{.Status}}'" in
  let output = Utils.run_command_output cmd in
  if output = "" then
    Printf.printf "No wt containers found.\n"
  else begin
    Printf.printf "wt containers:\n";
    String.split_on_char '\n' output
    |> List.iter (fun line ->
      if line <> "" then Printf.printf "  %s\n" line
    )
  end
