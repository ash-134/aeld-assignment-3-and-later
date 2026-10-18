#include "systemcalls.h"
#include <stdlib.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

bool do_system(const char *command)
{
    fflush(stdout);
    if (command == NULL) {
        return false;
    }
    int ret = system(command);
    if (ret == -1) {
        return false;
    }
    if (WIFEXITED(ret) && WEXITSTATUS(ret) == 0) {
        return true;
    }
    return false;
}

bool do_exec(int count, ...)
{
    fflush(stdout);
    va_list args;
    va_start(args, count);
    char *command[count + 1];
    for (int i = 0; i < count; i++) {
        command[i] = va_arg(args, char *);
    }
    command[count] = NULL;

    pid_t pid = fork();
    if (pid == -1) {
        va_end(args);
        return false;
    } else if (pid == 0) {
        execv(command[0], command);
        exit(EXIT_FAILURE);
    }

    va_end(args);
    int status;
    pid_t wait_pid = waitpid(pid, &status, 0);
    if (wait_pid == -1) {
        return false;
    }
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        return true;
    }
    return false;
}

bool do_exec_redirect(const char *outputfile, int count, ...)
{
    fflush(stdout);
    va_list args;
    va_start(args, count);
    char *command[count + 1];
    for (int i = 0; i < count; i++) {
        command[i] = va_arg(args, char *);
    }
    command[count] = NULL;

    int fd = open(outputfile, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        va_end(args);
        return false;
    }

    pid_t pid = fork();
    if (pid == -1) {
        close(fd);
        va_end(args);
        return false;
    } else if (pid == 0) {
        if (dup2(fd, STDOUT_FILENO) < 0) {
            close(fd);
            exit(EXIT_FAILURE);
        }
        close(fd);
        execv(command[0], command);
        exit(EXIT_FAILURE);
    }

    close(fd);
    va_end(args);

    int status;
    pid_t wait_pid = waitpid(pid, &status, 0);
    if (wait_pid == -1) {
        return false;
    }
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        return true;
    }
    return false;
}