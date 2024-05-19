Steno was directly inspired by and is very similar to [Cram](https://bitheap.org/cram/), an excellent tool for testing scripts and command-line interfaces.

The main reason I wrote Steno when Cram already exists is that Cram is a Python script, and using it requires a working Python installation. Steno, in contrast, is distributed as a native binary whose only dependency is `libc`. But there are more differences:

- Steno files are just shell scripts.
    - This means you can syntax highlight them normally, and even execute them without Steno installed at all.
    - Cram requires that you delimit each individual command in separate `$`/`>` blocks. Steno doesn't.
    - Instead, Steno uses specially-formatted comments to indicate output.
- Steno differentiates between stdout and stderr in its output.
- Steno does not have built-in `(regex)` or `(glob)` fuzzy matchers.
- Steno scripts are always `bash` scripts; you cannot configure the shell you use like you can in Cram.
    - Steno uses the non-portable `PIPESTATUS` to report multiple exit codes.

# Example

This is a very boring example:

```
# example.steno
echo hi
```

```
$ steno example.steno
```

```
echo hi
#| hi
```

---

Some notes:

- Steno doesn't interleave `stderr` and `stdout`. `stderr` always appears first, followed by `stdout`. It doesn't matter in what order your program flushes writes to the file descriptors.

When you execute a script like this:

```
echo hi
#|
echo bye
```

The actual stdout of that the script is something like:

```
hi
<random byte sequence 1>
bye
```

Steno parses this output to determine where one "block" ends and the other begins.

```
##        - explicitly indicates that there is no output
#| text   - stdout
#! text   - stderr
#=| text  - verbose stdout
#=! text  - verbose stderr
#? 1      - exit code
#? 1 0 1  - multiple exit codes can follow pipes
```

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

# Exit codes

The following script:

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

Steno will automatically insert `#?` when statements exit non-zero. (It does this by setting an `ERR` trap at the beginning of your script.)

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
##
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
