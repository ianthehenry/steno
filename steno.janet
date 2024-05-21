(import posix-spawn)
(import pat)
(import cmd)
(use judge)
(use ./util)

# TODO: should probably make a printf version of steno_log.
# or maybe it should only be printf? not sure
(def prelude `
BASH_XTRACEFD=$STENO_DEBUG_FD
steno_error () {
  printf '%s %s\0' "$1" "$2" >&4
}
trap 'steno_error "$LINENO" "${PIPESTATUS[*]}"' ERR

steno_log () {
  echo >&$STENO_DEBUG_FD "$@"
}

`)

(def prelude-line-count (length (string/split "\n" prelude)))

(def bash-options ["-o" "nounset" "-o" "pipefail"])

(def parse-peg (peg/compile ~{
  :line (+
    (/ (* (/ ':s* ,length) :op '(to -1)) ,|[$1 $2 $0])
    (/ (* '(to -1) (line)) ,|[:source ;$&]))
  :op (+
    (/ "#|" :stdout)
    (/ "#!" :stderr)
    (/ "#-" :empty)
    (/ "#?" :status))
  :main (split "\n" :line)
}))

(test (peg/match parse-peg `
echo hi
#? 0
#| hi
#! hello
#| bye
`)
  @[[:source "echo hi" 1]
    [:status " 0" 0]
    [:stdout " hi" 0]
    [:stderr " hello" 0]
    [:stdout " bye" 0]])

(test (peg/match parse-peg `
echo hi
echo hello
#| hi
#| hello
echo -n hi
echo -n hello
#| hihello
#-
`)
  @[[:source "echo hi" 1]
    [:source "echo hello" 2]
    [:stdout " hi" 0]
    [:stdout " hello" 0]
    [:source "echo -n hi" 5]
    [:source "echo -n hello" 6]
    [:stdout " hihello" 0]
    [:empty "" 0]])

(defn expectation/new [&named explicit]
  @{:err @[] :out @[] :status (ref/new nil) :explicit explicit})

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
      [:source _]
        (transition [:expectation (expectation/new :explicit true)]))

    (pat/match [line state]
      [[:source line line-number] [:source lines]]
        (array/push lines [line line-number])
      [[:stdout line _] [:expectation {:out out}]] (array/push out line)
      [[:stderr line _] [:expectation {:err err}]] (array/push err line)
      [[:status line _] [:expectation {:status status}]] (ref/set status line)
      [[:empty line _] [:expectation _]] nil))
  (transition nil)
  finished-states)

(test (parse-script `
echo hi
#? 0
#| hi
#! hello
#| bye
`)
  @[[:source @[["echo hi" 1]]]
    [:expectation
     @{:err @[" hello"]
       :explicit true
       :out @[" hi" " bye"]
       :status @[" 0"]}]])

(test (parse-script `
echo hi
echo hello
#| hi
#| hello
echo -n hi
echo -n hello
#| hihello
#-
`)
  @[[:source
     @[["echo hi" 1] ["echo hello" 2]]]
    [:expectation
     @{:err @[]
       :explicit true
       :out @[" hi" " hello"]
       :status @[nil]}]
    [:source
     @[["echo -n hi" 5] ["echo -n hello" 6]]]
    [:expectation
     @{:err @[]
       :explicit true
       :out @[" hihello"]
       :status @[nil]}]])

# each expectation gets a unique identifier

(defn escape-bytes [bytes] (string/join (seq [byte :in bytes] (string/format "\\x%02x" byte))))

(test (escape-bytes "\x01\x02\x03") "\\x01\\x02\\x03")

(defn compile-script [source separator]
  (var next-id 0)
  (def stanzas (parse-script source))
  (array/push stanzas [:expectation (expectation/new :explicit false)])

  (def expectations @{})
  (def ordered @[])

  (def lines (catseq [stanza :in stanzas]
    (pat/match stanza
      [:source lines] (do
        # TODO: why am I parsing the original line?
        (def lines (map 0 lines))
        (array/concat ordered lines)
        lines)
      [:expectation expectation] (do
        (def id (post++ next-id))
        (put expectations id expectation)
        # TODO: is there some guarantee that push-word always pushes a 32-bit int?
        (def tag (buffer/push-word (buffer separator) id))
        (array/push ordered expectation)
        [(string/format "printf '%s'; printf '%s' >&2" (escape-bytes tag) (escape-bytes tag))]))))

  {:expectations expectations
   :ordered ordered
   :lines lines})

(deftest compile-script
  # the separator gets escaped, even if it's ascii, so I'm using something
  # recognizable in hex instead of something like <sep>
  (def {:ordered ordered :expectation expectation :lines lines} (compile-script `
echo hi
echo hello
#| hi
#| hello
echo -n hi
echo -n hello
#| hihello
#-
` "\xff"))
  (test expectation nil)
  (test-stdout (each line lines (print line)) `
    echo hi
    echo hello
    printf '\xff\x00\x00\x00\x00'; printf '\xff\x00\x00\x00\x00' >&2
    echo -n hi
    echo -n hello
    printf '\xff\x01\x00\x00\x00'; printf '\xff\x01\x00\x00\x00' >&2
    printf '\xff\x02\x00\x00\x00'; printf '\xff\x02\x00\x00\x00' >&2
  `)
  (test ordered
    @["echo hi"
      "echo hello"
      @{:err @[]
        :explicit true
        :out @[" hi" " hello"]
        :status @[nil]}
      "echo -n hi"
      "echo -n hello"
      @{:err @[]
        :explicit true
        :out @[" hihello"]
        :status @[nil]}
      @{:err @[]
        :explicit false
        :out @[]
        :status @[nil]}]))

(defn parse-actuals [separator output errput]
  (def results-peg (peg/compile ~(some (/ (* '(to ,separator) ,separator (uint 4)) ,|[$1 $0]))))
  (def results @{})
  (defn get-result [tag]
    (get-or-put results tag {:errs @[] :outs @[]}))
  (each [tag text] (peg/match results-peg output)
    (table/push (get-result tag) :outs text))
  (each [tag text] (peg/match results-peg errput)
    (table/push (get-result tag) :errs text))
  results)

(test (parse-actuals "<sep>" "
hi\n
hello\n
<sep>\x00\x00\x00\x00bye then\n
<sep>\x01\x00\x00\x00"
"<sep>\x00\x00\x00\x00<sep>\x01\x00\x00\x00")
  @{0 {:errs @[""] :outs @["hi\nhello\n"]}
    1 {:errs @[""] :outs @["bye then\n"]}})

# TODO: these line numbers are based on the compiled script,
# which has erased certain comments. It's not clear to me yet
# if I need actual source lines or not. Probably not?
# Definitely not?
(def trace-peg (peg/compile ~{
  :main (any (* (group :line) "\0"))
  :line (* :line-number " " (sub (to "\0") :pipe-status))
  :line-number (/ :int ,|(- $ prelude-line-count -1))
  :pipe-status (group (split " " :int))
  :int (number :d+)
  }))
(defn parse-trace-output [trace-output]
  (peg/match trace-peg trace-output))

(def trace-output-example @"15 1\022 1\022 1\027 1\027 1\030 1 2 0 3\030 1 2 0 3\031 0 1 2 0\0")
(test (parse-trace-output trace-output-example)
  @[@[6 @[1]]
    @[13 @[1]]
    @[13 @[1]]
    @[18 @[1]]
    @[18 @[1]]
    @[21 @[1 2 0 3]]
    @[21 @[1 2 0 3]]
    @[22 @[0 1 2 0]]])

(defn await-exit [proc]
  (while (= nil (proc :exit-code))
    (ev/sleep 0.001)))

(defn transcribe-raw [script &named on-debug]
  (default on-debug ignore)
  (def [source-reader source-writer] (posix-spawn/pipe :write-stream))
  (def [stdout-reader stdout-writer] (posix-spawn/pipe :read-stream))
  (def [stderr-reader stderr-writer] (posix-spawn/pipe :read-stream))
  (def [trace-reader trace-writer] (posix-spawn/pipe :read-stream))
  (def [debug-reader debug-writer] (posix-spawn/pipe :read-stream))

  # I don't understand why I need to [:close source-writer].
  # Shouldn't CLOEXEC take care of that for me?
  # steno_trace and steno_log should probably be functions
  (def env @{"STENO_DEBUG_FD" "5"})
  # TODO: should we filter what we inherit? what does cram do?
  (def inherit-env (os/environ))
  (table/setproto env inherit-env)
  (def proc
    (posix-spawn/spawn2 ["bash" ;bash-options "/dev/fd/6"]
    {:cmd "bash"
     :file-actions
       [[:close stdin] [:dup2 source-reader 6] [:close source-reader] [:close source-writer]
        [:close stdout] [:dup2 stdout-writer stdout] [:close stdout-writer] [:close stdout-reader]
        [:close stderr] [:dup2 stderr-writer stderr] [:close stderr-writer] [:close stderr-reader]
        [:dup2 trace-writer 4] [:close trace-writer] [:close trace-reader]
        [:dup2 debug-writer 5] [:close debug-writer] [:close debug-reader]]
     :env (table/proto-flatten env)
     }))
  (file/close source-reader)
  (file/close stdout-writer)
  (file/close stderr-writer)
  (file/close trace-writer)
  (file/close debug-writer)

  (def trace-buf @"")
  (def stdout-buf @"")
  (def stderr-buf @"")
  (ev/spawn (while (ev/read trace-reader 1024 trace-buf)))
  (ev/spawn (while (ev/read stdout-reader 1024 stdout-buf)))
  (ev/spawn (while (ev/read stderr-reader 1024 stderr-buf)))
  (ev/spawn (while-let [chunk (ev/read debug-reader 1024)] (on-debug chunk)))

  # we don't write this until after we've started reading
  # to avoid a deadlock where a huge write doesn't complete
  # because bash blocks in the first chunk waiting for us
  # to read
  (ev/write source-writer prelude)
  (ev/write source-writer script)
  (ev/close source-writer)

  (await-exit proc)

  {:stdout-buf stdout-buf
   :stderr-buf stderr-buf
   :trace-buf trace-buf})

# okay, now we parse the line failures and insert new expectations wherever necessary...
# then we collapse adjacent expectations, i guess

# afterwards, group all of the expectations by their ID
# and error if we get inconsistent results for any expectation...
# ...or if there's any expectation we fail to execute

# then we produce the final output
# ...and diff it against the original source
# if there's any difference, we fail.

(def rng (lazy (math/rng (os/time))))

(defn make-separator [] (string (math/rng-buffer (rng) 8)))

(defn transcribe [source &named on-debug]
  (def separator (make-separator))
  (def {:expectations expectations
        :ordered ordered
        :lines compiled-script-lines}
    (compile-script source separator))

  (def {:stdout-buf stdout-buf
        :stderr-buf stderr-buf
        :trace-buf trace-buf}
    (transcribe-raw (string/join compiled-script-lines "\n") :on-debug on-debug))
  {:expectations expectations
   :actual (parse-actuals separator stdout-buf stderr-buf)
   :traced (parse-trace-output trace-buf)})

# oh shoot, i need to know the level
# of indentation of the preceding line
# or of the lines we're correcting or something
(defn print-lines-prefixed [prefix str]
  (def lines (string/split "\n" str))
  (defn last? [i]
    (= i (dec (length lines))))
  (seq [[i line] :pairs lines
        :unless (and (empty? line) (last? i))]
    (prin prefix)
    (unless (empty? line)
      (prin " "))
    (print line)))

(defn render [ordered]
  (var last-source-line "")
  (each entry ordered
    (cond
      (string? entry) (do
        (set last-source-line entry)
        (print entry))
      (let [{:actual-err err :actual-out out :explicit explicit} entry]
        (def indentation (string/repeat " " (get-indentation last-source-line)))
        (unless (empty? out)
          (print-lines-prefixed (string indentation "#|") out))
        (unless (empty? err)
          (print-lines-prefixed "#!" err))
        # TODO: also status
        (when (and explicit (empty? out) (empty? err))
          (print "#-"))
        ))))

(defn reconcile [source &named on-debug]
  (def separator (make-separator))
  (def {:expectations expectations
        :ordered ordered
        :lines compiled-script-lines}
    (compile-script source separator))

  (def {:stdout-buf stdout-buf
        :stderr-buf stderr-buf
        :trace-buf trace-buf}
    (transcribe-raw (string/join compiled-script-lines "\n") :on-debug on-debug))

  (def actual (parse-actuals separator stdout-buf stderr-buf))
  (def traced (parse-trace-output trace-buf))

  # do i actually even need to parse the "expecteds"? of course i do if i want to make, like,
  # my own interactive differ or whatever... but if i just shell out to cmp, do i need that
  # at all?
  (eachp [id {:errs errs :outs outs}] actual
    (def expectation (assert (in expectations id) "unknown expectation ID"))
    # TODO: this should really fail with a better error message
    (put expectation :actual-out (unique outs))
    (put expectation :actual-err (unique errs)))

  (render ordered)
  #ordered
  )

(cmd/main (cmd/fn [file :file]
  (pp (transcribe (slurp file) :on-debug eprin))))
