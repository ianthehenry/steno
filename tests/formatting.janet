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

(deftest "output indentation matches the indentation of the previous source line"
  (test-stdout (steno/reconcile (unindent `
    echo hi
      #| foo
      echo hi
      echo hi >&2
      false
      #|
      true
      #|
    #| foo`)) `
    echo hi
    #| hi
      echo hi
      echo hi >&2
      false
      #| hi
      #! hi
      #? 1
      true
      #-
  `))

# TODO
(deftest "newline between source and implicit final expectation when source ends in a newline"
  (test-stdout (steno/reconcile (unindent `
    echo hi
    `)) `
    echo hi
    
    #| hi
  `))

# TODO
(deftest "trailing newline doesn't mess up location of status"
  (test-stdout (steno/reconcile (unindent `
    echo hi
    false
    `)) `
    echo hi
    false
    #? 1
    
    #| hi
  `))
