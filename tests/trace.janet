(use judge)
(use ../src/util)
(import ../src :as steno)

(defn get-trace [script]
  (def {:lines lines} (steno/compile-script (unindent script) (steno/make-separator)))
  (-> lines
    (string/join "\n")
    steno/transcribe
    (in :trace-buf)
    steno/parse-trace-output))

(deftest "error reports"
  (test (get-trace `
    true
    false
    `)
    @[@[2 0 @[1]]]))

(deftest "no error reports for async jobs"
  (test (get-trace `
    true &
    false &
    `)
    @[]))

(deftest "trace line numbers do not match source line numbers"
  (test (get-trace `
    true
    #| this will interfere
    #|
    #|
    #|
    false
    `)
    @[@[3 0 @[1]]]))

(deftest "pipes split across multiple times report status as the final line"
  (test (get-trace `
    true | \
    false
    `)
    @[@[2 0 @[0 1]]])
  (test (get-trace `
    false | \
    false | \
    false | \
    false | \
    false`)
    @[@[5 0 @[1 1 1 1 1]]]))

(deftest "if a pipeline fails, succeeds, then fails, it will report multiple failures"
  (test (get-trace `
    true | false | true | \
    false | true | false
    `)
    @[@[2 0 @[0 1 0 1 0 1]]]))

(deftest "subshell failures can result in redundant trace errors"
  (test (get-trace `
    (exit 1) | (exit 2)
    (exit 1) | (exit 1)
    `)
    @[@[1 0 @[1 2]]
      @[1 1 @[1 2]]
      @[2 2 @[1 1]]
      @[2 3 @[1 1]]]))
