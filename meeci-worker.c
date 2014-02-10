#include <stdio.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>

#include <libmemcached/memcached.h>
#include <systemd/sd-daemon.h>

char meeci_host[16];

int is_valid_ip(char *ip) {
    struct sockaddr_in sa;
    return inet_pton(AF_INET, ip, &(sa.sin_addr));
}

void test() {
    
}

int main(int argc, char *argv[]) {
    if (sd_booted() <= 0) {
        perror("Not running on a systemd system.");
        return 1;
    }

    printf("%d %s\n", argc, argv[0]);
    if (argc > 1) {
        printf("%d\n", is_valid_ip(argv[1]));
    }
    if (geteuid() != 0) {
        printf("not root\n");
    }
}
