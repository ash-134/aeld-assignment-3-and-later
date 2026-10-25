#include <stdio.h>
#include <stdlib.h>
#include <syslog.h>

int main(int argc, char *argv[]) {
    openlog("writer", LOG_PID, LOG_USER);
    if (argc < 3) {
        syslog(LOG_ERR, "Error: Invalid number of arguments.");
        closelog();
        return 1;
    }
    const char *file_path = argv[1];
    const char *text_to_write = argv[2];
    FILE *fp = fopen(file_path, "w");
    if (fp == NULL) {
        syslog(LOG_ERR, "Error opening file %s", file_path);
        closelog();
        return 1;
    }
    if (fprintf(fp, "%s", text_to_write) < 0) {
        syslog(LOG_ERR, "Error writing to file %s", file_path);
        fclose(fp);
        closelog();
        return 1;
    }
    fclose(fp);
    syslog(LOG_DEBUG, "Writing %s to %s", text_to_write, file_path);
    closelog();
    return 0;
}
