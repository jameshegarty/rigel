all: out/conv out/conv.data out/conv.correct.txt out/stereo out/stereo.data out/stereo.correct.txt

clean:
	rm out/*

out/conv: conv.cpp
	g++ conv.cpp -o out/conv

out/conv.data: conv
	out/conv ../examples/1080p.raw out/conv.data

out/conv.correct.txt: out/conv.data
	diff out/conv.data gold/conv.data > out/conv.diff
	test ! -s out/conv.diff && touch out/conv.correct.txt

out/stereo: stereo.cpp
	g++ stereo.cpp -o out/stereo

out/stereo.data: stereo
	out/stereo ../examples/stereo0000.raw out/stereo.data

out/stereo.correct.txt: out/stereo.data
	diff out/stereo.data gold/stereo.data > out/stereo.diff
	test ! -s out/stereo.diff && touch out/stereo.correct.txt
