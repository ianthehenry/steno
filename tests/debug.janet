(use judge)
(use ../src/util)
(import ../src :as steno)

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
