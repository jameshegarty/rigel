all: processimage

%:  %.c
	arm-linux-gnueabi-gcc -std=c99  $< -o $@

clean:
	rm processimage
