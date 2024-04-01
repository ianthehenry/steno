`steno` was directly inspired by and is very similar to [`cram`](https://bitheap.org/cram/), an excellent tool for testing scripts and command-line interfaces.

The main reason I wrote `steno` when `cram` already exists is that `cram` is a Python script, and using it requires a working Python installation. `steno`, in contrast, is distributed as a native binary whose only dependency is `libc`. But there are more differences:

- `steno` files are just shell scripts.
    - This means you can syntax highlight them normally, and even execute them without `steno` installed at all.
    - `cram` requires that you delimit each individual command in separate `$`/`>` blocks. `steno` doesn't.
    - Instead, `steno` uses specially-formatted comments to indicate output.
- `steno` differentiates between stdout and stderr in its output.
- `steno` does not have built-in `(regex)` or `(glob)` fuzzy matchers.
- `steno` scripts are always `bash` scripts; you cannot configure the shell you use like you can in `cram`.
    - `steno` uses the non-portable `PIPESTATUS` to report multiple exit codes.

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

- `steno` doesn't interleave `stderr` and `stdout`. `stderr` always appears first, followed by `stdout`. It doesn't matter in what order your program flushes writes to the file descriptors.

When you execute a script like this:

```
echo hi
#=
echo bye
```

The actual stdout of that the script is something like:

```
hi
<random byte sequence 1>
bye
```

`steno` parses this output to determine where one "block" ends and the other begins.

```
##        - explicitly indicates that there is no output
#| text   - stdout
#! text   - stderr
#=| text  - verbose stdout
#=! text  - verbose stderr
#? 1      - exit code
#? 1 0 1  - multiple exit codes follow pipes
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

`steno` will automatically insert `#?` when statements exit non-zero. (It does this by setting an `ERR` trap at the beginning of your script.)

# Debugging

`steno` captures stdout and stderr from the script that you run, and doesn't print anything until the entire script completes. This means that you can't use "printf debugging" to trace the execution of your script and debug something like an infinite loop. You also can't use `set -x`, since that writes to stderr, which is also captured.

In order to get around this, steno sets up an extra file descriptor, available as `$STENO_DEBUG_FD`. Any writes to `$STENO_DEBUG_FD` will pass through to `steno`'s stderr output.

It also provides `$STENO_TRACE`, which you can execute as an unquoted top-level command:

```bash
$STENO_TRACE

echo okay then
```

To enable `set -x` and simultaneously redirect its output to the debug file descriptor.

> **Note!** This feature uses `BASH_XTRACEFD`, which is only defined on "newer" versions of Bash (2009 and later). The `bash` that ships natively with macOS is from 2007, and does not support `BASH_XTRACEFD`. So `$STENO_TRACE` will not work on macOS unless you have a newer version of Bash on your `PATH`. Which you should.

As well as `$STENO_LOG`, which you can use to print stuff.

```
# these two lines are equivalent:

$STENO_LOG hello
echo hello >&$STENO_DEBUG_FD
```

Probably these shouldn't be environment variables, and should be defined as shell functions instead. Hmm.

# Execution model

The way that `steno` works is that it generate a unique, random string to use as an output delimeter, and it interleaves that delimiter with your script's actual output. Then, once your script has exited, it splits the output on that delimiter and lines it up with the input.

So the script that `steno` executes is not *exactly* the same script that would run if you just ran `bash something.steno`. For example:

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

This kinda matters, but not really. It means that comments significant to `steno` shouldn't appear in certain positions. For example:

```bash
while false;
#| output
do
  :
done
```

That's a valid `bash` script that does nothing, but the translated equivalent:

```bash
while false;
echo '<special output delimiter>'
do
  :
done
```

Gets into an infinite loop.

This shouldn't really matter in practice, but if a script behaves differently under `bash` and `steno`, this is likely the reason.
