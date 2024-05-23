(use judge)
(use ../src/util)
(import ../src :as steno)

(deftest "basic correction"
  (test-stdout (steno/reconcile (unindent `
    echo hello
    #| goodbye`)) `
    echo hello
    #| hello
  `))

(deftest "empty file"
  (test-stdout (steno/reconcile "") `
    
  `))
(deftest "nearly empty file"
  (test-stdout (steno/reconcile "\n") `
    
    
  `))

(deftest "implicit expectation always inserted"
  (test-stdout (steno/reconcile "echo hello") `
    echo hello
    #| hello
  `))

(deftest "uncaptured output is captured at the end"
  (test-stdout (steno/reconcile (unindent `
    echo one
    #| foo
    echo two`)) `
    echo one
    #| one
    echo two
    #| two
  `))

(deftest "explicit expectations still appear even with no output"
  (test-stdout (steno/reconcile (unindent `
    true
    #| foo
    true`)) `
    true
    #-
    true
  `))

# TODO
(deftest "unreachable code causes an error"
  (test-stdout (steno/reconcile (unindent `
    echo one
    #| one
    exit 0
    echo two
    #| two
    true`)) `
    echo one
    #| one
    exit 0
    echo two
    #-
    true
  `))
