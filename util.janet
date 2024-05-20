(use judge)

(defn ref/new [value] @[value])
(defn ref/set [ref value] (set (ref 0) value))
(defn ref/get [ref] (ref 0))
(defn ref/update [ref f] (ref/set ref (f (ref/get ref))))

(defmacro post++ [x]
  (with-syms [$x]
    ~(let [,$x ,x]
      (++ ,x)
      ,$x)))

(deftest "post++"
  (var x 0)
  (test x 0)
  (test (post++ x) 0)
  (test x 1))

(defmacro get-or-put [t k v]
  (with-syms [$t $k $v]
    ~(let [,$t ,t ,$k ,k]
      (if-let [,$v (,$t ,$k)]
        ,$v
        (let [,$v ,v]
          (put ,$t ,$k ,$v) ,$v)))))

(deftest "get-or-put"
  (def t @{})
  (test t @{})
  (array/push (get-or-put t 0 @[]) :a)
  (array/push (get-or-put t 0 @[]) :b)
  (test t @{0 @[:a :b]}))

(defn table/push [t k v]
  (if-let [arr (in t k)]
    (array/push arr v)
    (put t k @[v])))

(deftest "table/push"
  (def t @{})
  (table/push t :foo 1)
  (test t @{:foo @[1]})
  (table/push t :foo 2)
  (test t @{:foo @[1 2]})
  (table/push t :bar 3)
  (test t @{:bar @[3] :foo @[1 2]}))

(defmacro while-let [bindings & body]
  ~(forever (if-let ,bindings
    (do ,;body)
    (break))))

(defmacro lazy [& body]
  (with-syms [$f $forced? $result]
    ~(do
      (def ,$f (fn [] ,;body))
      (var ,$forced? false)
      (var ,$result nil)
      (fn []
        (unless ,$forced?
          (set ,$result (,$f))
          (set ,$forced? true))
        ,$result))))

(defn ignore [_])

(defn unique [ind]
  (if (> (length (distinct ind)) 1)
    (errorf "non-unique values in %q" ind)
    (first ind)))
