(use judge)
(use ../src/util)
(import ../src :as steno)

(deftest "error reports"
  (test (steno/transcribe `
    true
    false
    `)
    {:actual @{0 {:errs @[""] :outs @[""]}}
     :expectations @{0 @{:err "" :explicit false :out ""}}
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
     :expectations @{0 @{:err ""
                         :explicit true
                         :out "this will interfere\n\n\n\n"}
                     1 @{:err "" :explicit false :out ""}}
     :traced @[@[3 @[1]]]}))

(deftest "pipes split across multiple times report status as the final line"
  (test (steno/transcribe `
    true | \
    false
    `)
    {:actual @{0 {:errs @[""] :outs @[""]}}
     :expectations @{0 @{:err "" :explicit false :out ""}}
     :traced @[@[2 @[0 1]]]})
  (test (steno/transcribe `
    false | \
    false | \
    false | \
    false | \
    false`)
    {:actual @{0 {:errs @[""] :outs @[""]}}
     :expectations @{0 @{:err "" :explicit false :out ""}}
     :traced @[@[5 @[1 1 1 1 1]]]}))

(deftest "if a pipeline fails, succeeds, then fails, it will report multiple failures"
  (test (steno/transcribe `
    true | false | true | \
    false | true | false
    `)
    {:actual @{0 {:errs @[""] :outs @[""]}}
     :expectations @{0 @{:err "" :explicit false :out ""}}
     :traced @[@[2 @[0 1 0 1 0 1]]]}))

(deftest "subshell failures can result in redundant trace errors"
  (test (steno/transcribe `
    (exit 1) | (exit 2)
    (exit 1) | (exit 1)
    `)
    {:actual @{0 {:errs @[""] :outs @[""]}}
     :expectations @{0 @{:err "" :explicit false :out ""}}
     :traced @[@[1 @[1 2]]
               @[1 @[1 2]]
               @[2 @[1 1]]
               @[2 @[1 1]]]}))
