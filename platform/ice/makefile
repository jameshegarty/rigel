all: out/uarttest.bin

clean:
	rm out/*

out/%.blif: %.v
	yosys -q -p 'synth_ice40 -top main -blif $@' $<

out/%_pnr.txt: out/%.blif
	arachne-pnr -q -d 1k -o $@ -p ice40.pcf $<

out/%.bin: out/%_pnr.txt
	icepack $< $@

%.run: out/%.bin
	sudo kextunload -b com.apple.driver.AppleUSBFTDI
	iceprog $<
	sudo kextload -b com.apple.driver.AppleUSBFTDI
#	screen /dev/tty.usbserial-141B 115200