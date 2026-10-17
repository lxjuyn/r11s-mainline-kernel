/* rmi4dump.c — 只读 RMI4 PDT 取证工具（静态编译，救援 shell 用）
 * 仅执行 I2C 读（写页选 0 + 读寄存器），不修改传感器配置。
 * 用法: rmi4dump [bus] [addr]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <linux/i2c-dev.h>
#include <linux/i2c.h>

static int fd;
static unsigned char dev_addr;

/* write offset, read n bytes (与内核 rmi_i2c_read_block 相同事务形状) */
static int rread(unsigned char off, unsigned char *buf, int n)
{
	struct i2c_msg msgs[2];
	struct i2c_rdwr_ioctl_data d;
	msgs[0].addr = dev_addr; msgs[0].flags = 0;
	msgs[0].len = 1; msgs[0].buf = &off;
	msgs[1].addr = dev_addr; msgs[1].flags = I2C_M_RD;
	msgs[1].len = n; msgs[1].buf = buf;
	d.msgs = msgs; d.nmsgs = 2;
	if (ioctl(fd, I2C_RDWR, &d) != 2)
		return -errno;
	return 0;
}

static int wpage(unsigned char page)
{
	struct i2c_msg m;
	struct i2c_rdwr_ioctl_data d;
	unsigned char b[2] = { 0xff, page };
	m.addr = dev_addr; m.flags = 0; m.len = 2; m.buf = b;
	d.msgs = &m; d.nmsgs = 1;
	if (ioctl(fd, I2C_RDWR, &d) != 1)
		return -errno;
	return 0;
}

int main(int argc, char **argv)
{
	char path[32];
	unsigned char buf[6];
	int a, rc;
	int bus = argc > 1 ? atoi(argv[1]) : 0;
	unsigned long addr = argc > 2 ? strtoul(argv[2], 0, 0) : 0x20;

	snprintf(path, sizeof(path), "/dev/i2c-%d", bus);
	fd = open(path, O_RDWR);
	if (fd < 0) { perror("open"); return 1; }
	dev_addr = (unsigned char)addr;
	if (ioctl(fd, I2C_SLAVE_FORCE, dev_addr) < 0) { perror("slave"); return 1; }

	if (wpage(0)) { printf("PAGESET FAIL %d\n", errno); return 1; }
	printf("PDT page0:\n");
	for (a = 0xe9; a > 0x00; a -= 6) {
		memset(buf, 0xAA, 6);
		rc = rread((unsigned char)a, buf, 6);
		printf("%02x: rc=%d %02x %02x %02x %02x %02x %02x\n",
		       a, rc, buf[0], buf[1], buf[2], buf[3], buf[4], buf[5]);
		if (buf[5] == 0x00 || buf[5] == 0xff)
			break;
	}
	printf("PROPS@EF: "); memset(buf, 0xAA, 1);
	rc = rread(0xef, buf, 1); printf("rc=%d %02x\n", rc, buf[0]);
	printf("BSR@FE: "); memset(buf, 0xAA, 1);
	rc = rread(0xfe, buf, 1); printf("rc=%d %02x\n", rc, buf[0]);
	printf("PAGESEL@FF: "); memset(buf, 0xAA, 1);
	rc = rread(0xff, buf, 1); printf("rc=%d %02x\n", rc, buf[0]);
	/* F01 query 区：0xd0-0xef 常见产品 ID 位置粗扫 */
	printf("LOWBLOCK 0xc0..0xcf:\n");
	for (a = 0xc0; a <= 0xcc; a += 6) {
		memset(buf, 0xAA, 6);
		rc = rread((unsigned char)a, buf, 6);
		printf("%02x: rc=%d %02x %02x %02x %02x %02x %02x |%c%c%c%c%c%c|\n",
		       a, rc, buf[0], buf[1], buf[2], buf[3], buf[4], buf[5],
		       (buf[0] >= 32 && buf[0] < 127) ? buf[0] : '.',
		       (buf[1] >= 32 && buf[1] < 127) ? buf[1] : '.',
		       (buf[2] >= 32 && buf[2] < 127) ? buf[2] : '.',
		       (buf[3] >= 32 && buf[3] < 127) ? buf[3] : '.',
		       (buf[4] >= 32 && buf[4] < 127) ? buf[4] : '.',
		       (buf[5] >= 32 && buf[5] < 127) ? buf[5] : '.');
	}
	printf("END\n");
	return 0;
}
