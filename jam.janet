(import ./posix-spawn/posix-spawn)
(import pat)
(use judge)
(use ./util)

(def prelude `
jam_error () {
  printf '%s %s [%s]\0' "$1" "$2" "$3" >&4
}
trap 'jam_error "$LINENO" "$?" "${PIPESTATUS[*]}"' ERR

`)

(def bash-options ["-o" "nounset" "-o" "pipefail"])

(def example1 `
echo hi
#? 0
#| hi
#! hello
#| bye
`)

(def example2 `
echo hi
echo hello
#| hi
#| hello
echo -n hi
echo -n hello
#| hihello
##
`)

(def parse-peg (peg/compile ~{
  :line (+
    (/ (* :s* :op '(to -1)) ,|[$0 $1])
    (/ (* '(to -1) (line)) ,|[:source ;$&]))
  :op (+
    (/ "#|" :stdout)
    (/ "#!" :stderr)
    (/ "##" :empty)
    (/ "#?" :status))
  :main (split "\n" :line)
}))

(test (peg/match parse-peg example1)
  @[[:source "echo hi" 1]
    [:status " 0"]
    [:stdout " hi"]
    [:stderr " hello"]
    [:stdout " bye"]])

(test (peg/match parse-peg example2)
  @[[:source "echo hi" 1]
    [:source "echo hello" 2]
    [:stdout " hi"]
    [:stdout " hello"]
    [:source "echo -n hi" 5]
    [:source "echo -n hello" 6]
    [:stdout " hihello"]
    [:empty ""]])

(defn parse-script [source]
  (def finished-states @[])
  (var state [:source @[]])

  (defn transition [new-state]
    (array/push finished-states state)
    (set state new-state))

  (each line (peg/match parse-peg source)
    (pat/match [(state 0) (line 0)]
      [:source :source] nil
      [:expectation :source] (transition [:source @[]])
      [:expectation _] nil
      [:source _] (transition [:expectation {:err @[] :out @[] :status (ref/new nil) :explicit true}]))

    (pat/match [line state]
      [[:source line line-number] [:source lines]]
        (array/push lines [line line-number])

      [[:stdout line] [:expectation {:out out}]] (array/push out line)
      [[:stderr line] [:expectation {:err err}]] (array/push err line)
      [[:status line] [:expectation {:status status}]] (ref/set status line)
      [[:empty line] [:expectation _]] nil
      ))
  (transition nil)
  finished-states
  )

(test (parse-script example1)
  @[[:source @[["echo hi" 1]]]
    [:expectation
     {:err @[" hello"]
      :out @[" hi" " bye"]
      :status @[" 0"]}]])

(test (parse-script example2)
  @[[:source
     @[["echo hi" 1] ["echo hello" 2]]]
    [:expectation
     {:err @[]
      :out @[" hi" " hello"]
      :status @[nil]}]
    [:source
     @[["echo -n hi" 5] ["echo -n hello" 6]]]
    [:expectation
     {:err @[]
      :out @[" hihello"]
      :status @[nil]}]])

# each expectation gets a unique identifier

(defn compile-script [source]
  (var next-id 0)
  (def stanzas (parse-script source))
  (array/push stanzas [:expectation {:err @[] :out @[] :status (ref/new nil) :explicit false}])

  (def expectations @{})

  (def lines
    (catseq [stanza :in stanzas]
      (pat/match stanza
        [:source lines] (map 0 lines)
        [:expectation expectation] (do
          (def id next-id)
          (++ next-id)
          (put expectations id expectation)
          [(string/format "printf '<done %d>'; printf '<done %d>' >&2" id id)]))))

  [expectations (string/join lines "\n")])

(test (compile-script example2)
  @["echo hi"
    "echo hello"
    "printf '--done--'; printf '--done--' >&2"
    "echo -n hi"
    "echo -n hello"
    "printf '--done--'; printf '--done--' >&2"])

(defn main [&]
  (def [source-reader source-writer] (posix-spawn/pipe :write-stream))
  (def [stdout-reader stdout-writer] (posix-spawn/pipe :read-stream))
  (def [stderr-reader stderr-writer] (posix-spawn/pipe :read-stream))
  (def [trace-reader trace-writer] (posix-spawn/pipe :read-stream))
  (def [debug-reader debug-writer] (posix-spawn/pipe :read-stream))

  (def env @{})

  (def bash-source (slurp "test.jam"))

  # I don't understand why I need to [:close source-writer].
  # Shouldn't CLOEXEC take care of that for me?
  (def proc
    (posix-spawn/spawn2 ["bash" ;bash-options "/dev/fd/6"]
    {:cmd "bash"
     :file-actions
       [[:close stdin] [:dup2 source-reader 6] [:close source-reader] [:close source-writer]
        [:close stdout] [:dup2 stdout-writer stdout] [:close stdout-writer] [:close stdout-reader]
        [:close stderr] [:dup2 stderr-writer stderr] [:close stderr-writer] [:close stderr-reader]
        [:dup2 trace-writer 4] [:close trace-writer] [:close trace-reader]
        [:dup2 debug-writer 5] [:close debug-writer] [:close debug-reader]]
      :env (table/proto-flatten (table/setproto env (os/environ)))
      }))
  (file/close source-reader)
  (file/close stdout-writer)
  (file/close stderr-writer)
  (file/close trace-writer)
  (file/close debug-writer)

  (ev/write source-writer prelude)
  (def [expectations compiled-source] (compile-script bash-source))
  (print compiled-source)
  (print "---")
  (ev/write source-writer compiled-source)
  # TODO: we need to print a terminator here
  (ev/close source-writer)

  (ev/spawn
    (while true
      (def chunk (ev/read debug-reader 1024))
      (unless chunk (break))
      (printf "debug: %s" chunk)))

  (def trace-buf @"")
  (def stdout-buf @"")
  (def stderr-buf @"")
  (ev/spawn (while (ev/read trace-reader 1024 trace-buf)))
  (ev/spawn (while (ev/read stdout-reader 1024 stdout-buf)))
  (ev/spawn (while (ev/read stderr-reader 1024 stderr-buf)))

  (while true
    (case (proc :exit-code)
      nil (ev/sleep 0.001)
      (do
        (print "process exited")
        (break))))

  (printf "exited %d" (proc :exit-code))
  (print "trace:")
  (pp trace-buf)
  (print "stdout:")
  (pp stdout-buf)
  (print "stderr:")
  (pp stderr-buf)
  )
