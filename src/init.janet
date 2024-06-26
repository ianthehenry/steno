(import posix-spawn)
(import pat)
(import cmd)
(use judge)
(use cmp/import)
(use ./util)

# TODO: should probably make a printf version of steno_log.
# or maybe it should only be printf? not sure
(def prelude `
BASH_XTRACEFD=$STENO_DEBUG_FD
steno_error_index=$STENO_NEXPECTATION_ID
_steno_i32_le () {
  printf "%.8x" "$1" | xxd -p -r | rev | tr -d '\n'
}
_steno_error () {
  printf "%s" "$STENO_SEPARATOR_HEX" | xxd -p -r | tee /dev/stderr
  _steno_i32_le "$steno_error_index" | tee /dev/stderr
  printf '%s %s %s\0' "$1" "$steno_error_index" "$2" >&$STENO_TRACE_FD
  steno_error_index=$((steno_error_index + 1))
}
trap '_steno_error "$LINENO" "${PIPESTATUS[*]}"' ERR

steno_log () {
  echo >&$STENO_DEBUG_FD "$@"
}

`)
(def postlude "\nwait")

(def prelude-line-count (length (string/split "\n" prelude)))

(def bash-options ["-o" "nounset" "-o" "pipefail"])

(def parse-peg (peg/compile ~{
  :line (+
    (/ (* (/ ':s* ,length) :op (? " ") '(to -1)) ,|[$1 $2 $0])
    (/ (* '(to -1) (line)) ,|[:source ;$&]))
  :op (+
    (/ "#|" :stdout)
    (/ "#!" :stderr)
    (/ "#-" :empty)
    (/ "#?" :status)
    (/ "#\\" :no-eol))
  :main (split "\n" :line)
}))

(test (peg/match parse-peg `
echo hi
#? 0
#| hi
#! hello
#| bye
#\ bye
`)
  @[[:source "echo hi" 1]
    [:status "0" 0]
    [:stdout "hi" 0]
    [:stderr "hello" 0]
    [:stdout "bye" 0]
    [:no-eol "bye" 0]])

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
    [:stdout "hi" 0]
    [:stdout "hello" 0]
    [:source "echo -n hi" 5]
    [:source "echo -n hello" 6]
    [:stdout "hihello" 0]
    [:empty "" 0]])

(defn expectation/new []
  @{:err @[] :out @[] :eol? @{:out true :err true} :status (ref/new nil)})

# mutates lines!
(defn- join-lines! [lines eol?]
  (if eol? (array/push lines ""))
  (string/join lines "\n"))

(defn expectation/finalize [t]
  (def {:out out :err err :eol? {:out out-eol? :err err-eol?} :status status} t)
  @{:out (join-lines! out out-eol?)
    :err (join-lines! err err-eol?)
    :status (ref/get status)
    :explicit true})

(defn expectation/implicit []
  @{:out "" :err "" :status nil :explicit false})

(defn parse-script [source]
  (def finished-states @[])
  (var state [:source @[]])

  (defn transition [new-state]
    (array/push finished-states state)
    (set state new-state))

  (def no-eol-applies-to @{})

  (each line (peg/match parse-peg source)
    (pat/match [(state 0) (line 0)]
      [:source :source] nil
      [:expectation :source] (transition [:source @[]])
      [:expectation _] nil
      [:source _] (transition [:expectation (expectation/new)]))

    (pat/match [line state]
      [[:source line line-number] [:source lines]]
        (array/push lines [line line-number])
      [[:stdout line _] [:expectation expectation]] (do
        (table/push expectation :out line)
        (put no-eol-applies-to expectation :out))
      [[:stderr line _] [:expectation expectation]] (do
        (table/push expectation :err line)
        (put no-eol-applies-to expectation :err))
      [[:status line _] [:expectation expectation]] (do
        # TODO: fail on multiple statuses?
        (ref/set (in expectation :status) line)
        (put no-eol-applies-to expectation nil))
      [[:no-eol _ _] [:expectation expectation]] (do
        # TODO: fail if you have multiple of these? or if they
        # don't occur at the end of the block?
        (put (in expectation :eol?) (in no-eol-applies-to expectation) false)
        (put no-eol-applies-to expectation nil))
      [[:empty line _] [:expectation expectation]] (put no-eol-applies-to expectation nil)))
  (transition nil)

  (seq [state :in finished-states]
    (match state
      [:source _] state
      [:expectation expectation]
        [:expectation (expectation/finalize expectation)])))

(test (parse-script `
echo hi
#| hi
#\
`)
  @[[:source @[["echo hi" 1]]]
    [:expectation
     @{:err "" :explicit true :out "hi"}]])

(test (parse-script `
echo hi
#! hi
#\
`)
  @[[:source @[["echo hi" 1]]]
    [:expectation
     @{:err "hi" :explicit true :out ""}]])

(test (parse-script `
echo hi
#? 0
#| hi
#! hello
#| bye
`)
  @[[:source @[["echo hi" 1]]]
    [:expectation
     @{:err "hello\n"
       :explicit true
       :out "hi\nbye\n"
       :status "0"}]])

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
     @{:err ""
       :explicit true
       :out "hi\nhello\n"}]
    [:source
     @[["echo -n hi" 5] ["echo -n hello" 6]]]
    [:expectation
     @{:err ""
       :explicit true
       :out "hihello\n"}]])

