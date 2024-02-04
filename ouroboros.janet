(import ./posix-spawn/posix-spawn)

(defn main [&]
  (def proc (os/spawn ["/bin/bash" "ouroboros.jam"]
    :e {
    :in :pipe
    :out :pipe
    #:err :pipe
    "HELLO" "THERE"
    }))

  #(ev/write (proc :in) "hey\0there\0123\0okay")
  #(ev/close (proc :in))

  (while (proc :out)
    (def chunk (ev/read (proc :out) 1024))
    (pp chunk)
    (unless chunk (break))
    # We read this into a bash variable, and bash variables
    # are c-strings that can't contain null bytes. So we
    # strip the null bytes out here.
    (def sanitized (string/replace-all "\0" "\\0" chunk))
    (ev/write (proc :in) sanitized))

  #(pp (ev/read (proc :out) 1024))
  #(pp (ev/read (proc :out) 1024))
  #(pp (ev/read (proc :out) 1024))
  #(pp (ev/read (proc :out) 1024))

  (os/proc-wait proc)
  )

(defn forward-loopback [from to]
  (print "forwarding")
  (while true
    (def chunk (ev/read from 1024))
    (unless chunk (print "NO CHUNK") (break))
    # We read this into a bash variable, and bash variables
    # are c-strings that can't contain null bytes. So we
    # strip the null bytes out here.
    (def sanitized (string/replace-all "\0" "\\0" chunk))
    (ev/write to sanitized)))

(defn main [&]
  (def [stdout-reader stdout-writer] (posix-spawn/pipe :read-stream))
  (def [stdout-loopback-reader stdout-loopback-writer] (posix-spawn/pipe :write-stream))

  # this is useful
  (def [stderr-reader stderr-writer] (posix-spawn/pipe :read-stream))

  (def [stderr-loopback-reader stderr-loopback-writer] (posix-spawn/pipe :write-stream))
  (def [debug-reader debug-writer] (posix-spawn/pipe :read-stream))

  (def proc
    (posix-spawn/spawn2 ["/bin/bash" "ouroboros.jam"]
    {:cmd "bash"
     :file-actions
       [[:close stdin]
        [:dup2 stdout-loopback-reader 4]
        [:dup2 stderr-loopback-reader 5]
        [:close stdout] [:dup2 stdout-writer stdout]
        [:close stderr] [:dup2 stderr-writer stderr]
        [:dup2 debug-writer 6]
        ]}))
  (file/close stdout-writer)
  (file/close stderr-writer)
  (file/close debug-writer)

  #(ev/write (proc :in) "hey\0there\0123\0okay")
  #(ev/close (proc :in))
  (var closed false)

  (ev/spawn (forward-loopback stdout-reader stdout-loopback-writer))
  (ev/spawn (forward-loopback stderr-reader stderr-loopback-writer))
  (ev/spawn
    (while true
      (def chunk (ev/read debug-reader 1024))
      (unless chunk (print "NO DEBUG CHUNK") (break))
      (printf "debug: %s" chunk)))

  (print "okay waiting")
  (while true
    (case (proc :exit-code)
      nil (ev/sleep 0.001)
      (do
        #(file/close stdout-writer)
        #(file/close stderr-writer)
        (break))
      ))
  (printf "exited" (proc :exit-code))
  (print "done waiting; process is gone")

  #(pp (ev/read (proc :out) 1024))
  #(pp (ev/read (proc :out) 1024))
  #(pp (ev/read (proc :out) 1024))
  #(pp (ev/read (proc :out) 1024))

  #(os/proc-wait proc)
  )
