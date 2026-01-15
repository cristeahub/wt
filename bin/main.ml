(** wt - Git worktree management CLI tool *)

let version = "0.1.0"

let usage () =
  Printf.printf "wt - Git worktree management tool\n\n";
  Printf.printf "Usage:\n";
  Printf.printf "  wt b <branch_name>   Create branch and worktree, or navigate to existing\n";
  Printf.printf "  wt d <branch_name>   Delete worktree (keeps branch)\n";
  Printf.printf "  wt db <branch_name>  Delete both worktree and branch\n";
  Printf.printf "  wt list              List all worktrees\n";
  Printf.printf "\n";
  Printf.printf "Docker commands (run from within a worktree):\n";
  Printf.printf "  wt docker build      Build the base Docker image\n";
  Printf.printf "  wt docker start      Start container for current worktree\n";
  Printf.printf "  wt docker stop       Stop the container\n";
  Printf.printf "  wt docker shell      Open interactive shell in container\n";
  Printf.printf "  wt docker status     Show container status\n";
  Printf.printf "  wt docker rm         Remove the container\n";
  Printf.printf "  wt docker list       List all wt containers\n";
  Printf.printf "  wt run <cmd...>      Run command in container (e.g., wt run claude)\n";
  Printf.printf "  wt run claude [-y]   Run claude with optional --dangerously-skip-permissions\n";
  Printf.printf "  wt run claude [-t]   Run claude with agent teams enabled\n";
  Printf.printf "\n";
  Printf.printf "Authentication:\n";
  Printf.printf "  wt login             Configure Claude authentication token\n";
  Printf.printf "\n";
  Printf.printf "Worktrees are stored in ~/.local/share/wt/<repo>/<branch>\n";
  Printf.printf "Claude sessions are isolated per worktree in ~/.local/share/wt/sessions/\n";
  Printf.printf "\n";
  Printf.printf "Tip: Add this shell function to auto-cd into worktrees:\n";
  Printf.printf "  wtb() { local dir=$(wt b \"$1\" | tail -1); [ -d \"$dir\" ] && cd \"$dir\"; }\n";
  exit 0

