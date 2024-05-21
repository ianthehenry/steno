(use judge)
(use ../src/util)
(import ../src :as steno)

(deftest "script executes without stdin"
  (test-stdout (steno/reconcile "cat") `
    cat
    #! cat: -: Bad file descriptor
    #! cat: closing standard input: Bad file descriptor
    #? 1
  `))
