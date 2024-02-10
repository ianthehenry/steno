(use judge)

(defn ref/new [value] @[value])
(defn ref/set [ref value] (set (ref 0) value))
(defn ref/get [ref] (ref 0))
(defn ref/update [ref f] (ref/set ref (f (ref/get ref))))

(defn clone [buf] (buffer buf))

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

(defn table/push [tab k v]
  (if-let [arr (in tab k)]
    (array/push arr v)
    (put tab k @[v])))

(defmacro while-let [bindings & body]
  ~(forever (if-let ,bindings
    (do ,;body)
    (break))))
