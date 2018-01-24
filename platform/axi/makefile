all: processimage

%:  %.c
	aarch64-linux-gnu-gcc -std=c99  $< -o $@

clean:
	rm processimage
