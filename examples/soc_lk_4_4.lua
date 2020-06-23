local R = require "rigel"
local T = require "types"
local types = T
local RM = require "generators.modules"
local C = require "generators.examplescommon"
local G = require "generators.core"
local SOC = require "generators.soc"
local SDF = require "sdf"
local Zynq = require "generators.zynq"
local J = require "common"
local harness = require "generators.harnessSOC"
local P = require "params"

local f = require "fixed"

local AUTOFIFO = string.find(arg[0],"autofifo")
AUTOFIFO = (AUTOFIFO~=nil)

if AUTOFIFO then
  R.AUTO_FIFOS = true
  R.Z3_FIFOS = true
else
  R.AUTO_FIFOS = false
end

local first,flen = string.find(arg[0],"%d+")
local CONVWIDTH = tonumber(string.sub(arg[0],first,flen))
local V = tonumber(string.sub(arg[0], string.find(arg[0],"%d+",flen+1)))
local VORIG = V
V = V/CONVWIDTH

print("CONVWIDTH",CONVWIDTH,"V",V)

local bits = {
  inv22={15,26,0},
  inv22inp={5,5,0}, -- NOTICE THIS IS DIFFERENT THAN WINDOW=6 VERSION
--  d={0,0,0},
--  Apartial={0,0,0},
--  Bpartial={0,0,0},
--  solve={0,0,0}
}

local inputFilename = "trivial_64.raw"
local W,H = 64,64
if CONVWIDTH==6 then
  bits.inv22inp={0,10,0}
  inputFilename = "trivial_128.raw"
  W,H = 128,128
elseif CONVWIDTH==12 then
  bits.inv22inp={0,10,0}
  inputFilename = "packed_v0000.raw"
  W,H = 1920,1080
end

local outfile = "soc_lk_"..CONVWIDTH.."_"..(V*CONVWIDTH)..J.sel(AUTOFIFO,"_autofifo","")
io.output("out/"..outfile..".design.txt"); io.write("Lucas Kanade "..H.." "..CONVWIDTH.."x"..CONVWIDTH); io.close()
io.output("out/"..outfile..".designT.txt"); io.write(V); io.close()
io.output("out/"..outfile..".dataset.txt"); io.write("SIG20_zu9"..J.sel(AUTOFIFO,"_autofifo","")); io.close()

local PadRadius = CONVWIDTH/2
local PadRadiusAligned = PadRadius
if V>1 then
  PadRadiusAligned = J.upToNearest(V,CONVWIDTH/2)
end

local PadExtra = PadRadiusAligned - PadRadius

local cycles = ((W+PadRadiusAligned*2)*(H+PadRadius*2+1))/V

if CONVWIDTH==4 and V==(1/4) then
--  cycles = cycles - 1
elseif CONVWIDTH==12 and V==(3/12) then
--  cycles = cycles - 1
end

print("CYCLES",cycles)

local regs = SOC.axiRegs({},SDF{1,cycles}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}} ):instantiate("ZynqNOC")
noc.extern=true

local FIFOSIZE = 128
      

