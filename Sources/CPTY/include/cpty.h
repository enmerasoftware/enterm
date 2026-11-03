#ifndef CPTY_H
#define CPTY_H
#include <sys/types.h>

/* Starts `path` on a new pseudo terminal. Returns 0 and fills master and pid, or -1 with errno. */
int cpty_spawn(const char *path, char *const argv[], char *const envp[], const char *cwd,
               unsigned short rows, unsigned short cols, int *master, pid_t *pid);
int cpty_resize(int master, unsigned short rows, unsigned short cols);
#endif
