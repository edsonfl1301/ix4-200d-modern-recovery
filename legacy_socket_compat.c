/* Linux 2.6 compatibility for an isolated, single-listener Samba process.
 * SO_REUSEPORT is optional here; do not suppress any other socket errors.
 * No authentication, signing or encryption behavior is changed.
 */
typedef unsigned int socklen_t;
extern void *dlsym(void *, const char *);
extern int *__errno_location(void);
typedef int (*setsockopt_fn)(int, int, int, const void *, socklen_t);

int setsockopt(int fd, int level, int option, const void *value, socklen_t size)
{
    static setsockopt_fn original;
    if (!original) original = (setsockopt_fn)dlsym((void *)-1, "setsockopt");
    if (!original) { *__errno_location() = 38; return -1; }
    int result = original(fd, level, option, value, size);
    if (result == -1 && level == 1 && option == 15 && *__errno_location() == 92)
        return 0;
    return result;
}
