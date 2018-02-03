all: lsdump86

lsdump86: lsdump86.c libx64_static.a
	gcc lsdump86.c libx64_static.a -o lsdump86
	
libx64_static.a: libx64.asm
	fasm libx64.asm libx64.o
	ar rc libx64_static.a libx64.o
	ranlib libx64_static.a
	
clean:
	rm *.a -f
	rm *.o -f
	rm lsdump86 -f
