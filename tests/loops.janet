(use judge)
(use ../src/util)
(import ../src :as steno)

(deftest "single exit code in a loop is fine"
  (test-stdout (steno/reconcile (unindent `
    for i in 0 1; do
      false
    done`)) `
    for i in 0 1; do
      false
    done
  `))

(deftest "multiple distinct exit codes in a loop is not fine"
  (test-stdout (steno/reconcile (unindent `
    for i in 0 1; do
      test $i = 0
    done`)) `
    for i in 0 1; do
      test $i = 0
    done
  `))

(deftest "single output in a loop is fine"
  (test-stdout (steno/reconcile (unindent `
    for i in 0 1; do
      echo hi
      #| hi
    done`)) `
    for i in 0 1; do
      echo hi
      #| hi
    done
  `))

(deftest "multiple distinct outputs in a loop is not fine"
  (test-error (steno/reconcile (unindent `
    for i in 0 1; do
      echo $i
      #| hi
    done`))
    "non-unique values in @[\"0\\n\" \"1\\n\"]"))
