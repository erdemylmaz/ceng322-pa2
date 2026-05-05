# CENG322 PA-2 Shell

This project implements a simple shell-like C program for CENG322 Operating Systems Programming Assignment #2.

The shell prompt is:

```text
shell322>
```

An empty line is printed before each prompt, as required.

## Files

- `main.c`: source code
- `shell322`: compiled executable, generated with `gcc`
- `PA-2.pdf`: assignment document

## Build

Compile with:

```sh
gcc -Wall -Wextra -pedantic -std=c11 main.c -o shell322
```

Run interactively with:

```sh
./shell322
```

Exit with:

```text
exit
```

## Implemented Requirements

### Built-in Commands

The following commands are implemented inside the shell program, not by calling Linux shell commands:

- `cd <directory>`
  - Uses `chdir()`.
  - Supports relative paths.
  - Supports absolute paths.
  - If no directory is given, changes to `$HOME`.
  - Updates the `PWD` environment variable.

- `pwd`
  - Uses `getcwd()`.
  - Prints the current working directory.

- `mkdir <dir1> ... <dir10>`
  - Creates up to 10 directories in one command.
  - Uses `mkdir()`.

- `rmdir <directory>`
  - Removes one empty directory.
  - Uses `rmdir()`.

- `history`
  - Prints the 10 most recent commands from the current shell session.
  - Uses an internal FIFO array.
  - Includes the `history` command itself.
  - Does not use the Linux `history` command.

- `exit`
  - Terminates the shell with `exit(0)`.

### System Commands

Any non-built-in command is treated as a system command.

The program uses:

- `fork()`
- `execvp()`
- `waitpid()`

The program does not use `system()`.

### Background Processes

A command ending with `&` runs in the background.

Example:

```text
sleep 5 &
```

The shell prints the background process id and immediately shows the next prompt.

### Pipe Operator

One pipe is supported.

Example:

```text
ls -1 | wc -l
```

The program connects the left command's standard output to the right command's standard input using:

- `pipe()`
- `dup2()`
- `fork()`
- `execvp()`

Multiple pipes are not required by the assignment and are not supported.

### Logical AND Operator

One logical AND operator is supported.

Example:

```text
gcc main.c && ./shell322
```

The right command runs only if the left command exits successfully.

Multiple `&&` operators are not required by the assignment and are not supported.

## Assignment Assumptions

This implementation follows the assumptions in `PA-2.pdf`:

- Input line length is at most 100 characters.
- Command arguments are separated by spaces.
- At most 10 command arguments are expected by the assignment.
- At most one of `&`, `|`, and `&&` appears in a command line.
- Quoting, redirection, multiple pipes, and complex shell syntax are not required.

## Manual Test Checklist

After compiling, run:

```sh
./shell322
```

Then test these commands manually.

### `pwd`

```text
pwd
```

Expected: prints the current project directory.

### `cd` with Relative Path

```text
mkdir test_cd
cd test_cd
pwd
cd ..
rmdir test_cd
```

Expected: `pwd` shows that the shell moved into `test_cd`, then returns to the project directory.

### `cd` with Absolute Path

Replace the path with your own project path if needed:

```text
cd /Users/erdem/Documents/iyte/operating-systems/pa2
pwd
```

Expected: `pwd` prints that absolute path.

### `cd` with No Argument

```text
cd
pwd
```

Expected: moves to your home directory.

Then return to the project directory:

```text
cd /Users/erdem/Documents/iyte/operating-systems/pa2
```

### `mkdir` with Multiple Directories

```text
mkdir d1 d2 d3 d4 d5 d6 d7 d8 d9 d10
rmdir d1
rmdir d2
rmdir d3
rmdir d4
rmdir d5
rmdir d6
rmdir d7
rmdir d8
rmdir d9
rmdir d10
```

Expected: all 10 directories are created and then removed.

### `history`

```text
pwd
cd .
pwd
history
```

Expected: prints commands in issue order, including `history`.

### System Command

```text
echo hello
```

Expected:

```text
hello
```

### Background Process

```text
sleep 5 &
```

Expected: prints a process id immediately and shows the next prompt without waiting 5 seconds.

### Pipe

```text
ls -1 | wc -l
```

Expected: prints the number of files/directories in the current directory.

### Logical AND Success

```text
true && echo and_ok
```

Expected:

```text
and_ok
```

### Logical AND Failure

```text
false && echo should_not_print
```

Expected: `should_not_print` is not printed.

## Full Scripted Test

From the project directory, run:

```sh
gcc -Wall -Wextra -pedantic -std=c11 main.c -o shell322

printf 'pwd
mkdir pa2_test_one pa2_test_two
cd pa2_test_one
pwd
cd ..
rmdir pa2_test_one
rmdir pa2_test_two
echo foreground_ok
sleep 1 &
echo background_after
ls -1 | wc -l
false && echo should_not_print
true && echo and_ok
exit
' | ./shell322
```

Expected important results:

- The first `pwd` prints the project directory.
- The second `pwd` prints the `pa2_test_one` directory.
- `foreground_ok` is printed.
- A background process id is printed after `sleep 1 &`.
- `background_after` is printed immediately after the background PID.
- `ls -1 | wc -l` prints a number.
- `should_not_print` is not printed.
- `and_ok` is printed.

## History FIFO Test

Run:

```sh
printf 'echo c1
echo c2
echo c3
echo c4
echo c5
echo c6
echo c7
echo c8
echo c9
echo c10
echo c11
history
exit
' | ./shell322
```

Expected history output:

```text
[1] echo c3
[2] echo c4
[3] echo c5
[4] echo c6
[5] echo c7
[6] echo c8
[7] echo c9
[8] echo c10
[9] echo c11
[10] history
```

This proves that only the latest 10 commands are stored.

## Error Handling Tests

Run:

```sh
printf 'cd no_such_directory_322
mkdir
rmdir
no_such_command_322
exit
' | ./shell322
```

Expected:

- `cd` prints an error.
- `mkdir` prints a missing operand error.
- `rmdir` prints an argument error.
- unknown command prints an `execvp` error.

## Notes

- The shell intentionally stays simple because the assignment only requires basic space-delimited parsing.
- Do not test with quotes, redirection, semicolons, or multiple pipes because those are outside the assignment requirements.
- On Linux, the same `gcc` command above should compile the program.
