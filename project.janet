(declare-project
  :name "steno"
  :description ""
  :dependencies
    [{:url "https://github.com/ianthehenry/janet-posix-spawn.git"}
     {:url "https://github.com/ianthehenry/judge.git"}
     {:url "https://github.com/ianthehenry/pat.git"}
     {:url "https://github.com/ianthehenry/cmd.git"}
     ])

(declare-executable
 :name "steno"
 :entry "src/init.janet")
