`jam` was directly inspired by and is very similar to [`cram`](https://bitheap.org/cram/), an excellent tool for testing scripts and command-line interfaces.

The main reason I wrote `jam` when `cram` already exists is that `cram` is a Python script, and using it requires a working Python installation. `jam`, in contrast, is distributed as a native binary whose only dependency is `libc`. But there are more differences:

- `jam` files are quite close to regular shell scripts.
    - This means you can syntax highlight them as normal `bash` scripts.
    - `cram` requires that you delimit each individual command in separate `$`/`>` blocks. `jam` does not.
    - `jam` uses specially-formatted comments to indicate output.
- `jam` differentiates between stdout and stderr in its output.
- `jam` does not have built-in `(regex)` or `(glob)` fuzzy line matchers, but does have some other niceties explained below.
- `jam` scripts are always `bash` scripts; you cannot configure the shell you use like you can in `cram`.
    - `jam` uses the non-portable `PIPESTATUS` to report multiple exit codes.
    - `jam` uses `BASH_XTRACEFD` to trace the exit codes for individual commands.

# Example

This is a very boring example:

```
# example.jam
echo hi
```

```
$ jam example.jam
```

```
echo hi
#| hi
```

---

Some notes:

- `jam` doesn't interleave `stderr` and `stdout`. `stderr` always appears first, followed by `stdout`. It doesn't matter in what order your program flushes writes to the file descriptors.

When you execute a script like this:

```
echo hi
#=
echo bye
```

The actual stdout of that the script is:

```
<start token>hi
<end token>
<start token>bye
<end token>
```

Except that `<start token>` and `<end token>` are special.

```
##        - explicitly indicates that there is no output
#| text   - stdout
#! text   - stderr
#=| text  - verbose stdout
#=! text  - verbose stderr
#? 1      - exit code
#? 1 0 1  - multiple exit codes follow pipes
```

If you want to distinguish lines with newlines, use `#=|`. `#=|` will print whitespace characters and control characters as escape codes. For example:

```bash
echo -n first
echo second
echo -n second
#| first
#| second
#| third

echo -n first
echo second
echo -n second
#=| first\n
#=| second
#=| third\n
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

```bash
echo -n first
echo second
echo -n second
#| first
#| second
#| third

echo -n first
echo second
echo -n second
#=| first\n
#=| second
#=| third\n
```

By default `jam` will insert.

This is a special syntax:

### something.txt
hello
this is something
the end
###

This is equivalent to:

cat >something.txt <<'EOF'
hello
this is something
the end
'EOF'

Although note that, if you use this syntax, your `jam` scripts can no longer be executed as regular `bash` scripts. It's up to you to decide whether or not you care about that.

---

By default `jam` does not set `-e`, so a script will keep going the failure of any subcommand... somehow.

# Execution model

The way that `jam` works is that it generate a unique, random string to use as an output delimeter, and it interleaves that delimiter with your script's actual output. Then, once your script has exited, it splits the output on that delimiter and lines it up with the input.

So the script that `jam` executes is not *exactly* the same script that would run if you just ran `bash something.jam`. For example:

```
echo hi
|=
echo bye
```

Turns into something more like:

```
echo hi
echo -n '<some long unique string>'
echo bye
```

This kinda matters, but not really. It means that comments significant to `jam` can't appear in certain positions. For example:

```bash
while false;
#= output
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

This shouldn't really matter in practice.

Ah, we need to distinguish `$?` and `PIPESTATUS`. If a command executes inside ` while` or `if`, `PIPESTATUS` will reflect the real exit code, while `$?` will be `0`. So something like:

```
trap ": ERR" ERR
PS4='+ $LINENO $? [${PIPESTATUS[*]}] '
```

Interesting.

I *think* this renders the error trap unusable?