(* Get current worktree context (repo_name, branch_name, worktree_path) *)
let get_worktree_context () =
  let cwd = Sys.getcwd () in
  let wt_base = Wt_lib.Utils.get_wt_base_dir () in
  (* Check if we're inside ~/.local/share/wt/<repo>/<branch> *)
  if String.length cwd > String.length wt_base &&
     String.sub cwd 0 (String.length wt_base) = wt_base then
    (* Extract repo and branch from path *)
    let rel_path = String.sub cwd (String.length wt_base + 1)
      (String.length cwd - String.length wt_base - 1) in
    match String.split_on_char '/' rel_path with
    | repo :: branch :: _ -> Some (repo, branch, Filename.concat (Filename.concat wt_base repo) branch)
    | _ -> None
  else
    None

(* Find the dockerfile directory *)
let get_dockerfile_dir () =
  (* Look for Dockerfile in the installed location or current directory *)
  let home = Sys.getenv "HOME" in
  let installed_docker_dir = Filename.concat
    (Filename.concat (Filename.concat home ".local") "share") "wt/docker" in
  if Sys.file_exists (Filename.concat installed_docker_dir "Dockerfile") then
    Some installed_docker_dir
  else
    (* Try relative to executable *)
    None

let docker_command subcmd =
  match subcmd with
  | "build" ->
      if not (Wt_lib.Docker.docker_available ()) then begin
        Printf.eprintf "Error: Docker is not available. Make sure Docker is installed and running.\n";
        exit 1
      end;
      (match get_dockerfile_dir () with
      | Some dir ->
          if not (Wt_lib.Docker.build_image dir) then exit 1
      | None ->
          Printf.eprintf "Error: Dockerfile not found.\n";
          Printf.eprintf "Run install.sh to set up the Docker image.\n";
          exit 1)
  | "start" ->
      (match get_worktree_context () with
      | Some (repo, branch, path) ->
          if not (Wt_lib.Docker.image_exists ()) then begin
            Printf.eprintf "Error: Docker image not found. Run 'wt docker build' first.\n";
            exit 1
          end;
          if not (Wt_lib.Docker.start_container repo branch path) then exit 1
      | None ->
          Printf.eprintf "Error: Not inside a wt worktree.\n";
          Printf.eprintf "Navigate to a worktree first (e.g., wtb <branch>)\n";
          exit 1)
  | "stop" ->
      (match get_worktree_context () with
      | Some (repo, branch, _) ->
          if not (Wt_lib.Docker.stop_container repo branch) then exit 1
      | None ->
          Printf.eprintf "Error: Not inside a wt worktree.\n";
          exit 1)
  | "shell" ->
      (match get_worktree_context () with
      | Some (repo, branch, _) ->
          let code = Wt_lib.Docker.shell_in_container repo branch in
          exit code
      | None ->
          Printf.eprintf "Error: Not inside a wt worktree.\n";
          exit 1)
  | "status" ->
      (match get_worktree_context () with
      | Some (repo, branch, _) ->
          Printf.printf "%s\n" (Wt_lib.Docker.status_string repo branch)
      | None ->
          Printf.eprintf "Error: Not inside a wt worktree.\n";
          exit 1)
  | "rm" ->
      (match get_worktree_context () with
      | Some (repo, branch, _) ->
          if not (Wt_lib.Docker.remove_container repo branch) then exit 1
      | None ->
          Printf.eprintf "Error: Not inside a wt worktree.\n";
          exit 1)
  | "list" ->
      Wt_lib.Docker.list_containers ()
  | _ ->
      Printf.eprintf "Error: Unknown docker subcommand '%s'\n" subcmd;
      Printf.eprintf "Run 'wt --help' for usage\n";
      exit 1

let run_command args =
  match get_worktree_context () with
  | Some (repo, branch, _) ->
      (* Handle -y and -t shorthands for claude *)
      let args = match args with
        | "claude" :: rest ->
            let has_skip_flag = List.exists (fun a -> a = "-y" || a = "--dangerously-skip-permissions") rest in
            let has_teams_flag = List.exists (fun a -> a = "-t") rest in
            let filtered = List.filter (fun a -> a <> "-y" && a <> "-t") rest in
            let claude_args = if has_skip_flag then "--dangerously-skip-permissions" :: filtered else filtered in
            let prefix = if has_teams_flag then "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 " else "" in
            [prefix ^ "claude" ^ (if claude_args = [] then "" else " " ^ String.concat " " claude_args)]
        | _ -> args
      in
      let cmd = String.concat " " args in
      let code = Wt_lib.Docker.exec_in_container repo branch cmd true in
      exit code
  | None ->
      Printf.eprintf "Error: Not inside a wt worktree.\n";
      Printf.eprintf "Navigate to a worktree first (e.g., wtb <branch>)\n";
      exit 1

let login_command () =
  Printf.printf "Claude Code Authentication Setup\n";
  Printf.printf "================================\n\n";
  (* Try auto-extracting from macOS Keychain first *)
  Printf.printf "Checking macOS Keychain for Claude Code credentials...\n%!";
  match Wt_lib.Docker.try_extract_keychain_token () with
  | Some token ->
      Wt_lib.Docker.save_token token;
      Printf.printf "Token extracted from Keychain and saved successfully!\n";
      Printf.printf "All new wt containers will have Claude authentication configured.\n";
      Printf.printf "Restart any running containers for the change to take effect.\n"
  | None ->
      Printf.printf "Could not extract token from Keychain.\n\n";
      Printf.printf "To authenticate manually:\n";
      Printf.printf "1. Run 'claude' on your host machine and complete authentication\n";
      Printf.printf "2. Run 'claude setup-token' to get your OAuth token\n";
      Printf.printf "3. Paste the token below\n\n";
      Printf.printf "Token: %!";
      let token = read_line () in
      let token = String.trim token in
      if token = "" then begin
        Printf.eprintf "Error: No token provided.\n";
        exit 1
      end;
      Wt_lib.Docker.save_token token;
      Printf.printf "\nToken saved successfully!\n";
      Printf.printf "All new wt containers will have Claude authentication configured.\n";
      Printf.printf "Restart any running containers for the change to take effect.\n"

let () =
  let args = Array.to_list Sys.argv |> List.tl in
  match args with
  | [] | ["-h"] | ["--help"] | ["help"] -> usage ()
  | ["-v"] | ["--version"] -> Printf.printf "wt %s\n" version
  | ["b"; branch_name] -> Wt_lib.Worktree.branch_command branch_name
  | ["d"; branch_name] -> Wt_lib.Worktree.delete_command branch_name
  | ["db"; branch_name] -> Wt_lib.Worktree.delete_both_command branch_name
  | ["list"] -> Wt_lib.Worktree.list_command ()
  | ["b"] ->
      Printf.eprintf "Error: Missing branch name\n";
      Printf.eprintf "Usage: wt b <branch_name>\n";
      exit 1
  | ["d"] ->
      Printf.eprintf "Error: Missing branch name\n";
      Printf.eprintf "Usage: wt d <branch_name>\n";
      exit 1
  | ["db"] ->
      Printf.eprintf "Error: Missing branch name\n";
      Printf.eprintf "Usage: wt db <branch_name>\n";
      exit 1
  | ["docker"; subcmd] -> docker_command subcmd
  | ["docker"] ->
      Printf.eprintf "Error: Missing docker subcommand\n";
      Printf.eprintf "Usage: wt docker <build|start|stop|shell|status|rm|list>\n";
      exit 1
  | "run" :: cmd_args when cmd_args <> [] -> run_command cmd_args
  | ["run"] ->
      Printf.eprintf "Error: Missing command to run\n";
      Printf.eprintf "Usage: wt run <command...>\n";
      exit 1
  | ["login"] -> login_command ()
  | cmd :: _ ->
      Printf.eprintf "Error: Unknown command '%s'\n" cmd;
      Printf.eprintf "Run 'wt --help' for usage\n";
      exit 1
