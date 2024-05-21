(use judge)
(use ../src/util)
(import ../src :as steno)

(deftest "transcribe-raw"
  (test (steno/transcribe-raw "echo stdout; echo stderr >&2; false")
    {:stderr-buf @"stderr\n"
     :stdout-buf @"stdout\n"
     :trace-buf @"10 1\0"}))

(deftest "transcribe-raw redirects stdout properly"
  (test (steno/transcribe-raw "echo stdout >/dev/stdout")
    {:stderr-buf @""
     :stdout-buf @"stdout\n"
     :trace-buf @""}))

(deftest "transcribe-raw can read null bytes correctly"
  (test (steno/transcribe-raw "printf '\\0\\0\\0'")
    {:stderr-buf @""
     :stdout-buf @"\0\0\0"
     :trace-buf @""}))

(deftest "no deadlock on a giant write that has a giant read"
  # we shouldn't really hardcode this; if we're underestimating
  # the buffer size then this test would succeed without actually
  # testing anything
  (def pipe-buffer-size (* 16 4096))
  (def too-big (+ 1 pipe-buffer-size))
  (def script (buffer/new-filled too-big (chr "\n")))
  (buffer/blit script (string "dd if=/dev/zero bs="too-big" count=1 status=none") 0)

  (def {:stderr-buf stderr-buf
        :stdout-buf stdout-buf
        :trace-buf trace-buf}
        (steno/transcribe-raw script))

  (test (length stdout-buf) 65537))
