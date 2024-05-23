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

(deftest "output indentation ignores blank lines"
  (test-stdout (steno/reconcile (unindent `
    echo hi
      echo hi
    
    #|`)) `
    echo hi
      echo hi
    
      #| hi
      #| hi
  `))

(deftest "newline between source and implicit final expectation when source ends in a newline"
  (test-stdout (steno/reconcile (unindent `
    echo hi
    `)) `
    echo hi
    #| hi
    
  `))

(deftest "trailing newline doesn't mess up location of status"
  (test-stdout (steno/reconcile (unindent `
    echo hi
    false
    `)) `
    echo hi
    false
    #| hi
    #? 1
    
  `))

(deftest "output with no trailing newline is distinguished"
  (test-stdout (steno/reconcile (unindent `
    echo hi
    #|
    echo -n hi
    #|
    `)) `
    echo hi
    #| hi
    echo -n hi
    #| hi
    #\
    
  `)
  (test-stdout (steno/reconcile (unindent `
    echo hi >&2
    #|
    echo -n hi >&2
    #|
    `)) `
    echo hi >&2
    #! hi
    echo -n hi >&2
    #! hi
    #\
    
  `)
  (test-stdout (steno/reconcile (unindent `
    echo -n hi
    echo -n hi >&2
    `)) `
    echo -n hi
    echo -n hi >&2
    #| hi
    #\
    #! hi
    #\
    
  `)
  )

# TODO: this isn't great
(deftest "trailing backslashes can kinda screw things up"
  (test-stdout (steno/reconcile (unindent `
    echo \`)) `
    echo \
    #| printf \x28\xa7\xdb\x5d\xfd\xbc\x47\x9c\x00\x00\x00\x00
  `))

# this is worse, though
(deftest "trailing backslashes can kinda screw things up"
  (test-stdout (steno/reconcile (unindent `
    echo \
    #| \`)) `
    echo \
    #| printf \x3d\xb2\xfe\xa3\xde\x49\xb8\x11\x00\x00\x00\x00
  `))

(deftest "bash doesn't treat trealing backslashes in comments as significant"
  (test-stdout (steno/reconcile (unindent `
    echo 'for example \'
    #| for example \
    echo byee`)) `
    echo 'for example \'
    #| for example \
    echo byee
    #| byee
  `))

