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

(def- indentation-peg (peg/compile ~(/ ':s* ,length)))
(defn get-indentation [str] (first (peg/match indentation-peg str)))

(defn unindent [str]
  (def indentation (get-indentation str))
  (string/join (seq [line :in (string/split "\n" str)]
    (string/slice line indentation)) "\n"))

(defmacro pop-while [stack predicate name & body]
  (with-syms [$stack $predicate]
    ~(let [,$stack ,stack ,$predicate ,predicate]
      (while (and (not (empty? ,$stack)) (,$predicate (array/peek ,$stack)))
        (def ,name (array/pop ,$stack))
        ,;body))))

(defn find-last-index [pred ind]
  (var result nil)
  (loop [i :down-to [(dec (length ind)) 0]
         :let [x (in ind i)]
         :when (pred x)]
    (set result i)
    (break))
  result)

(test (find-index odd? [1 2 3 4]) 0)
(test (find-last-index odd? [1 2 3 4]) 2)

(defn find-last [pred ind]
  (var result nil)
  (loop [i :down-to [(dec (length ind)) 0]
         :let [x (in ind i)]
         :when (pred x)]
    (set result x)
    (break))
  result)

(test (find odd? [1 2 3 4]) 1)
(test (find-last odd? [1 2 3 4]) 3)
