all: out/conv out/conv.data out/conv.correct.txt

clean:
	rm out/*

out/conv: conv.cpp
	g++ conv.cpp -o out/conv

out/conv.data: conv
	out/conv ../examples/1080p.raw out/conv.data

out/conv.correct.txt: out/conv.data
	diff out/conv.data gold/conv.data > out/conv.diff
	test ! -s out/conv.diff && touch out/conv.correct.txt
