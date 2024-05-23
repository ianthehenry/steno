(use judge)
(use ../src/util)
(import ../src :as steno)

(deftest "async output gets collected in the final expectation"
  (test-stdout (steno/reconcile (unindent `
    echo hi
    #|
    (sleep 0; echo bye) &
    `)) `
    echo hi
    #| hi
    (sleep 0; echo bye) &
    #| bye
    
  `))

(deftest "async errors aren't reported anywhere"
  (test-stdout (steno/reconcile (unindent `
    false &
    echo hi
    #|
    (sleep 0; echo bye; false) &
    `)) `
    false &
    echo hi
    #| hi
    (sleep 0; echo bye; false) &
    #| bye
    
  `))

(deftest "async output goes after the final non-empty line"
  (test-stdout (steno/reconcile (unindent `
    (sleep 0; echo bye; false) &
    
    
    `)) `
    (sleep 0; echo bye; false) &
    #| bye
    
    
    
  `))
