(use judge)
(use ../src/util)
(import ../src :as steno)

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
