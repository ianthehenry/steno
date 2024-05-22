(use judge)
(use ../src/util)
(import ../src :as steno)

# TODO: i think we need to block until all subprocesses complete.
# either that or kill them. don't want to leave orphans around
(deftest "async output gets collected in the final expectation"
  (test-stdout (steno/reconcile (unindent `
    echo hi
    (sleep 1; echo bye) &
    `)) `
    echo hi
    (sleep 1; echo bye) &
    #| hi
    
  `))
