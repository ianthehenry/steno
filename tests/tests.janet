(use judge)
(use ../src/util)
(import ../src :as steno)

(deftest "trivial transcription"
  (test (steno/transcribe "echo hello")
    {:actual @{0 {:errs @[""] :outs @["hello\n"]}}
     :expectations @{0 @{:err @[]
                         :explicit false
                         :out @[]
                         :status @[nil]}}
     :traced @[]}))

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
