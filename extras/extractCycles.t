cstdio = terralib.includec("stdio.h")

terra extractCycles(infile : &int8)
  var imgIn = cstdio.fopen(infile, "rb");
  cstdio.fseek(imgIn, -4, cstdio.SEEK_END);
  var cycles : uint32
  cstdio.fread(&cycles,4,1,imgIn)
  cstdio.printf("%d",cycles)
  cstdio.fclose(imgIn)
end

extractCycles(arg[1])