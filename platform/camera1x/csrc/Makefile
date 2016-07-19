CC = arm-linux-gnueabi-gcc
CFLAGS = -std=c99
DEPS = processimagelib.h
OBJ = processimage.o processimagelib.o

all: processimage clean

%.o: %.c $(DEPS)
	$(CC) $(CFLAGS) -c -o $@ $<

processimage: $(OBJ)
	$(CC) $(CFLAGS) -o $@ $^
	
clean:
	-rm *.o
