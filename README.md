# Steno

> Steno is not finished. It's not even particularly close to finished.

Steno is a tool for snapshot-testing command-line interfaces. You give it a shell script, and it will record the output of every command that it runs:

```bash
# example.steno
echo hello
echo world
```

```
$ steno
```

```bash
# example.steno.corrected
echo hello
echo world
#| hello
#| world
```

Output appears in specially-formatted comment blocks at the end of the script. If you want to put the output closer to the command, you can add an empty `#|` block. This will cause Steno to fill in the output as of this point, then keep going with the rest of the script. For example:

```bash
# example.steno
echo hello
#|
echo world
```

```bash
# example.steno.corrected
echo hello
#| hello
echo world
#| world
```

# Steno and Cram

Steno was directly inspired by [Cram](https://bitheap.org/cram/), an excellent tool for testing scripts and command-line interfaces.

The main reason I wrote Steno when Cram already exists is that Cram is a Python program, and running it requires a working Python installation. But Steno is a [Janet](https://janet-lang.org/) program, and you can run it as a native binary even if you've never heard of Janet before.

But there are more differences:

- Steno files are just shell scripts.
    - This means you can syntax highlight them normally, and even execute them without Steno installed at all.
    - Cram requires that you delimit each individual command in separate `$`/`>` blocks. Steno doesn't.
    - Instead, Steno uses specially-formatted comments to indicate output.
- Steno differentiates between stdout and stderr in its output.
- Steno does not have anything like Cram's `(regex)` or `(glob)` fuzzy matchers. You can achieve the same thing by piping output through `sed`, but I'm not opposed to adding them -- I've just never used them.
- Steno scripts are always `bash` scripts; you cannot configure the shell you use like you can in Cram.
    - Steno uses some Bash-specific features, like `PIPESTATUS`, to report multiple exit codes.

# Special comments

```
#| text   - stdout
#! text   - stderr
#? 1      - exit code
#? 1 0 1  - multiple exit codes can follow pipes
#\        - indicates no final newline on the prrrevious #| or #! block
#-        - indicates that there is no output
```

# `#-`

If your input has an expectation block, but there is no actual output at that point, Steno will write `#-`. This allows you to differentiate between no output and a newline:

```
echo
#|

true
#-
```

Steno will only write `#-` if there is an expectation at that position in its input. This means that on subsequent runs -- where there might be output -- Steno will not have forgetten that you wanted a "checkpoint" there.

# Exit codes

Steno will automatically insert `#?` when statements exit non-zero. So the following script:

```bash
true
false
true
```

Will become:

```bash
true
false
#? 1
true
```

# Debugging

Steno captures stdout and stderr from the script that you run, and doesn't print anything until the entire script completes, which can make it hard to use `printf`-debugging when a test doesn't terminate or takes a long time to complete.

This is annoying, so Steno scripts have access to an extra file descriptor, available as `$STENO_DEBUG_FD`. Any writes to `$STENO_DEBUG_FD` will automatically pass through to Steno's stderr output. 

Steno also defines the following helper function automatically:

```bash
steno_log () { echo >&$STENO_DEBUG_FD "$@" }
```

By default Bash also writes `set -x` output to stderr. Steno sets `BASH_XTRACEFD` to `$STENO_DEBUG_FD`, so its output should be passed through as well.

**But hark!** `BASH_XTRACEFD` is only defined on "newer" versions of Bash (2009 and later). The `/bin/bash` that ships natively with macOS is from 2007, and does not support `BASH_XTRACEFD`. So `set -x` output will be captured by Steno on macOS unless you have a newer version of Bash on your `PATH`. Which you really should.

# Execution model

Steno works by translating the Bash script you give it into another, extremely similar Bash script with a little bit of extra output thrown in -- replacing specially-formatted comment-blocks like `#|` and `#!` with calls to print out a unique, randomized string of bytes.

Then it executes that script, and collects its stdout and stderr output. It searches the output for the random byte strings that it injected, and that tells it what pieces of the output belong to which expectation.

So the script that Steno executes is not *exactly* the same script that would run if you just ran `bash something.steno`. For example:

```
echo hi
#|
echo bye
```

Turns into something more like:

```
echo hi
echo '<some long unique string>'
echo bye
```

This kinda matters, but not really. It means that comments significant to Steno shouldn't appear in certain positions. For example:

```bash
while false;
#| output
do
  :
done
```

That's a valid Bash script that does nothing, but the translated equivalent:

```bash
while false;
printf '<special output delimiter>'
do
  :
done
```

Gets into an infinite loop.

This shouldn't really matter in practice, but if a script behaves differently under Bash and Steno, this is likely the reason.

Another gotcha is Steno's handling of terminal backslashes. A script like this:

```bash
echo hello \
#| hello
```

Will produce nonsense, because that compiles to something like this:

```bash
echo hello \
printf '<special output delimiter>'
```

Although Steno could detect and ignore these, I've decided not to do anything for now as that might not be the intended fix.

# Misc notes

Steno doesn't interleave `stdout` and `stderr`. `stdout` always appears first, followed by `stderr`, followed by the exit status. It doesn't matter in what order your program flushes writes to the file descriptors.

# Unimplemented ideas

If you care about distinguishing lines with newlines, use `#=|`. `#=|` will print whitespace characters as C-style escape codes. For example:

```bash
echo -n first
#| first
echo second
#| second
echo -n second
#| third

echo -n first
#=| first\n
echo second
#=| second
echo -n second
#=| third\n

echo -n first
echo second
echo -n second
#| first
#| secondthird
```

You can also use `#=|` to see ANSI escape sequences, which are otherwise filtered out of the output.

```
(example)
```

You can also use `#~|` to see a "prettified" version of output, that replaces common ANSI escape codes with human-readable equivalents.

```
<red>foo</>
```

(You can also use `#=!` for exact stderr.)

# Background jobs

Steno waits for all background jobs to complete before it exits (it adds an implicit `wait` to the end of your script). If you would instead like to kill processes before you exit, you need to do that explicitly.

TODO: figure out what the right default here is

# Hacking

Building Steno requires [Janet](https://github.com/janet-lang/janet) and [`jpm`](https://github.com/janet-lang/jpm).

```
$ jpm -l deps
$ jpm -l build
$ build/steno
```

Steno's tests are written with [Judge](https://github.com/ianthehenry/judge). I recommend running them interactively, with one of the following invocations (see `--help` for details)

```
$ jpm_tree/bin/judge
$ jpm_tree/bin/judge -i
$ jpm_tree/bin/judge -a
```
