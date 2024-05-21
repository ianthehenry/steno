(use judge)
(use ../src/util)
(import ../src :as steno)

(deftest "transcribe-raw"
  (test (steno/transcribe-raw "echo stdout; echo stderr >&2; false")
    {:stderr-buf @"stderr\n"
     :stdout-buf @"stdout\n"
     :trace-buf @"10 1\0"}))

(deftest "transcribe-raw redirects stdout properly"
  (test (steno/transcribe-raw "echo stdout >/dev/stdout")
    {:stderr-buf @""
     :stdout-buf @"stdout\n"
     :trace-buf @""}))

(deftest "transcribe-raw can read null bytes correctly"
  (test (steno/transcribe-raw "printf '\\0\\0\\0'")
    {:stderr-buf @""
     :stdout-buf @"\0\0\0"
     :trace-buf @""}))

(deftest "no deadlock on a giant write that has a giant read"
  # we shouldn't really hardcode this; if we're underestimating
  # the buffer size then this test would succeed without actually
  # testing anything
  (def pipe-buffer-size (* 16 4096))
  (def too-big (+ 1 pipe-buffer-size))
  (def script (buffer/new-filled too-big (chr "\n")))
  (buffer/blit script (string "dd if=/dev/zero bs="too-big" count=1 status=none") 0)

  (def {:stderr-buf stderr-buf
        :stdout-buf stdout-buf
        :trace-buf trace-buf}
        (steno/transcribe-raw script))

  (test (length stdout-buf) 65537))

(deftest "trivial transcription"
  (test (steno/transcribe "echo hello")
    {:actual @{0 {:errs @[""] :outs @["hello\n"]}}
     :expectations @{0 @{:err @[]
                         :explicit false
                         :out @[]
                         :status @[nil]}}
     :traced @[]}))

(deftest "error reports"
  (test (steno/transcribe `
    true
    false
    `)
    {:actual @{0 {:errs @[""] :outs @[""]}}
     :expectations @{0 @{:err @[]
                         :explicit false
                         :out @[]
                         :status @[nil]}}
     :traced @[@[2 @[1]]]}))

(deftest "trace line numbers do not match source line numbers"
  (test (steno/transcribe `
    true
    #| this will interfere
    #|
    #|
    #|
    false
    `)
    {:actual @{0 {:errs @[""] :outs @[""]}
               1 {:errs @[""] :outs @[""]}}
     :expectations @{0 @{:err @[]
                         :explicit true
                         :out @[" this will interfere" "" "" ""]
                         :status @[nil]}
                     1 @{:err @[]
                         :explicit false
                         :out @[]
                         :status @[nil]}}
     :traced @[@[3 @[1]]]}))

(deftest "pipes split across multiple times report status as the final line"
  (test (steno/transcribe `
    true | \
    false
    `)
    {:actual @{0 {:errs @[""] :outs @[""]}}
     :expectations @{0 @{:err @[]
                         :explicit false
                         :out @[]
                         :status @[nil]}}
     :traced @[@[2 @[0 1]]]})
  (test (steno/transcribe `
    false | \
    false | \
    false | \
    false | \
    false`)
    {:actual @{0 {:errs @[""] :outs @[""]}}
     :expectations @{0 @{:err @[]
                         :explicit false
                         :out @[]
                         :status @[nil]}}
     :traced @[@[5 @[1 1 1 1 1]]]}))

(deftest "steno_log does not show up in error output"
  (def debugs @[])
  (test (steno/transcribe `steno_log hello` :on-debug |(array/push debugs $))
    {:actual @{0 {:errs @[""] :outs @[""]}}
     :expectations @{0 @{:err @[]
                         :explicit false
                         :out @[]
                         :status @[nil]}}
     :traced @[]})
  (test debugs @[@"hello\n"]))

(deftest "if a pipeline fails, succeeds, then fails, it will report multiple failures"
  (test (steno/transcribe `
    true | false | true | \
    false | true | false
    `)
    {:actual @{0 {:errs @[""] :outs @[""]}}
     :expectations @{0 @{:err @[]
                         :explicit false
                         :out @[]
                         :status @[nil]}}
     :traced @[@[2 @[0 1 0 1 0 1]]]}))

(deftest "subshell failures can result in redundant trace errors"
  (test (steno/transcribe `
    (exit 1) | (exit 2)
    (exit 1) | (exit 1)
    `)
    {:actual @{0 {:errs @[""] :outs @[""]}}
     :expectations @{0 @{:err @[]
                         :explicit false
                         :out @[]
                         :status @[nil]}}
     :traced @[@[1 @[1 2]]
               @[1 @[1 2]]
               @[2 @[1 1]]
               @[2 @[1 1]]]}))

(deftest "output always ends with an implicit expectation"
  (test (steno/transcribe `
    echo hello
    `)
    {:actual @{0 {:errs @[""] :outs @["hello\n"]}}
     :expectations @{0 @{:err @[]
                         :explicit false
                         :out @[]
                         :status @[nil]}}
     :traced @[]}))

(defn unindent [str]
  (def indentation (get-indentation str))
  (string/join (seq [line :in (string/split "\n" str)]
    (string/slice line indentation)) "\n"))

(deftest "basic correction"
  (test-stdout (steno/reconcile (unindent `
    echo hello
    #| goodbye`)) `
    echo hello
    #| hello
  `))

(deftest "uncaptured output is captured at the end"
  (test-stdout (steno/reconcile (unindent `
    echo one
    #| foo
    echo two`)) `
    echo one
    #| one
    echo two
    #| two
  `))

(deftest "explicit expectations still appear even with no output"
  (test-stdout (steno/reconcile (unindent `
    true
    #| foo
    true`)) `
    true
    #-
    true
  `))

(deftest "output indentation matches the indentation of the previous source line"
  (test-stdout (steno/reconcile (unindent `
    echo hi
      #| foo
      echo hi
    #| foo`)) `
    echo hi
    #| hi
      echo hi
      #| hi
  `))

# TODO: this is obviously goofy
(deftest "newline between source and implicit final expectation when source ends in a newline"
  (test-stdout (steno/reconcile (unindent `
    echo hi
    `)) `
    echo hi

    #| hi
  `))

# TODO: need some tests for outputs in loops... i think it's okay
# to just say, yeah, you can see the same expectation multiple
# times? maybe? or maybe we always take the last one. i'm not sure.
