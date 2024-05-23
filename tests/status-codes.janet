(use judge)
(use ../src/util)
(import ../src :as steno)

(deftest "status codes appear after the error"
  (test-stdout (steno/reconcile "false") `
    false
    #? 1
  `))

(deftest "subshell failures can result in redundant trace errors"
  (test (->
    (steno/transcribe `
      (exit 1) | (exit 2)
      (exit 1) | (exit 1)
      `)
    (in :trace-buf)
    steno/parse-trace-output)
    @[@[1 0 @[1 2]]
      @[1 1 @[1 2]]
      @[2 2 @[1 1]]
      @[2 3 @[1 1]]]))

(deftest "failing statements get status expectations, even if they didn't exist"
  (test-stdout (steno/reconcile (unindent `
    false
    true
    `)) `
    false
    #? 1
    true
    
  `))

(deftest "status expectations can go at end of file"
  (test-stdout (steno/reconcile (unindent `
    false`)) `
    false
    #? 1
  `)
  (test-stdout (steno/reconcile (unindent `
    false
    `)) `
    false
    #? 1
    
  `))

(deftest "status expectations are erased if there is no error"
  (test-stdout (steno/reconcile (unindent `
    true
    #? 1`)) `
    true
    #-
  `))

(deftest "implicit status expectations still capture error"
  (test-stdout (steno/reconcile (unindent `
    echo stderr >&2
    echo stdout
    false
    echo fine`)) `
    echo stderr >&2
    echo stdout
    false
    #| stdout
    #! stderr
    #? 1
    echo fine
    #| fine
  `))
