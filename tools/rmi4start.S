/* rmi4start.S — 裸静态 ELF 入口：从初始栈取 argc/argv 传给 main */
	.text
	.globl _start
	.type _start, %function
_start:
	mov x0, sp
	ldr x0, [x0]		/* argc = *(sp)   */
	add x1, sp, #8		/* argv = sp + 8  */
	b main
