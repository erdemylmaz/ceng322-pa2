// Enable the POSIX function declarations used in this program.
// This is needed for calls like setenv(), fork(), execvp(), pipe(), and waitpid().
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define MAX_LINE 256
#define MAX_ARGS 32
#define HISTORY_SIZE 10

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

// Store the last 10 commands entered by the user.
static char history[HISTORY_SIZE][MAX_LINE];
static int history_count = 0;
static int history_start = 0;

// Remove extra spaces before and after the command.
static char *trim(char *s)
{
    size_t len;

    while (*s == ' ' || *s == '\t')
        s++;

    len = strlen(s);
    while (len > 0 && (s[len - 1] == ' ' || s[len - 1] == '\t' || s[len - 1] == '\n')) {
        s[len - 1] = '\0';
        len--;
    }

    return s;
}

// Add one command to history. If history is full, replace the oldest command.
static void add_history(const char *line)
{
    int index;

    if (history_count < HISTORY_SIZE) {
        index = history_count;
        history_count++;
    } else {
        index = history_start;
        history_start = (history_start + 1) % HISTORY_SIZE;
    }

    snprintf(history[index], MAX_LINE, "%s", line);
}

// Print the stored commands in the order they were entered.
static void print_history(void)
{
    int i;

    for (i = 0; i < history_count; i++) {
        int index = (history_start + i) % HISTORY_SIZE;
        printf("[%d] %s\n", i + 1, history[index]);
    }
}

// Split a command line into arguments using spaces.
static int parse_args(char *line, char *args[])
{
    int count = 0;
    char *token = strtok(line, " ");

    while (token != NULL && count < MAX_ARGS - 1) {
        args[count++] = token;
        token = strtok(NULL, " ");
    }

    args[count] = NULL;
    return count;
}

// Check whether the command is one of the required built-in commands.
static int is_builtin(const char *cmd)
{
    return strcmp(cmd, "cd") == 0 ||
           strcmp(cmd, "pwd") == 0 ||
           strcmp(cmd, "mkdir") == 0 ||
           strcmp(cmd, "rmdir") == 0 ||
           strcmp(cmd, "history") == 0 ||
           strcmp(cmd, "exit") == 0;
}

// Run a built-in command directly inside the shell.
static int run_builtin(char *args[], int argc)
{
    if (strcmp(args[0], "cd") == 0) {
        char cwd[PATH_MAX];
        char *target = args[1];

        if (argc > 2) {
            fprintf(stderr, "cd: too many arguments\n");
            return 1;
        }

        // If no directory is given, cd should go to HOME.
        if (target == NULL) {
            target = getenv("HOME");
            if (target == NULL) {
                fprintf(stderr, "cd: HOME is not set\n");
                return 1;
            }
        }

        if (chdir(target) != 0) {
            perror("cd");
            return 1;
        }

        // After chdir(), update PWD so child commands see the new directory.
        if (getcwd(cwd, sizeof(cwd)) == NULL) {
            perror("getcwd");
            return 1;
        }

        if (setenv("PWD", cwd, 1) != 0) {
            perror("setenv");
            return 1;
        }

        return 0;
    }

    if (strcmp(args[0], "pwd") == 0) {
        char cwd[PATH_MAX];

        if (getcwd(cwd, sizeof(cwd)) == NULL) {
            perror("pwd");
            return 1;
        }

        printf("%s\n", cwd);
        return 0;
    }

    if (strcmp(args[0], "mkdir") == 0) {
        int i;
        int status = 0;

        if (argc < 2) {
            fprintf(stderr, "mkdir: missing operand\n");
            return 1;
        }

        // The assignment allows mkdir to create up to 10 directories.
        if (argc > 11) {
            fprintf(stderr, "mkdir: at most 10 directories are allowed\n");
            return 1;
        }

        for (i = 1; i < argc; i++) {
            if (mkdir(args[i], 0777) != 0) {
                perror(args[i]);
                status = 1;
            }
        }

        return status;
    }

    if (strcmp(args[0], "rmdir") == 0) {
        // rmdir is required to take exactly one directory name.
        if (argc != 2) {
            fprintf(stderr, "rmdir: exactly one directory name is required\n");
            return 1;
        }

        if (rmdir(args[1]) != 0) {
            perror(args[1]);
            return 1;
        }

        return 0;
    }

    if (strcmp(args[0], "history") == 0) {
        // The command was already saved before this function is called.
        print_history();
        return 0;
    }

    if (strcmp(args[0], "exit") == 0) {
        exit(0);
    }

    return 1;
}

