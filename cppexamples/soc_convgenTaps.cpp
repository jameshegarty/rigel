#include <fstream>
#include <rigel.h>
#include <types.h>
#include <library.h>
#include <common.h>
#include <string>

using namespace Rigel;
using namespace RigelLibrary;

constexpr unsigned int V = 8;
constexpr float VF = 8;
constexpr float ConvWidthF = 8;
constexpr int ConvWidth = 8;
constexpr unsigned int ConvRadius = 4;

constexpr unsigned int PadRadius = 8; //upToNearest(V, ConvRadius);


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

  for(int autofifo=0; autofifo<=1; autofifo++){
    for(int V=1; V<=64; V*=2){
      float VF = V;
      float cycles = ((1920.f+PadRadius*2)*(1080.f+ConvWidthF))/(VF/ConvWidthF);

      std::string outfile = std::string("soc_convgenTaps_8_")+std::to_string(V)+((autofifo==0)?"":"_autofifo");

      std::ofstream outdesign("out/"+outfile+".design.txt");
      outdesign << "Convolution 1080p 8x8";
      outdesign.close();

      std::ofstream outdesignT("out/"+outfile+".designT.txt");
      outdesignT << VF/8.f;
      outdesignT.close();

      std::ofstream outdataset("out/"+outfile+".dataset.txt");
      if(autofifo==0){outdataset << "cpp";}else{outdataset << "cpp_autofifo";}
      outdataset.close();

      std::ofstream out("out/"+outfile+".lua");
      out << header;
      if(autofifo==0){
        out << "R.AUTO_FIFOS = false\n";
      }else{
        out << "R.AUTO_FIFOS = true\n";
        out << "R.Z3_FIFOS = true\n";
      }
      
      out << "local regs = SOC.axiRegs({{\"coeffs\",RM.reg(T.Array2d(T.Uint(8),8,8),J.range(8*8))}},SDF{1,"+std::to_string(cycles)+"}):instantiate(\"regs\")\n"
        "local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate(\"ZynqNOC\")\n"
        "noc.extern=true\n";

      out << convInnerLua;
      out << convTopLua;
      out << "harness({regs.start,\n"
        "         G.AXIReadBurst{\"1080p.raw\",{1920,1080},T.Uint(8),noc.read},\n"
        "         ConvTop,\n"
        "         G.AXIWriteBurst{\"out/"+outfile+"\",noc.write},\n"
        "         regs.done},{filename=\"out/"+outfile+"\"},{regs})\n";

      out.close();
    }
  }
  
  return 0;
}


