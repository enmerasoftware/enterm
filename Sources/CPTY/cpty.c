#include "cpty.h"
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>

int cpty_spawn(const char *path, char *const argv[], char *const envp[], const char *cwd,
               unsigned short rows, unsigned short cols, int *master, pid_t *pid) {
    struct winsize size;
    memset(&size, 0, sizeof(size));
    size.ws_row = rows;
    size.ws_col = cols;
    int fd = -1;
    pid_t child = forkpty(&fd, NULL, NULL, &size);
    if (child < 0) return -1;
    if (child == 0) {
        if (cwd != NULL && chdir(cwd) != 0) chdir("/");
        signal(SIGPIPE, SIG_DFL);
        signal(SIGCHLD, SIG_DFL);
        execve(path, argv, envp);
        _exit(127);
    }
    *master = fd;
    *pid = child;
    return 0;
}

int cpty_resize(int master, unsigned short rows, unsigned short cols) {
    struct winsize size;
    memset(&size, 0, sizeof(size));
    size.ws_row = rows;
    size.ws_col = cols;
    return ioctl(master, TIOCSWINSZ, &size);
}
