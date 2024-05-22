(use judge)
(use ../src/util)
(import ../src :as steno)

(deftest "steno_log does not show up in error output"
  (def debugs @[])
  (test (steno/transcribe `steno_log hello` :on-debug |(array/push debugs $))
    {:stderr-buf @""
     :stdout-buf @""
     :trace-buf @""})
  (test debugs @[@"hello\n"]))
