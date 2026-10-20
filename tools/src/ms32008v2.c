/* ms32008v2 - replay stone-main's MS32008 PTZ start/stop bursts (i2c-1, addr 0x10).
 * Derived from offline RE of stone-main 6.2163.49,
 * Default is DRY RUN (prints only). Pass --go to write.
 * usage: ms32008v2 [--go] [--bus /dev/i2c-1] <pan|tilt> <dir 0|1> <qsteps 1..800> [pps=1500] [hold_ms=auto]
 *        ms32008v2 [--go] start <pan|tilt> <dir> <q> [pps]   (no hold, no stop)
 *        ms32008v2 [--go] count   (read pulseRecord regs)
 *        ms32008v2 [--go] stop
 * Never touches GPIO, flash or other devices. Does not re-init the chip (stone-main did that at boot). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/i2c.h>
#include <linux/i2c-dev.h>

static int fd = -1, go = 0;
#define ADDR 0x10
#define FCLK 15000000u          /* value stone-main uses (.data 0x8a7e54) */

static int wr(unsigned reg, unsigned val) {
    unsigned char b[2] = { (unsigned char)reg, (unsigned char)val };
    struct i2c_msg m = { ADDR, 0, 2, b };
    struct i2c_rdwr_ioctl_data d = { &m, 1 };
    printf("  w 0x%02x <- 0x%02x\n", reg, val);
    if (!go) return 0;
    if (ioctl(fd, I2C_RDWR, &d) < 0) { perror("I2C_RDWR"); return -1; }
    return 0;
}

static int rd(unsigned reg) {
    unsigned char r = (unsigned char)reg, v = 0;
    struct i2c_msg m[2] = { { ADDR, 0, 1, &r }, { ADDR, I2C_M_RD, 1, &v } };
    struct i2c_rdwr_ioctl_data d = { m, 2 };
    if (!go) return 0;
    if (ioctl(fd, I2C_RDWR, &d) < 0) { perror("I2C_RDWR rd"); return -1; }
    return v;
}
static int stop_seq(void) {           /* identical to stone-main stop (7 writes) */
    puts("STOP");
    return wr(0x02, 0xC0) | wr(0x1F, 0) | wr(0x1E, 0) | wr(0x2F, 0) | wr(0x2E, 0)
         | wr(0x10, 0x90) | wr(0x20, 0x90);
}

int main(int argc, char **argv) {
    const char *bus = "/dev/i2c-1";
    int i = 1;
    for (; i < argc && argv[i][0] == '-'; i++) {
        if (!strcmp(argv[i], "--go")) go = 1;
        else if (!strcmp(argv[i], "--bus") && i + 1 < argc) bus = argv[++i];
        else { fprintf(stderr, "bad opt %s\n", argv[i]); return 2; }
    }
    if (i >= argc) { fprintf(stderr, "usage: see source header\n"); return 2; }
    if (go) {
        fd = open(bus, O_RDWR);
        if (fd < 0) { perror(bus); return 1; }
    } else puts("# DRY RUN (add --go to write)");

    if (!strcmp(argv[i], "stop")) return stop_seq() ? 1 : 0;
    if (!strcmp(argv[i], "count")) {   /* pulseRecord A=tilt 0x1E/1F, B=pan 0x2E/2F (LE) */
        int a0 = rd(0x1E), a1 = rd(0x1F), b0 = rd(0x2E), b1 = rd(0x2F);
        if (a0 < 0 || a1 < 0 || b0 < 0 || b1 < 0) return 1;
        printf("COUNT tilt=%d pan=%d\n", a0 | (a1 << 8), b0 | (b1 << 8));
        return 0;
    }
    int nowait = 0;
    if (!strcmp(argv[i], "start")) { nowait = 1; i++; }
    if (argc - i < 3) { fprintf(stderr, "need <pan|tilt> <dir> <qsteps>\n"); return 2; }
    int pan = !strcmp(argv[i], "pan");
    if (!pan && strcmp(argv[i], "tilt")) { fprintf(stderr, "axis pan|tilt\n"); return 2; }
    unsigned dir = atoi(argv[i + 1]) & 1;
    long q = atol(argv[i + 2]);
    long pps = argc - i > 3 ? atol(argv[i + 3]) : 1500;
    long hold = argc - i > 4 ? atol(argv[i + 4]) : -1;
    if (q < 1 || q > 8000) { fprintf(stderr, "qsteps 1..8000 (full travel cap)\n"); return 2; }
    if (pps < 200 || pps > 1500) { fprintf(stderr, "pps 200..1500\n"); return 2; }
    unsigned freq = FCLK / (pps * 16);
    if (freq < 127) freq = 127;
    if (hold < 0) hold = q * 1000 / pps + 200;   /* chip stops by itself after q; stop is a backstop */

    unsigned base = pan ? 0x20 : 0x10;          /* B = pan (8000 range), A = tilt (2300 range) */
    unsigned clr2 = pan ? 0x80 : 0x40;           /* reg2 after clearing own forceStop bit (assumes prior stop left 0xC0) */
    unsigned load = pan ? 0x40 : 0x80;           /* reg1 confLoad bit */
    printf("START %s dir=%u qsteps=%ld freq=0x%04x hold=%ldms\n", pan ? "pan(B)" : "tilt(A)", dir, q, freq, hold);
    int r = wr(base, 0xD0)                       /* motorType=5wire, pdEN=1, lowDivLevel=1 */
          | wr(0x02, clr2)
          | wr(base, 0xD0)
          | wr(base + 1, 0x88 | dir)             /* msMode=full step, forceStopPos=10, dir */
          | wr(base + 2, freq & 0xff) | wr(base + 3, freq >> 8)
          | wr(base + 4, q & 0xff) | wr(base + 5, (q >> 8) & 0xff)
          | wr(0x01, load);
    if (r) { stop_seq(); return 1; }
    if (nowait) return 0;            /* start only: chip runs until pulse count or stop */
    if (go) usleep(hold * 1000);
    return stop_seq() ? 1 : 0;
}
