(lang dune 3.0)
(name wt)
(version 0.1.0)

(generate_opam_files true)

(maintainers "Christoffer Tønnessen <christoffer@cto.gg>")
(authors "Christoffer Tønnessen <christoffer@cto.gg>")
(homepage "https://github.com/cristeahub/wt")
(bug_reports "https://github.com/cristeahub/wt/issues")
(source (github cristeahub/wt))
(license MIT)

(package
 (name wt)
 (synopsis "Git worktree management CLI tool")
 (description "A CLI tool for managing git worktrees and branches")
 (depends
  (ocaml (>= 5.1.0))
  dune))