// Wait until a foreground child process finishes.
static int wait_for_child(pid_t pid)
{
    int status;

    while (waitpid(pid, &status, 0) == -1) {
        if (errno != EINTR) {
            perror("waitpid");
            return 1;
        }
    }

    if (WIFEXITED(status))
        return WEXITSTATUS(status);

    return 1;
}

// Run a normal system command by using fork() and execvp().
// For background commands, print the process id and do not wait.
static int run_external(char *args[], int background)
{
    pid_t pid = fork();

    if (pid < 0) {
        perror("fork");
        return 1;
    }

    if (pid == 0) {
        execvp(args[0], args);
        perror(args[0]);
        exit(1);
    }

    if (background) {
        // For background commands the parent shell should continue immediately.
        printf("%d\n", (int)pid);
        return 0;
    }

    return wait_for_child(pid);
}

// Run one command that does not contain pipe or logical AND.
static int run_command(char *command, int background)
{
    char *args[MAX_ARGS];
    int argc;

    command = trim(command);
    if (*command == '\0')
        return 0;

    argc = parse_args(command, args);
    if (argc == 0)
        return 0;

    if (is_builtin(args[0]))
        return run_builtin(args, argc);

    return run_external(args, background);
}

// Used by pipe children after stdin or stdout is redirected.
static void run_child_command(char *command)
{
    char *args[MAX_ARGS];
    int argc;

    command = trim(command);
    argc = parse_args(command, args);

    if (argc == 0)
        exit(0);

    if (is_builtin(args[0]))
        exit(run_builtin(args, argc));

    execvp(args[0], args);
    perror(args[0]);
    exit(1);
}

// Run two commands connected by one pipe.
static int run_pipe(char *left, char *right)
{
    int fd[2];
    pid_t first;
    pid_t second;
    int right_status;

    left = trim(left);
    right = trim(right);

    if (*left == '\0' || *right == '\0') {
        fprintf(stderr, "pipe: missing command\n");
        return 1;
    }

    if (pipe(fd) != 0) {
        perror("pipe");
        return 1;
    }

    first = fork();
    if (first < 0) {
        perror("fork");
        close(fd[0]);
        close(fd[1]);
        return 1;
    }

    if (first == 0) {
        // The left command writes its output into the pipe.
        close(fd[0]);
        if (dup2(fd[1], STDOUT_FILENO) == -1) {
            perror("dup2");
            exit(1);
        }
        close(fd[1]);
        run_child_command(left);
    }

    second = fork();
    if (second < 0) {
        perror("fork");
        close(fd[0]);
        close(fd[1]);
        wait_for_child(first);
        return 1;
    }

    if (second == 0) {
        // The right command reads its input from the pipe.
        close(fd[1]);
        if (dup2(fd[0], STDIN_FILENO) == -1) {
            perror("dup2");
            exit(1);
        }
        close(fd[0]);
        run_child_command(right);
    }

    close(fd[0]);
    close(fd[1]);
    wait_for_child(first);
    right_status = wait_for_child(second);

    return right_status;
}

// Run the second command only if the first command succeeds.
static int run_and(char *left, char *right)
{
    int status;

    left = trim(left);
    right = trim(right);

    if (*left == '\0' || *right == '\0') {
        fprintf(stderr, "&&: missing command\n");
        return 1;
    }

    status = run_command(left, 0);
    if (status == 0)
        status = run_command(right, 0);

    return status;
}

// Remove finished background processes without blocking the shell.
static void reap_background_processes(void)
{
    while (waitpid(-1, NULL, WNOHANG) > 0)
        ;
}

int main(void)
{
    char line[MAX_LINE];

    while (1) {
        char command[MAX_LINE];
        char *input;
        char *operator_pos;
        int background = 0;
        size_t len;

        reap_background_processes();

        // The assignment asks for an empty line before each prompt.
        printf("\nshell322>");
        fflush(stdout);

        if (fgets(line, sizeof(line), stdin) == NULL) {
            printf("\n");
            break;
        }

        input = trim(line);
        if (*input == '\0')
            continue;

        snprintf(command, sizeof(command), "%s", input);
        // Save the original command before strtok() changes the string.
        add_history(command);

        // The input has at most one special operator, so check them one by one.
        operator_pos = strstr(command, "&&");
        if (operator_pos != NULL) {
            *operator_pos = '\0';
            run_and(command, operator_pos + 2);
            continue;
        }

        operator_pos = strchr(command, '|');
        if (operator_pos != NULL) {
            *operator_pos = '\0';
            run_pipe(command, operator_pos + 1);
            continue;
        }

        len = strlen(command);
        if (len > 0 && command[len - 1] == '&') {
            command[len - 1] = '\0';
            background = 1;
        }

        run_command(command, background);
    }

    return 0;
}
