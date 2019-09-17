all: processimage

processimage:  ../axi/processimage.c
	arm-linux-gnueabihf-gcc -std=c99  ../axi/processimage.c -o processimage

clean:
	rm processimage