# each expectation gets a unique identifier

(defn to-hex [bytes] (string/join (seq [byte :in bytes] (string/format "%02x" byte))))
(defn escape-bytes [bytes] (string/join (seq [byte :in bytes] (string/format "\\x%02x" byte))))

(test (to-hex "\x01\x02\x03") "010203")
(test (escape-bytes "\x01\x02\x03") "\\x01\\x02\\x03")

(defn empty-line? [line]
  (string/check-set " \t" line))
(test (empty-line? "") true)
(test (empty-line? "   ") true)
(test (empty-line? "  \t ") true)
(test (empty-line? "  \t x") false)

(defn add-implicit-final-expectation! [stanzas]
  (match (array/peek stanzas)
    nil  (array/push stanzas [:expectation (expectation/implicit)])
    [:source lines] (do
      (def index-of-empty-suffix (inc (or (find-last-index |(not (empty-line? (first $))) lines) -1)))
      (def non-empty-lines (tuple/slice lines 0 index-of-empty-suffix))
      (def empty-lines (tuple/slice lines index-of-empty-suffix))
      (array/pop stanzas)
      (unless (empty? non-empty-lines)
        (array/push stanzas [:source non-empty-lines]))
      (array/push stanzas [:expectation (expectation/implicit)])
      (unless (empty? empty-lines)
        (array/push stanzas [:source empty-lines])))
  ))

(deftest add-implicit-final-expectation
  (def stanzas @[])
  (add-implicit-final-expectation! stanzas)
  (test stanzas
    @[[:expectation
       @{:err "" :explicit false :out ""}]])

  (def stanzas @[[:source [["echo hi" 1]]]])
  (add-implicit-final-expectation! stanzas)
  (test stanzas
    @[[:source [["echo hi" 1]]]
      [:expectation
       @{:err "" :explicit false :out ""}]])

  (def stanzas @[[:source [["echo hi" 1] ["" 2]]]])
  (add-implicit-final-expectation! stanzas)
  (test stanzas
    @[[:source [["echo hi" 1]]]
      [:expectation
       @{:err "" :explicit false :out ""}]
      [:source [["" 2]]]])

  (def stanzas @[[:source [["echo hi" 1] ["  " 2] ["" 3]]]])
  (add-implicit-final-expectation! stanzas)
  (test stanzas
    @[[:source [["echo hi" 1]]]
      [:expectation
       @{:err "" :explicit false :out ""}]
      [:source [["  " 2] ["" 3]]]]))

