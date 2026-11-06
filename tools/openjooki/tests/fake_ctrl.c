/* A stand-in for one of the Jooki's closed hardware controllers (gpio_ctrl, ht_ctrl, esp32_ctrl),
 * for test_mqtt_lan.py. It behaves as they do with the broker: it connects to 127.0.0.1:PORT,
 * says it is alive (a retained /j/fake/alive/<its name> = its pid), and when the broker goes it
 * leaves with exit 0, a "clean" exit that the launcher does not restart. It cannot reach the
 * broker: exit 3, a crash, which the launcher restarts.   usage: <name> PORT */
#include <arpa/inet.h>
#include <libgen.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static int put_str(unsigned char *b, const char *s) {
  int n = (int)strlen(s);
  b[0] = (unsigned char)(n >> 8); b[1] = (unsigned char)(n & 255);
  memcpy(b + 2, s, (size_t)n);
  return n + 2;
}

static int send_all(int s, const unsigned char *b, int n) { return write(s, b, (size_t)n) == n ? 0 : -1; }

int main(int argc, char **argv) {
  int port = argc > 1 ? atoi(argv[1]) : 1883;
  char *name = basename(argv[0]);
  char id[64], topic[96], msg[32];
  unsigned char b[512], v[256];
  int n = 0, vn = 0;
  struct sockaddr_in a;

  snprintf(id, sizeof id, "%s-%d", name, (int)getpid());
  int s = socket(AF_INET, SOCK_STREAM, 0);
  memset(&a, 0, sizeof a);
  a.sin_family = AF_INET; a.sin_port = htons((unsigned short)port); a.sin_addr.s_addr = htonl(0x7f000001);
  if (s < 0 || connect(s, (struct sockaddr *)&a, sizeof a) < 0) return 3;

  /* CONNECT, MQTT 3.1.1, clean session, keep-alive 60 s */
  vn += put_str(v, "MQTT"); v[vn++] = 4; v[vn++] = 2; v[vn++] = 0; v[vn++] = 60; vn += put_str(v + vn, id);
  b[n++] = 0x10; b[n++] = (unsigned char)vn; memcpy(b + n, v, (size_t)vn); n += vn;
  if (send_all(s, b, n) < 0) return 3;
  if (read(s, b, 4) != 4 || b[0] != 0x20 || b[3] != 0) return 3;

  /* PUBLISH, QoS 0, retained: alive */
  snprintf(topic, sizeof topic, "/j/fake/alive/%s", name);
  snprintf(msg, sizeof msg, "%d", (int)getpid());
  vn = put_str(v, topic); memcpy(v + vn, msg, strlen(msg)); vn += (int)strlen(msg);
  n = 0; b[n++] = 0x31; b[n++] = (unsigned char)vn; memcpy(b + n, v, (size_t)vn); n += vn;
  if (send_all(s, b, n) < 0) return 3;

  struct pollfd p = { s, POLLIN, 0 };
  for (;;) {
    int r = poll(&p, 1, 20000);
    if (r == 0) { unsigned char ping[2] = { 0xc0, 0 }; if (send_all(s, ping, 2) < 0) return 0; continue; }
    if (read(s, b, sizeof b) <= 0) return 0;   /* the broker went away: a "clean" exit */
  }
}
