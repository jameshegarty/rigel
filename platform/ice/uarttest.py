import serial
import sys

print("usage: test.py inputfile.raw outputfile.raw")

print("infile:"+sys.argv[1])
print("outfile:"+sys.argv[2])

infile = open(sys.argv[1],"rb")
outfile = open(sys.argv[2],"wb")

indata = infile.read()
print("infile len: ",len(indata))

ser = serial.Serial("/dev/tty.usbserial-141B",115200)
ser.write(indata)
res = ser.read(len(indata))
#print(x)
outfile.write(res)
ser.close()

infile.close()
outfile.close()