(defn compile-script [source separator]
  (var next-id 0)
  (def stanzas (parse-script source))

  (add-implicit-final-expectation! stanzas)
  (def expectations @{})
  (def ordered @[])

  (def lines (catseq [stanza :in stanzas]
    (pat/match stanza
      [:source lines] (do
        # TODO: why am I parsing the original line number?
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
  `)
  (test ordered
    @["echo hi"
      "echo hello"
      @{:err ""
        :explicit true
        :out "hi\nhello\n"}
      "echo -n hi"
      "echo -n hello"
      @{:err ""
        :explicit true
        :out "hihello\n"}]))

# there is definitely always at least one expectation,
# but the output might not contain it, if the script
# exits early. so we can't always associate residue
# with an expectation ID.
(defn parse-actuals [separator output errput]
  (def results-peg (peg/compile ~{
    :main (* :properly-tagged :residue)
    :properly-tagged (any (/ (* '(to ,separator) ,separator (uint 4)) ,|[$1 $0]))
    :residue (+ -1 (/ '(to -1) ,|[:residue $0]))}))
  (def results @{})
  (defn get-result [id]
    (get-or-put results id {:errs @[] :outs @[]}))
  # We basically want a table that remembers the insertion order of its keys.
  # Might be neater if we just made a helper module for that.
  (def ids @[])
  (def ids-seen @{})
  (def outs (peg/match results-peg output))
  (def errs (peg/match results-peg errput))
  (each [id _] outs (unless (in ids-seen id) (put ids-seen id true) (array/push ids id)))
  # I don't think you should ever see an ID on stderr without first
  # seeing it on stdout, but just in case...
  (each [id _] errs (unless (in ids-seen id) (put ids-seen id true) (array/push ids id)))
  (each [id text] outs (table/push (get-result id) :outs text))
  (each [id text] errs (table/push (get-result id) :errs text))
  [ids results])

(test (parse-actuals "<sep>" (unindent "
  hi\n
  hello\n
  <sep>\x00\x00\x00\x00bye then\n
  <sep>\x01\x00\x00\x00")
  "<sep>\x00\x00\x00\x00<sep>\x01\x00\x00\x00")
  [@[0 1]
   @{0 {:errs @[""] :outs @["hi\nhello\n"]}
     1 {:errs @[""] :outs @["bye then\n"]}}])

(deftest "parse-actuals includes trailing output in the final expectation"
  (test (parse-actuals "<sep>" (unindent "
    hi\n
    hello\n
    <sep>\x00\x00\x00\x00bye then\n
    <sep>\x01\x00\x00\x00excess\n
    words")
  "<sep>\x00\x00\x00\x00<sep>\x01\x00\x00\x00trailing")
    [@[0 1 :residue]
     @{0 {:errs @[""] :outs @["hi\nhello\n"]}
       1 {:errs @[""] :outs @["bye then\n"]}
       :residue {:errs @["trailing"]
                 :outs @["excess\nwords"]}}]))

# TODO: these line numbers are based on the compiled script,
# which has erased certain comments. It's not clear to me yet
# if I need actual source lines or not. Probably not?
# Definitely not?
(def trace-peg (peg/compile ~{
  :main (any (* (group :line) "\0"))
  :line (* :line-number " " :id " " (sub (to "\0") :pipe-status))
  :line-number (/ :int ,|(- $ prelude-line-count -1))
  :id :int
  :pipe-status (group (split " " :int))
  :int (number :d+)
  }))
(defn parse-trace-output [trace-output]
  (peg/match trace-peg trace-output))

(def trace-output-example @"15 10 1\022 11 1\030 12 1 2 0 3\030 13 1 2 0 3\0")
(test (parse-trace-output trace-output-example)
  @[@[-1 10 @[1]]
    @[6 11 @[1]]
    @[14 12 @[1 2 0 3]]
    @[14 13 @[1 2 0 3]]])

(defn await-exit [proc]
  (while (= nil (proc :exit-code))
    (ev/sleep 0.001)))

(defn transcribe [script &named on-debug separator next-id]
  (default on-debug ignore)
  (default next-id 0)
  (default separator "")
  (def [source-reader source-writer] (posix-spawn/pipe :write-stream))
  (def [stdout-reader stdout-writer] (posix-spawn/pipe :read-stream))
  (def [stderr-reader stderr-writer] (posix-spawn/pipe :read-stream))
  (def [trace-reader trace-writer] (posix-spawn/pipe :read-stream))
  (def [debug-reader debug-writer] (posix-spawn/pipe :read-stream))

  (def source-fd (posix-spawn/fd source-reader))
  (def trace-fd (posix-spawn/fd trace-writer))
  (def debug-fd (posix-spawn/fd debug-writer))

  # TODO: we could just dynamically generate the prelude
  # instead of passing these as environment variables...
  # make them uninheritable, and it'll let us delete (to-hex)
  (def env @{"STENO_DEBUG_FD" (string debug-fd)
             "STENO_TRACE_FD" (string trace-fd)
             "STENO_NEXPECTATION_ID" (string next-id)
             "STENO_SEPARATOR_HEX" (to-hex separator)})

  # TODO: should we filter what we inherit? what does cram do?
  (def inherit-env (os/environ))
  (table/setproto env inherit-env)
  (def proc (posix-spawn/spawn2 ["bash" ;bash-options (string "/dev/fd/" source-fd)]
    {:cmd "bash"
     :file-actions
       [[:close stdin]
        [:close stdout] [:dup2 stdout-writer stdout] [:close stdout-writer]
        [:close stderr] [:dup2 stderr-writer stderr] [:close stderr-writer]]
     :env (table/proto-flatten env)
     }))

  (posix-spawn/close-fd source-reader)
  (posix-spawn/close-fd stdout-writer)
  (posix-spawn/close-fd stderr-writer)
  (posix-spawn/close-fd trace-writer)
  (posix-spawn/close-fd debug-writer)

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
  (ev/write source-writer postlude)
  (ev/close source-writer)

  (await-exit proc)

  {:stdout-buf stdout-buf
   :stderr-buf stderr-buf
   :trace-buf trace-buf})

(def rng (lazy (math/rng (os/time))))

(defn make-separator [] (string (math/rng-buffer (rng) 8)))

(defn xprint-lines-prefixed [to indentation prefix str]
  (def lines (string/split "\n" str))
  (defn last? [i]
    (= i (dec (length lines))))
  (loop [[i line] :pairs lines
        :unless (and (empty? line) (last? i))]
    (xprint to indentation prefix (if (empty? line) "" " ") line))

  (when (and (not (empty? lines)) (not (empty? (last lines))))
    (xprint to indentation "#\\")))

(defn render [ordered buf]
  (var last-source-line "")
  (each entry ordered
    (cond
      (string? entry) (do
        (unless (empty-line? entry)
          (set last-source-line entry))
        (xprint buf entry))
      # if you never encountered this expectation, actual-{out,err} will be nil
      (let [{:actual-err err :actual-out out :actual-status status :explicit explicit} entry]
        (def indentation (string/repeat " " (get-indentation last-source-line)))
        (def out? (not (or (nil? out) (empty? out))))
        (def err? (not (or (nil? err) (empty? err))))
        (def status? (not (nil? status)))
        (when out?
          (xprint-lines-prefixed buf indentation "#|" out))
        (when err?
          (xprint-lines-prefixed buf indentation "#!" err))
        (when status?
          (xprint buf indentation "#? " (string/join (map string status) " ")))
        (when (and explicit (not (or out? err? status?)))
          (xprint buf indentation "#-"))
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
    (transcribe (string/join compiled-script-lines "\n")
      :on-debug on-debug
      :separator separator
      :next-id (inc (max-of (keys expectations)))))

  (def [actual-ids actual] (parse-actuals separator stdout-buf stderr-buf))
  (def traced (parse-trace-output trace-buf))

  (def final-expectation (assert (find-last |(not (string? $)) ordered) "BUG: script with no expectation"))

  # TODO: we should check for duplicate expectations now,
  # and remove the new-expectation de-duping stuff. this way
  # we can report the statuses in the order they happened, instead of
  # after the (unstable!) cmp/sort below

  # we'll treat this like a stack, so we put it in reverse order
  (cmp/sort traced (by 0 desc))

  (def new-ordered @[])
  (eachp [i element] ordered
    (var new-expectation nil)
    (pop-while traced |(= i (first $)) [_ id status]
      (put expectations id
        (pat/match element
          |string? (or new-expectation
            (do
              (def expectation (expectation/implicit))
              (set new-expectation expectation)
              (put expectation :actual-status status)
              (array/push new-ordered expectation)
              expectation))
          expectation (do
            (put expectation :actual-status status)
            expectation))))
    (array/push new-ordered element))

  # so now there's a weird issue where, basically,
  # multiple IDs point to the same actual expectation.
  # so this tells us output by ID, but really we want
  # to ensure uniqueness by expectation.
  (loop [id :in actual-ids :let [{:outs outs :errs errs} (in actual id)]]
    (def expectation (if (= id :residue)
      final-expectation
      (assert (in expectations id) (string/format "BUG: unknown expectation ID %d" id))))

    # we can have multiple IDs pointing to the same expectation, in the case of
    # errors or residue. if we encounter from multiple sources, it's not exactly
    # a conflicting report, but rather a case of "and also here's this." So we
    # append the output on. But... this is actually kind of terrible, because of
    # the iteration order.

    # TODO: uniqueness failure should fail with a better error message
    (table/append-str expectation :actual-out (unique outs))
    (table/append-str expectation :actual-err (unique errs)))

  (def buf @"")
  (render new-ordered buf)
  (prin buf))

(cmd/main (cmd/fn [file :file]
  (reconcile (slurp file) :on-debug eprin)))
