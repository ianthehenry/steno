(use judge)
(use ../src/util)
(import ../src :as steno)

(deftest "status codes appear after the error"
  (test (steno/transcribe `
    false
    `)
    {:actual @{0 {:errs @[""] :outs @[""]}}
     :expectations @{0 @{:err @[]
                         :explicit false
                         :out @[]
                         :status @[nil]}}
     :traced @[@[1 @[1]]]}))

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
