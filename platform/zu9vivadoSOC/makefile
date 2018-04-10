all: processimage_mpsoc_SOC

processimage_mpsoc_SOC:  processimage_mpsoc_SOC.c
	aarch64-linux-gnu-gcc -std=c99  $< -o $@

clean:
	rm processimage_mpsoc_SOC
