local cstdio = terralib.includec("stdio.h")
local cstdlib = terralib.includec("stdlib.h")

terra upToNearestTerra(roundto : int,x: int)
  if x % roundto == 0 or roundto==0 then return x end
  
  var ox : int
  if x < 0 then
    ox = x - (x%roundto)
  else
    ox = x + (roundto-x%roundto)
  end

  return ox
end


terra downToNearestTerra(roundto:int,x:int)
  if x % roundto == 0 or roundto == 0 then return x end

  var ox :int
  if x < 0 then
    ox = x - (roundto+x%roundto)
  else
    ox = x - x%roundto
  end

  return ox
end

local Ctmp = terralib.includecstring [[
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <inttypes.h>

  double CurrentTimeInSeconds() {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return tv.tv_sec + tv.tv_usec / 1000000.0;
                                 }

                                   ]]

--darkroom.currentTimeInSeconds = Ctmp.CurrentTimeInSeconds

terra orionAssert(cond : bool, str : &int8)
  if cond==false then
    cstdio.printf("ASSERT fail %s\n", str)
    cstdlib.exit(1)
  end
end
darkroomAssert = orionAssert

-- a % b
-- stupid C mod doesn't treat negative numbers as you'd hope
terra fixedModulus(a : int,b : int)
  while a < 0 do a = a+b end
  return a % b
end

-- a/b
-- makes it floor 'correctly' with negative numbers:
-- (usual integer divide rounds down for positive numbers, up for negative numbers)
-- -7/7 = -1, -3/7=-1, -8/7 = -2
-- assumes b is positive
terra floorDivide(a : int, b: int)
  return terralib.select(a<0, (a-b+1)/b, a/b)
end

function andopterra(a,b) return `a and b end
terra xor( a:bool, b:bool) return (a or b) and (not (a and b)) end
