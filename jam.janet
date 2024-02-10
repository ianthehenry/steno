(import ./posix-spawn/posix-spawn)
(import pat)
(import cmd)
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
      :explicit true
      :out @[" hi" " bye"]
      :status @[" 0"]}]])

(test (parse-script example2)
  @[[:source
     @[["echo hi" 1] ["echo hello" 2]]]
    [:expectation
     {:err @[]
      :explicit true
      :out @[" hi" " hello"]
      :status @[nil]}]
    [:source
     @[["echo -n hi" 5] ["echo -n hello" 6]]]
    [:expectation
     {:err @[]
      :explicit true
      :out @[" hihello"]
      :status @[nil]}]])

# each expectation gets a unique identifier

(defn escape-bytes [bytes] (string/join (seq [byte :in bytes] (string/format "\\x%02x" byte))))

(test (escape-bytes "\x01\x02\x03") "\\x01\\x02\\x03")

(defn compile-script [source rng]
  (var next-id 0)
  (def stanzas (parse-script source))
  (array/push stanzas [:expectation {:err @[] :out @[] :status (ref/new nil) :explicit false}])

  (def random-bytes (math/rng-buffer rng 8))
  (def expectations @{})

  (def lines
    (catseq [stanza :in stanzas]
      (pat/match stanza
        [:source lines] (map 0 lines)
        [:expectation expectation] (do
          (def id (post++ next-id))
          (put expectations id expectation)
          (def tag (buffer/push-word (clone random-bytes) id))
          [(string/format "printf '%s'; printf '%s' >&2" (escape-bytes tag) (escape-bytes tag))]))))

  {:expectations expectations
   :script (string/join lines "\n")
   :separator (string random-bytes)})

(defn sanitize [{:expectations expectations :script script :separator separator}]
  (print (string/replace-all (escape-bytes separator) "<sep>" script))
  expectations)

(test-stdout (sanitize (compile-script example2 (math/rng))) `
  echo hi
  echo hello
  printf '<sep>\x00\x00\x00\x00'; printf '<sep>\x00\x00\x00\x00' >&2
  echo -n hi
  echo -n hello
  printf '<sep>\x01\x00\x00\x00'; printf '<sep>\x01\x00\x00\x00' >&2
  printf '<sep>\x02\x00\x00\x00'; printf '<sep>\x02\x00\x00\x00' >&2
`
  @{0 {:err @[]
       :explicit true
       :out @[" hi" " hello"]
       :status @[nil]}
    1 {:err @[]
       :explicit true
       :out @[" hihello"]
       :status @[nil]}
    2 {:err @[]
       :explicit false
       :out @[]
       :status @[nil]}})

(defn parse-actuals [separator output errput]
  (def results-peg (peg/compile ~(some (/ (* '(to ,separator) ,separator (uint 4)) ,|[$1 $0]))))
  (def results @{})
  (defn get-result [tag]
    (get-or-put results tag {:errs @[] :outs @[] :status (ref/new nil)}))

  (each [tag text] (peg/match results-peg output)
    (table/push (get-result tag) :outs text))

  (each [tag text] (peg/match results-peg errput)
    (table/push (get-result tag) :errs text))

  results)

(test (parse-actuals "<sep>" "
hi\n
hello\n
<sep>\x00\x00\x00\x00bye then\n
<sep>\x01\x00\x00\x00" "<sep>\x00\x00\x00\x00<sep>\x01\x00\x00\x00")
  @{0 {:errs @[""]
       :outs @["hi\nhello\n"]
       :status @[nil]}
    1 {:errs @[""]
       :outs @["bye then\n"]
       :status @[nil]}})

(defn await-exit [proc]
  (while (= nil (proc :exit-code))
    (ev/sleep 0.001)))

(cmd/main (cmd/fn [file :file]
  (def [source-reader source-writer] (posix-spawn/pipe :write-stream))
  (def [stdout-reader stdout-writer] (posix-spawn/pipe :read-stream))
  (def [stderr-reader stderr-writer] (posix-spawn/pipe :read-stream))
  (def [trace-reader trace-writer] (posix-spawn/pipe :read-stream))
  (def [debug-reader debug-writer] (posix-spawn/pipe :read-stream))

  (def bash-source (slurp file))

  # I don't understand why I need to [:close source-writer].
  # Shouldn't CLOEXEC take care of that for me?
  (def env @{
    "JAM_DEBUG_FD" "5"
    "JAM_TRACE" "eval BASH_XTRACEFD=$JAM_DEBUG_FD; set -x"
    "JAM_LOG" "eval echo >&$JAM_DEBUG_FD"
    })
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
  (def {:expectations expectations
        :script compiled-source
        :separator separator}
    (compile-script bash-source (math/rng (os/time))))
  (ev/write source-writer compiled-source)
  (ev/close source-writer)

  (def trace-buf @"")
  (def stdout-buf @"")
  (def stderr-buf @"")
  (ev/spawn (while (ev/read trace-reader 1024 trace-buf)))
  (ev/spawn (while (ev/read stdout-reader 1024 stdout-buf)))
  (ev/spawn (while (ev/read stderr-reader 1024 stderr-buf)))
  (ev/spawn (while-let [chunk (ev/read debug-reader 1024)] (eprin chunk)))

  (await-exit proc)

  (pp expectations)
  (pp (parse-actuals separator stdout-buf stderr-buf))

  # okay, now we parse the line failures and insert new expectations wherever necessary...
  # then we collapse adjacent expectations, i guess

  # afterwards, group all of the expectations by their ID
  # and error if we get inconsistent results for any expectation...
  # ...or if there's any expectation we fail to execute

  # then we produce the final output
  # ...and diff it against the original source
  # if there's any difference, we fail.
  ))
