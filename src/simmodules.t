local M = {}

function M.fifo( T, reqMaxSize )
  assert(terralib.types.istype(T))
  assert(type(reqMaxSize)=="number")
  local maxSize = reqMaxSize + 1 -- if we alloc reqMaxSize, we can't distinguish between empty and full

  local struct FIFO {
    data : T[maxSize];
    frontAddr : int; -- always >=0
    backAddr : int; -- always >=0
  }

  terra FIFO:reset()
    self.frontAddr = 0
    self.backAddr = 0
  end

  terra FIFO:pushBack( inp : &T ) 
    self.data[self.backAddr % maxSize] = @inp
    self.backAddr = self.backAddr + 1
  end

  -- expects idx <=0
  -- idx=0 is the thing that was most recently pushBack'ed
  terra FIFO:peekBack( idx : int ) : &T
    return &self.data[(self.backAddr+idx-1) % maxSize]
  end

  terra FIFO:popFront() : &T
    var cur = &self.data[self.frontAddr % maxSize]
    self.frontAddr = self.frontAddr + 1
    return cur
  end

  terra FIFO:hasData() return self.backAddr > self.frontAddr end
  terra FIFO:size() return self.backAddr-self.frontAddr end

  return FIFO
end

function M.shiftRegister( T, size )
  local FIFO = M.fifo( T, size )
  local struct SR { fifo : FIFO }
  terra SR:init() self.fifo:init() end
  terra SR:pushBack( inp : &T )
    self.fifo:pushBack(inp)
    if self.fifo:size()>size then self.fifo:popFront() end
  end
  -- these are the _newest_ things in the shift register
  -- idx=0 is the most recent thing pushBack'ed
  -- idx=-1 is the second most recent thing pushBack'ed
  terra SR:peekBack(idx:int) return self.fifo:peekBack(idx) end
  return SR
end

return M