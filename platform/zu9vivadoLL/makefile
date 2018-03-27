all: processimage_mpsoc_LL

processimage_mpsoc_LL:  processimage_mpsoc_LL.c
	aarch64-linux-gnu-gcc -std=c99  $< -o $@

clean:
	rm processimage_mpsoc_LL
