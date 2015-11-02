function downsample(scaleX,scaleY,w,h)
  local r ={}
  for y=0,h-1 do
    for x=0,w-1 do
      table.insert(r,x%scaleX==0 and y%scaleY==0)
    end
  end
  return r
end

-- depth: total # of levels
-- chosenDepth: which pyramid level do we want to collect stats for? (0 indexed)
-- topW: width of the top level of the pyramid
function pyramid(depth,chosenDepth,topW,H)
  local r = {}
  for y=0,H-1 do
    for d=0,depth-1 do
      local W = topW/math.pow(4,d)
      for x=0,W-1 do
        table.insert(r,d==chosenDepth)
      end
    end
  end

  return r
end

-- reads every T cycles
function standard(T, length)
  local expectedOutput = length*T
  assert(expectedOutput == math.floor(expectedOutput))

  local t = {}
  local outputsSoFar = 0
  for i = 0, length-1 do
--    table.insert(t, i%T==0)
    if outputsSoFar<(i+1)*T then
      table.insert(t,true)
      outputsSoFar = outputsSoFar + 1
    else
      table.insert(t,false)
    end
  end
  print(outputsSoFar,expectedOutput,"length",length)
  assert(outputsSoFar==expectedOutput)
  return t
end

function display(tab)
  assert(type(tab)=="table")
  local r = {}
  for i=1,#tab do if tab[i] then table.insert(r,"A") else table.insert(r,"X") end end
  print(table.concat(r,""))
end

function simulate(produce,consume)
  assert(#produce==#consume)
  local fifoSize = 0
  local maxFifoSize = 0
  local minFifoSize = 0

  for i=1,#produce do
    if produce[i] then fifoSize = fifoSize+1 end
    if consume[i] then fifoSize = fifoSize-1 end
    if fifoSize>maxFifoSize then maxFifoSize = fifoSize end
    if fifoSize<minFifoSize then minFifoSize = fifoSize end
  end

  assert(fifoSize==0) -- this has better be true at the end

  print("Max Fifo Size",maxFifoSize)
  print("Min Fifo Size",minFifoSize)
end

local W,H = 128, 4

--local p = downsample(2,2,W,H)
local totalW = W+(W/4)+(W/16)+(W/64)
print("tw/w",totalW/W)
local p = standard((W/64)/totalW,totalW*H)
display(p)
--local c = standard(4,W*H)
local c = pyramid(4,3,W,H)
display(c)

simulate(p,c)
