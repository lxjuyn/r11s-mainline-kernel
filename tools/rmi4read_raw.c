/* rmi4read_raw.c — 零 libc 依赖（裸 aarch64 syscall），静态链接。
 * 只读 RMI4 任意地址：用法: rmi4read_raw <hex_addr> <dec_len>
 * 写页选 0 + I2C_RDWR 读。逐字节读 + 一次性块读对照。
 */
#define SYS_openat 56
#define SYS_ioctl 29
#define SYS_write 64
#define SYS_exit 93

#define AT_FDCWD -100
#define O_RDWR 2
#define I2C_SLAVE_FORCE 0x0706
#define I2C_RDWR 0x0707
#define I2C_M_RD 1

struct i2c_msg { unsigned short addr, flags, len; unsigned char *buf; };
struct i2c_rdwr_ioctl_data { struct i2c_msg *msgs; unsigned int nmsgs; };

static long sc4(long n, long a, long b, long c, long d)
{
	register long x8 __asm__("x8") = n;
	register long x0 __asm__("x0") = a;
	register long x1 __asm__("x1") = b;
	register long x2 __asm__("x2") = c;
	register long x3 __asm__("x3") = d;
	__asm__ volatile("svc 0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3) : "memory");
	return x0;
}
static void exit_(int c) { sc4(SYS_exit, c, 0, 0, 0); __builtin_unreachable(); }
static int open_(const char *p, int f) { return sc4(SYS_openat, AT_FDCWD, (long)p, f, 0); }
static long ioctl_(int fd, long r, void *a) { return sc4(SYS_ioctl, fd, r, (long)a, 0); }
static void write_(const char *b, long n) { sc4(SYS_write, 1, (long)b, n, 0); }

static int slen(const char *s) { int n = 0; while (s[n]) n++; return n; }
static void puts_(const char *s) { write_(s, slen(s)); }
static void puth(unsigned char v)
{
	char b[2] = { "0123456789abcdef"[v >> 4], "0123456789abcdef"[v & 15] };
	write_(b, 2);
}
static void putd(long v)
{
	char b[24]; int i = 0;
	if (v < 0) { write_("-", 1); v = -v; }
	do { b[i++] = '0' + v % 10; v /= 10; } while (v);
	while (i) write_(&b[--i], 1);
}
static void printc(unsigned char c) { write_((const char *)&c, 1); }

static int hexv(char c)
{
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}
static int parsehex(const char *s, long *out)
{
	long v = 0; int n = 0;
	while (*s) { int d = hexv(*s); if (d < 0) return -1; v = v * 16 + d; s++; n++; }
	if (!n) return -1;
	*out = v; return 0;
}
static int parsedec(const char *s, long *out)
{
	long v = 0; int n = 0;
	while (*s >= '0' && *s <= '9') { v = v * 10 + (*s - '0'); s++; n++; }
	if (!n || *s) return -1;
	*out = v; return 0;
}

static int fd;
static unsigned int dev_addr = 0x20;
static unsigned char off;
static long last_err;

static int rread(unsigned char o, unsigned char *buf, int n)
{
	struct i2c_msg m[2]; struct i2c_rdwr_ioctl_data d;
	off = o;
	m[0].addr = dev_addr; m[0].flags = 0; m[0].len = 1; m[0].buf = &off;
	m[1].addr = dev_addr; m[1].flags = I2C_M_RD; m[1].len = n; m[1].buf = buf;
	d.msgs = m; d.nmsgs = 2;
	long r = ioctl_(fd, I2C_RDWR, &d);
	last_err = r;
	return r == 2 ? 0 : -1;
}

int main(int argc, char **argv);

int main(int argc, char **argv)
{
	unsigned char buf[64];
	unsigned char pg[2] = { 0xff, 0 };
	struct i2c_msg m; struct i2c_rdwr_ioctl_data d;
	long addr = -1, len = 0, a, i, rc;

	if (argc != 3 || parsehex(argv[1], &addr) || parsedec(argv[2], &len) ||
	    addr < 0 || addr > 0xff || len < 1 || len > 64) {
		puts_("USAGE rmi4read_raw <hex_addr> <dec_len1-64>\n");
		exit_(2);
	}

	fd = open_("/dev/i2c-0", O_RDWR);
	if (fd < 0) { puts_("OPENFAIL\n"); exit_(1); }
	if (ioctl_(fd, I2C_SLAVE_FORCE, (void *)(long)dev_addr) < 0) { puts_("SLAVEFAIL\n"); exit_(1); }

	m.addr = dev_addr; m.flags = 0; m.len = 2; m.buf = pg;
	d.msgs = &m; d.nmsgs = 1;
	if (ioctl_(fd, I2C_RDWR, &d) != 1) { puts_("PAGESET FAIL\n"); exit_(1); }

	/* 逐字节读 */
	puts_("B1 "); puth(addr); puts_(": ");
	for (a = addr; a < addr + len && a <= 0xff; a++) {
		buf[0] = 0xAA;
		rc = rread(a, buf, 1);
		if (rc) { puts_("ERR"); putd(last_err); printc(' '); }
		else { puth(buf[0]); printc(' '); }
	}
	printc('\n');

	/* 一次性块读（与内核 rmi_i2c_read_block 同形状） */
	puts_("BL "); puth(addr); puts_("x"); putd(len); puts_(": ");
	for (i = 0; i < len; i++) buf[i] = 0xAA;
	rc = rread(addr, buf, len);
	if (rc) { puts_("ERR"); putd(last_err); }
	else for (i = 0; i < len; i++) { puth(buf[i]); printc(' '); }
	printc('\n');

	puts_("END\n");
	exit_(0);
}
