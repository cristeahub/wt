let version = "0.1.0"

let usage () =
  Printf.printf "wt - Git worktree management tool\n\n";
  Printf.printf "Usage:\n";
  Printf.printf "  wt b <branch_name>   Create branch and worktree, or navigate to existing\n";
  Printf.printf "  wt d <branch_name>   Delete worktree (keeps branch)\n";
  Printf.printf "  wt db <branch_name>  Delete both worktree and branch\n";
  Printf.printf "  wt repo <name>       Print absolute path of a repo (substring match)\n";
  Printf.printf "  wt list              List all worktrees\n";
  Printf.printf "\n";
  Printf.printf "Worktrees are stored in ~/.local/share/wt/<repo>/<branch>\n";
  Printf.printf "\n";
  Printf.printf "File copying:\n";
  Printf.printf "  Create a .wtfiles in your repo root listing untracked files to copy\n";
  Printf.printf "  into new worktrees (one path per line, # comments supported).\n";
  Printf.printf "\n";
  Printf.printf "Tip: Add this shell function to auto-cd into worktrees:\n";
  Printf.printf "  wtb() { local dir=$(wt b \"$1\" | tail -1); [ -d \"$dir\" ] && cd \"$dir\"; }\n";
  exit 0

let () =
  let args = Array.to_list Sys.argv |> List.tl in
  match args with
  | [] | ["-h"] | ["--help"] | ["help"] -> usage ()
  | ["-v"] | ["--version"] -> Printf.printf "wt %s\n" version
  | ["b"; branch_name] -> Wt_lib.Worktree.branch_command branch_name
  | ["d"; branch_name] -> Wt_lib.Worktree.delete_command branch_name
  | ["db"; branch_name] -> Wt_lib.Worktree.delete_both_command branch_name
  | ["repo"; name] -> Wt_lib.Worktree.repo_command name
  | ["repo"] ->
      Printf.eprintf "Error: Missing repo name\n";
      Printf.eprintf "Usage: wt repo <name>\n";
      exit 1
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
  | cmd :: _ ->
      Printf.eprintf "Error: Unknown command '%s'\n" cmd;
      Printf.eprintf "Run 'wt --help' for usage\n";
      exit 1
