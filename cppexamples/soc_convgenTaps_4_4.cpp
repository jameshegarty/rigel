#include <fstream>
#include <rigel.h>
#include <types.h>
#include <library.h>
#include <common.h>
#include <string>

using namespace Rigel;
using namespace Rigel::Lib;

constexpr unsigned int V = 4;
constexpr float VF = 4;
constexpr float ConvWidthF = 8;
constexpr int ConvWidth = 8;
constexpr float ConvRadiusF = ConvWidthF/2.f;
constexpr unsigned int ConvRadius = ConvRadiusF;

constexpr unsigned int PadRadius = upToNearest(V, ConvRadius);
constexpr float cycles = ((1920.f+PadRadius*2)*(1080.f+ConvWidthF))/(VF/ConvWidthF);

class ConvInner:public UserFunction{
public:
  ConvInner():UserFunction("ConvInner",Array2d(Tuple(Uint(8),Uint(8)),8,8)){}
  Val define(Val inp){
    Val out = Map<TupleToArray>(inp);
    Val msbs = Map<Map<AddMSBs<24>>>(out);
    Val att = Map<ArrayToTuple>(msbs);
    Val mm = Map<Mul>(att);
    Val res = Reduce<AddAsync>(mm);
    Val sft = Rshift<11>(res);
    return RemoveMSBs<24>(sft);
  }
};

class ConvTop:public UserFunction{
public:
  ConvTop():UserFunction("ConvTop",Array2d(Uint(8),1920,1080)){}
  Val define(Val inp){
    Val pad = Pad<PadRadius, PadRadius, ConvRadius, ConvRadius>(inp);

    Val padFO = FanOut<2>(pad);
    Val pad0i = padFO[0];
    Val pad0 = NAUTOFIFO<128>(pad0i);
    Val pad1i = padFO[1];
    Val pad1 = NAUTOFIFO<128>(pad1i);

    Val st = Stencil<-ConvWidth+1,0,-ConvWidth+1,0>(pad0);

    Val trig = Map<ValueToTrigger>(pad1);
    //Val coeffs = Map<RM.Storv(regs.coeffs)>(trig);
    Val coeffs = Map<Coeffs>(trig);
    Val coeffsCol = Map<ToColumns>(coeffs);

    Val padFanIn = FanIn(Concat(st,coeffsCol));
    Val padZip = Zip(padFanIn);

    Val padZipZip = Map<Zip>(padZip);
    Val res = Map<ConvInner>(padZipZip);
    Val resres = Crop<PadRadius+ConvRadius, PadRadius-ConvRadius, ConvRadius*2, 0>(res);

    return resres;
  }
};

int main(){
  ConvInner convInner;
  std::string convInnerLua = convInner.luaDefinition();

  ConvTop convTop;
  std::string convTopLua = convTop.luaDefinition();

  std::ofstream out("out/soc_convgenTaps_4_4.lua");
  out << header;
  out << "local regs = SOC.axiRegs({{\"coeffs\",RM.reg(T.Array2d(T.Uint(8),8,8),J.range(8*8))}},SDF{1,"+std::to_string(cycles)+"}):instantiate(\"regs\")\n"
"local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate(\"ZynqNOC\")\n"
"noc.extern=true\n";

  out << convInnerLua;
  out << convTopLua;
  out << "harness({regs.start,\n"
"         G.AXIReadBurst{\"1080p.raw\",{1920,1080},T.Uint(8),noc.read},\n"
"         ConvTop,\n"
"         G.AXIWriteBurst{\"out/soc_convgenTaps_4_4\",noc.write},\n"
"         regs.done},{filename=\"out/soc_convgenTaps_4_4\"},{regs})\n";

  out.close();

  return 0;
}
