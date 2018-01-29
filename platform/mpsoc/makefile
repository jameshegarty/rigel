all: processimage_mpsoc

processimage_mpsoc:  processimage_mpsoc.c
	aarch64-linux-gnu-gcc -std=c99  $< -o $@

clean:
	rm processimage_mpsoc
