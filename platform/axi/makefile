all: processimage processimage_mpsoc

processimage:  processimage.c
	arm-linux-gnueabi-gcc -std=c99  $< -o $@

processimage_mpsoc:  processimage.c
	aarch64-linux-gnu-gcc -std=c99  $< -o $@

clean:
	rm processimage processimage_mpsoc