--local Fdenom = G.SchedulableFunction{"Fdenom", T.Array2d(P.NumberType("ty"),4),true,
local Fdenom = G.Fmap{G.Function{"Fdenom", T.rv(T.Array2d(types.Int(20,-2),4)),
  function(i)
    print("FDENOM",i.type)
--    local iFO = G.FanOut{4}(i)
    local lhs = G.MulE(i[0],i[3])
    local rhs = G.MulE(i[1],i[2])
    local fdenom = G.SubE(lhs,rhs)

    fdenom = G.RemoveMSBs{bits.inv22inp[1]}(fdenom)
    fdenom = G.RemoveLSBsE{bits.inv22inp[2]}(fdenom)
    print("FDENOMOUT",fdenom.type)
    return fdenom
end}}

--local Fout = G.SchedulableFunction{"Fout", T.tuple{T.array2d(P.NumberType("AType"),4), P.NumberType("fdet_type")},
local Fout = G.Fmap{G.Function{"Fout", T.rv(T.tuple{T.array2d(T.Int(20,-2),4), T.Int(40,-35-bits.inv22inp[2])}),
  function(i)
    print("FOUT",i.type)
    local fmatrix = G.FanOut{4}(i[0])
    local i0 = G.NAUTOFIFO{128}(fmatrix[0][0])
    local i1 = G.NAUTOFIFO{128}(fmatrix[1][1])
    local i2 = G.NAUTOFIFO{128}(fmatrix[2][2])
    local i3 = G.NAUTOFIFO{128}(fmatrix[3][3])
    local fdet = G.FanOut{4}(i[1])

    local OT = {G.MulE(G.NAUTOFIFO{128}(fdet[0]),i3),
                G.MulE(G.Neg(G.NAUTOFIFO{128}(fdet[1])),i1),
                G.MulE(G.Neg(G.NAUTOFIFO{128}(fdet[2])),i2),
                G.MulE(G.NAUTOFIFO{128}(fdet[3]),i0)}

    for k,v in pairs(OT) do
      OT[k] = G.RemoveMSBs{bits.inv22[1]}(OT[k])
      OT[k] = G.RemoveLSBsE{bits.inv22[2]}(OT[k])
    end
    
    return G.TupleToArray(unpack(OT))
end}}

--local Invert2x2 = G.SchedulableFunction{"Invert2x2", T.Array2d(P.NumberType("A"),4),
local Invert2x2 = G.Function{"Invert2x2", T.rv(T.Array2d(T.int(20,-2),4)),SDF{1,1},
  function(i)
--    i = G.Map{G.AddMSBs{12}}(i)
--    print("i",i.type,i.rate,i.type:deSchedule():verilogBits()/8)
    --    i = G.FwritePGM{"out/"..outfile..".invert2x2.pgm",{134,135}}(i)
--    i = RM.shiftRegister(i.type:deInterface(),1)(i)
--    i = G.Map{G.RemoveMSBs{12}}(i)

    print("INV",i.type)
    local iFO = G.FanOut{2}(i)
    local denom = Fdenom( G.NAUTOFIFO{128}(iFO[0]) )
    print("DENOM.ty",denom.type)
    local det = G.Fmap{C.lutinvert(denom.type:deInterface())}(denom)
    local res = Fout( G.NAUTOFIFO{128}(iFO[1]), det )
    return res
end}

--print(Invert2x2)

--local Dx = G.SchedulableFunction{"Dx",T.Array2d(T.Uint(8),3),
local Dx = G.Fmap{G.Function{"Dx", T.rv(T.Array2d(T.Uint(8),3)),
  function(i)
    local iFO = G.FanOut{2}(i)
    local outl = G.UtoI(G.AddMSBs{1}(iFO[0][2]))
    local outr = G.UtoI(G.AddMSBs{1}(iFO[1][0]))
    local outt = G.SubE(outl,outr)
    local out = G.RshiftE{1}(outt)
    return out
end}}

--local Dy = G.SchedulableFunction{"Dy", types.array2d(types.uint(8),1,3),
local Dy = G.Fmap{G.Function{"Dy", T.rv(types.array2d(types.uint(8),1,3)),
  function(i)
    local iFO = G.FanOut{2}(i)
    local outl = G.UtoI(G.AddMSBs{1}(G.Index{{0,2}}(iFO[0])))
    local outr = G.UtoI(G.AddMSBs{1}(G.Index{{0,0}}(iFO[1])))
    local outt = G.SubE(outl,outr)
    return G.RshiftE{1}(outt)
end}}

local CalcA = G.SchedulableFunction{"CalcA",
  types.tuple{ types.array2d( P.NumberType("ty"), P.SizeValue("sz")),
               types.array2d( P.NumberType("ty"), P.SizeValue("sz")) },
  function(inp)
    print("CALCA",inp.type,inp.rate)
    local inpFO = G.FanOut{2}(inp)
    
    --local Fdx = G.NAUTOFIFO{1}
    local Fdx = inpFO[0][0]
    local FdxFO = G.FanOut{3}(Fdx)
    --local Fdy = G.NAUTOFIFO{1}()
    local Fdy = inpFO[1][1]
    local FdyFO = G.FanOut{3}(Fdy)

    local inp0 = G.Zip(G.NAUTOFIFO{1}(FdxFO[0]),G.NAUTOFIFO{1}(FdxFO[1]))
    local out0 = G.Map{G.MulE}(inp0)
    
    out0 = G.Reduce{G.Add{R.Async}}(out0)
--    out0 = G.FIFO{1}(out0)
    
    local inp1 = G.Zip(G.NAUTOFIFO{1}(FdxFO[2]),G.NAUTOFIFO{1}(FdyFO[0]))
    local out1 = G.Map{G.MulE}(inp1)
    out1 = G.Reduce{G.Add{R.Async}}(out1)
--    out1 = G.FIFO{1}(out1)
    
    --local out2 = out1
    local out1FO = G.FanOut{2}(out1)
    
    local inp3 = G.Zip(G.NAUTOFIFO{8}(FdyFO[1]),G.NAUTOFIFO{8}(FdyFO[2]))
    local out3 = G.Map{G.MulE}(inp3)
    out3 = G.Reduce{G.Add{R.Async}}(out3)
--    out3 = G.FIFO{1}(out3)
    
    local out = R.concat{G.NAUTOFIFO{1}(out0),G.NAUTOFIFO{1}(out1FO[0]),G.NAUTOFIFO{1}(out1FO[1]),G.NAUTOFIFO{1}(out3)}
    
    return G.TupleToArray(G.FanIn(out))
  end}

local Minus = G.SchedulableFunction{"Minus",T.Tuple{P.NumberType("A"),P.NumberType("A")},
  function(i)
    assert( i.type:deInterface().list[1]==i.type:deInterface().list[2] )
    local lhs = G.UtoI(G.AddMSBs{1}(i[0]))
    local rhs = G.UtoI(G.AddMSBs{1}(i[1]))
    return G.SubE(lhs,rhs)
  end}

local CalcB = G.SchedulableFunction{"CalcB",
  T.Tuple{ T.Array2d(T.U8,P.SizeValue("w")), T.Array2d(T.U8,P.SizeValue("w")),
           T.Array2d(P.NumberType("ty"),P.SizeValue("w")),
           T.Array2d(P.NumberType("ty"),P.SizeValue("w")) },
  function(i)                              
    print("CALCB",i.type,i.rate)
    local iFO = G.FanOut{4}(i)
    local frame0 = G.NAUTOFIFO{FIFOSIZE}(iFO[0][0])
    local frame1 = G.NAUTOFIFO{FIFOSIZE}(iFO[1][1])
    local Fdx = G.NAUTOFIFO{FIFOSIZE}(iFO[2][2])
    local Fdy = G.NAUTOFIFO{FIFOSIZE}(iFO[3][3])

    ---------
    local gmf = R.concat("mfgmf",{frame1,frame0}):setName("gmf")
    gmf = G.Zip(gmf):setName("gmf_zip")
    gmf = G.Map{Minus}(gmf)
    gmf = G.NAUTOFIFO{FIFOSIZE}(gmf)
    local gmfFO = G.FanOut{2}(gmf)
    ---------

    Fdx = G.NAUTOFIFO{1}(Fdx)
    local gmf0 = G.NAUTOFIFO{1}(gmfFO[0]):setName("gmf0")
    
    local out_0 = R.concat("o0tup",{Fdx, gmf0 }):setName("out_0_concat")
    out_0 = G.Zip(out_0):setName("out_0_zip")
    out_0 = G.Map{G.MulE}(out_0)
    out_0 = G.Reduce{G.Add{R.Async}}(out_0)
--    out_0 = G.FIFO{1}(out_0)
                      
    Fdy = G.NAUTOFIFO{1}(Fdy)
    local gmf1 = G.NAUTOFIFO{1}(gmfFO[1])
    
    local out_1 = R.concat("o1tup",{Fdy, gmf1 }):setName("out_1_concat")
    out_1 = G.Zip(out_1)
    out_1 = G.Map{G.MulE}(out_1)
    out_1 = G.Reduce{G.Add{R.Async}}(out_1)
--    out_1 = G.FIFO{1}(out_1)
    
    local out = G.FanIn(out_0,out_1)
    out = G.TupleToArray(out)
    
    return out
end}

--local Solve = G.SchedulableFunction{"Solve", T.Tuple{T.Array2d(P.NumberType("AinvType"),4),T.Array2d(P.NumberType("btype"),2)},
local Solve = G.Fmap{G.Function{"Solve", T.rv(T.Tuple{T.Array2d(T.Int(19,-11-bits.inv22inp[2]),4),T.Array2d(T.Int(20,-1),2)}),
  function(i)
    print("SOLVE",i.type)
    local iFO = G.FanOut{2}(i)
    local Ainv = G.FanOut{4}(iFO[0][0])
    local b = G.FanOut{2}(iFO[1][1])
    local b0, b1 = b[0][0], b[1][1]
    b0 = G.FanOut{2}(G.Neg(b0))
    b1 = G.FanOut{2}(G.Neg(b1))
    local Ainv0, Ainv1, Ainv2, Ainv3 = G.NAUTOFIFO{128}(Ainv[0][0]), G.NAUTOFIFO{128}(Ainv[1][1]), G.NAUTOFIFO{128}(Ainv[2][2]), G.NAUTOFIFO{128}(Ainv[3][3])

    local out_0_lhs = G.MulE( G.NAUTOFIFO{128}(Ainv0), G.NAUTOFIFO{128}(b0[0]) )
    local out_0_rhs = G.MulE( G.NAUTOFIFO{128}(Ainv1), G.NAUTOFIFO{128}(b1[0]) )
    local out_0 = G.AddE( out_0_lhs, out_0_rhs )
    
    local out_1_lhs = G.MulE( G.NAUTOFIFO{128}(Ainv2), G.NAUTOFIFO{128}(b0[1]) )
    local out_1_rhs = G.MulE( G.NAUTOFIFO{128}(Ainv3), G.NAUTOFIFO{128}(b1[1]) )
    local out_1 = G.AddE(out_1_lhs,out_1_rhs)
    
    return G.TupleToArray(out_0,out_1)
end}}

--local Display = G.SchedulableFunction{"Display", T.Array2d(P.NumberType("ity"),2),
local Display = G.Fmap{G.Function{"Display", T.rv(T.Array2d(T.Int(40,-12-bits.inv22inp[2]),2)),
  function(inp)
    print("DISPLAY",inp.type)
    local inpFO = G.FanOut{2}(inp)
    
    local out = {}
    for i=0,1 do
      local I = inpFO[i][i]
      local B = G.MulE{32}(I)

      local FF = G.AddE{128}(B)

      FF = G.Abs(FF)
      FF = G.ItoU(FF)

      local FF_den = G.Denormalize(FF)

      local FF_trunc = G.RemoveMSBs{FF_den.type:deInterface().precision-8}(FF_den)
      --J.err(FF_trunc.type:deInterface()==T.U8,"FF_trunc is:",FF_trunc.type,FF_trunc.scheduleConstraints)
      
      table.insert(out,FF_trunc)
    end

    local res = G.TupleToArray(unpack(out))

    return res
end}}

local LK = G.SchedulableFunction{"LK",types.Array2d(T.Tuple{types.uint(8),types.uint(8)},P.SizeValue("imsize")),
    function(inp)

      --inp = G.Map{G.FwritePGM{"out/"..outfile..".inp.raw"},true}(inp)
--      inp=G.FwritePGM{"out/"..outfile..".inp.pgm"}(inp)
      
      print("LKINP",inp.type,inp.rate)
      local inpFO = G.FanOut{2}(inp)
      
      local frame0 = G.Map{G.Index{0}}(G.NAUTOFIFO{FIFOSIZE}(inpFO[0]))
      local frame0FO = G.FanOut{2}(frame0)
      local frame0_0 = G.NAUTOFIFO{FIFOSIZE}(frame0FO[0])
      local frame0_1 = G.NAUTOFIFO{FIFOSIZE}(frame0FO[1])

      print("frame0_1",frame0_1.type,frame0_1.rate,frame0_1.scheduleConstraints, frame0_1.type:deSchedule():verilogBits()/8)
--      frame0_1 = G.Map{G.Fwrite{"out/"..outfile..".frame0_1.data"},true}(frame0_1)
      
      local frame1 = G.Map{G.Index{1}}(G.NAUTOFIFO{FIFOSIZE}(inpFO[1]))
      frame1 = G.NAUTOFIFO{FIFOSIZE}(frame1)
      
      local lb0 = G.Stencil{{-CONVWIDTH, 0, -CONVWIDTH, 0}}(frame0_0)
      
      local lb0_fd = G.Stencil{{-2, 0, -2, 0}}(frame0_1)

--      print("FDX_st",lb0_fd.type,lb0_fd.rate,lb0_fd.type:deSchedule():verilogBits()/8)
--      lb0_fd = G.FwritePGM{"out/"..outfile..".fdxst.pgm"}(lb0_fd)

      --      print("lb0fd",lb0_fd.type,lb0_fd.rate,lb0_fd.scheduleConstraints)
--      lb0_fd = G.Map{G.Fwrite{"out/"..outfile..".lb0fd.raw",R.Unoptimized},true,R.Unoptimized}(lb0_fd)

      local lb0_fd_FO = G.FanOut{2}(lb0_fd)
      local lb0_fd_0 = G.NAUTOFIFO{FIFOSIZE}(lb0_fd_FO[0])
      local lb0_fd_1 = G.NAUTOFIFO{FIFOSIZE}(lb0_fd_FO[1])


      local lb1 = G.Stencil{{-CONVWIDTH, 0, -CONVWIDTH, 0}}(frame1)
      
--      print("FDXI",lb0_fd_0.type,lb0_fd_0.rate)
      local fdx = G.Map{G.Slice{{0,2,1,1}}}(lb0_fd_0)

      if VORIG<CONVWIDTH then
        fdx = G.NAUTOFIFO{2}(fdx)
      end
      
--      print("FDXINP",fdx.type,fdx.rate,fdx.type:deSchedule():verilogBits()/2)
--      fdx = G.FwritePGM{"out/"..outfile..".fdxi.pgm"}(fdx)
      fdx = G.Map{Dx}(fdx)
      
--      fdx = G.Map{G.AddMSBs{6}}(fdx)
--      print("FDX",fdx.type,fdx.rate,fdx.type:deSchedule():verilogBits()/8)
--      fdx = G.FwritePGM{"out/"..outfile..".fdx.pgm"}(fdx)
--      fdx = G.Map{G.RemoveMSBs{6}}(fdx)
      
--      print("FDX",fdx.type,fdx.rate,fdx.scheduleConstraints)
      local fdx_stencil = G.Stencil{{-CONVWIDTH+1, 0, -CONVWIDTH+1, 0}}(fdx)

--      print("FDX_ST",fdx_stencil.type,fdx_stencil.rate,fdx_stencil.scheduleConstraints)
      
      local fdx_stencilFO = G.FanOut{2}(fdx_stencil)
      
      local fdy = G.Map{G.Slice{{1,1,0,2}}}(lb0_fd_1)

      if VORIG<CONVWIDTH then
        fdy = G.NAUTOFIFO{2}(fdy)
      end
      
      local fdy = G.Map{Dy}(fdy)
      
      local fdy_stencil = G.Stencil{{-CONVWIDTH+1, 0, -CONVWIDTH+1, 0}}(fdy)
      
      local fdy_stencilFO = G.FanOut{2}(fdy_stencil)
      
      local Ainpinp = R.concat{ G.NAUTOFIFO{FIFOSIZE}(fdx_stencilFO[0]), G.NAUTOFIFO{FIFOSIZE}(fdy_stencilFO[0]) }
      print("AINPINP",Ainpinp.type,Ainpinp.rate)
      local Ainp = G.Zip( Ainpinp  )
      local A = G.Map{CalcA}(Ainp)
      
--      A = G.Map{G.Map{G.AddMSBs{12}}}(A)
--      print("A",A.type,A.rate,A.type:deSchedule():verilogBits()/8)
--      A = G.FwritePGM{"out/"..outfile..".A.pgm"}(A)
--      A = G.Map{G.Map{G.RemoveMSBs{12}}}(A)

      print("AINVINP",A.type,A.rate)
      local Ainv = G.Map{Invert2x2}(A)
      Ainv = G.NAUTOFIFO{FIFOSIZE}(Ainv)
      
--      Ainv = G.Map{G.Map{G.AddMSBs{13}}}(Ainv)
--      print("AINV",Ainv.type,Ainv.rate,Ainv.type:deSchedule():verilogBits()/8)
--      Ainv = G.FwritePGM{"out/"..outfile..".Ainv.pgm"}(Ainv)
--      Ainv = G.Map{G.Map{G.RemoveMSBs{13}}}(Ainv)
      
--      local lb0FO2 = lb0FO[2]
--      print("F0SLICEINP",lb0FO2.type,lb0FO2.rate)
      local f0_slice = G.Map{G.Slice{{0, CONVWIDTH-1, 0, CONVWIDTH-1}}}(lb0)
--      f0_slice = G.FIFO{1}(f0_slice)
      
      print("F0SLICE",f0_slice.type,f0_slice.rate)
      f0_slice = G.Map{G.ToColumns}(f0_slice)
      print("F0",f0_slice.type,f0_slice.rate)
      local f1_slice = G.Map{G.Slice{{0, CONVWIDTH-1, 0, CONVWIDTH-1}}}(lb1)
--      f1_slice = G.FIFO{1}(f1_slice)
      f1_slice = G.Map{G.ToColumns}(f1_slice)

      print("F)",f0_slice.type,f0_slice.scheduleConstraints)
      local binp = R.concat{G.NAUTOFIFO{FIFOSIZE}(f0_slice), G.NAUTOFIFO{FIFOSIZE}(f1_slice), G.NAUTOFIFO{FIFOSIZE}(fdx_stencilFO[1]), G.NAUTOFIFO{FIFOSIZE}(fdy_stencilFO[1])}
      print("BINP0",binp.type,binp.rate,binp.scheduleConstraints)
      local binp = G.FanIn(binp  )
      print("BINP",binp.type,binp.rate,binp.scheduleConstraints)
      local binp = G.Zip( binp  )
      print("BIN2P",binp.type,binp.rate)
      local b = G.Map{CalcB}(binp)

--      b = G.NAUTOFIFO{FIFOSIZE}(b)
      
--      b = G.Map{G.Map{G.AddMSBs{12}}}(b)
--      print("BDONE",b.type,b.rate)
--      b = G.FwritePGM{"out/"..outfile..".b.pgm"}(b)
--      b = G.Map{G.Map{G.RemoveMSBs{12}}}(b)
      
      local zipcc = R.concat{Ainv,b}
      print("ZIPCC",zipcc.type,zipcc.rate)
      zipcc = G.FanIn(zipcc)
      print("ZIPCC2",zipcc.type,zipcc.rate)
      local sinp = G.Zip(zipcc)

--      print("sinp",sinp.type,sinp.rate)
--      sinp = G.Map{G.Fwrite{"out/"..outfile..".sinp.data"},true}(sinp)

      local vectorField = G.Map{Solve}(sinp)

--      vectorField = G.Map{G.Map{G.AddMSBs{24}}}(vectorField)
--      print("solve",vectorField.type,vectorField.rate)
--      vectorField = G.FwritePGM{"out/"..outfile..".solve.pgm"}(vectorField)
--      vectorField = G.Map{G.Map{G.RemoveMSBs{24}}}(vectorField)
      
      local out = G.Map{Display}(vectorField)

--      print("DISPLAY",out.type,out.rate)
--      out = G.Map{G.Fwrite{"out/"..outfile..".display.data"},true}(out)
      
--      out = G.NAUTOFIFO{FIFOSIZE}(out)
      return out
    end}

local LKTop = G.SchedulableFunction{ "LKTop", T.Trigger,
  function(i)
    print("LKTOP",i.type,i.rate,i.scheduleConstraints)
    local readStream = G.AXIReadBurst{ inputFilename, {W,H}, T.Tuple{T.Uint(8),T.Uint(8)}, 4, noc.read }(i)
    print("RSTReAM",readStream.type,readStream.rate)
    local padded = G.Pad{{PadRadiusAligned, PadRadiusAligned, PadRadius+1, PadRadius}}(readStream)
--    padded = G.Map{G.Fwrite{"out/"..outfile..".padded.raw"},true}(padded)
    print("PADDED$",padded.type,padded.rate,PadRadiusAligned,PadRadius)
    local out = LK(padded)
    out = G.Crop{{PadRadius*2+PadExtra, PadExtra, PadRadius*2+1, 0}}(out)
--    out = G.NAUTOFIFO{FIFOSIZE}(out)
    return G.AXIWriteBurst{"out/"..outfile,noc.write}(out)
  end}

--local Top = C.linearPipeline({regs.start, LKTop, regs.done},"Top", SDF{1,cycles}, {regs} )
harness({regs.start, LKTop, regs.done},nil,{regs})
