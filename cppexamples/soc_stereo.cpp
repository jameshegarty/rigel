#include <fstream>
#include <rigel.h>
#include <types.h>
#include <library.h>
#include <common.h>
#include <string>

using namespace Rigel;
using namespace RigelLibrary;

constexpr int SearchWindow = 64;
constexpr int OffsetX = 20; // search the range [-OffsetX-SearchWindow, -OffsetX]
constexpr int THRESH = 1000;
constexpr int SADWidth = 8;
constexpr int W=720;
constexpr int H=400;

class DisplayOutput:public UserFunction{
public:
  DisplayOutput():UserFunction("DisplayOutput",Tuple(Uint(8),Uint(16))){}
  Val define(Val inp){
    Val th = Const<UintValue<16,0>,THRESH>(ValueToTrigger(inp));
    Val zero = Const<UintValue<8,0>,0>(ValueToTrigger(inp));
    return Sel( Concat(GT(Concat(inp[1],th)), zero, inp[0]) );
  }
};

// indices for the argmin
constexpr int idx(int i){
  // index gives us the distance to the right hand side of the window
  return SearchWindow+OffsetX-i;
}
  
class FindBestMatch:public UserFunction{
public:
  FindBestMatch():UserFunction("FindBestMatch", Array2d( Array2d( Array2d( Uint(8), 2, 1 ), SADWidth, SADWidth ), SearchWindow, 1 )){}
  Val define(Val i){
    Val inp = FanOut<2>(i).setName("FindBestInpFanOut");

    Val inp0 = (inp[0]).setName("inp0");
    Val inp1 = (inp[1]).setName("inp1");
      
    //    local idx = {} -- build indices for the argmin
    //    for i=1,SearchWindow do
    //      -- index gives us the distance to the right hand side of the window
    //      idx[i] = SearchWindow+OffsetX-(i-1)
    //    end

    Val indices = Const<UintValue<8,0>,SearchWindow,1,idx>(ValueToTrigger(inp0).setName("valueToTrigger")).setName("indices");
    Val SADOut = Map<SAD>(inp1).setName("SADOut");

    Val indicesFIFO = NAUTOFIFO<128>(indices);
    Val SADOutFIFO = NAUTOFIFO<128>(SADOut);
    Val argminInp = Zip( FanIn( Concat(indicesFIFO, SADOutFIFO) ).setName("fanIn")); //{u8,u16}[SearchWindow]

    Val res = Reduce<ArgMin>(argminInp);

    return res;
  }
};

class StereoTop:public UserFunction{
public:
  StereoTop():UserFunction("StereoTop", Array2d(Tuple(Uint(8),Uint(8)),W,H) ){}
  Val define(Val readStream){
    Val inp = Pad<OffsetX+SearchWindow+SADWidth,0,3,4>(readStream);

    Val inpFO = FanOut<2>(inp);

    Val left = Map<Index<0>>(inpFO[0]);
    Val leftFIFO = NAUTOFIFO<128>(left); //     left = NAUTOFIFO{128,"left"}(left)
    Val leftSOS = StencilOfStencils<-(SearchWindow+SADWidth+OffsetX)+2,-(OffsetX), -SADWidth+1, 0, SADWidth,SADWidth>(leftFIFO);

    Val right = Map<Index<1>>(inpFO[1]);
    Val rightFIFO = NAUTOFIFO<128>(right);

    // override the default rate of this stencil op to 100%:
    // input rate is actually 25%, but since we are broadcasting after,
    // if we throughput reduce the stencil, it will actually lead to double buffering
    Val rightSt = Stencil<-SADWidth+1,0,-SADWidth+1,0,SDF<1,1>>(rightFIFO);

    Val rightBroad = Map<Broadcast<SearchWindow,1>>(rightSt);
    
    Val merged = Zip(FanIn(Concat(leftSOS,rightBroad))); // {A[SADWidth,SADWidth],A[SADWidth,SADWidth]}[SearchWindow]
    Val mergedZip = Map<Zip>(merged);
    Val mergedZA = Map<Map<ZipToArray>>(mergedZip); // {A,A}[SADWidth, SADWidth][SearchWindow]
    
    Val min = Map<FindBestMatch>(mergedZA); // do the stereo match!
    Val minFIFO = NAUTOFIFO<128>(min);
    Val res = Map<DisplayOutput>(minFIFO);
    Val resres = Crop< OffsetX+SearchWindow+SADWidth, 0, SADWidth-1, 0 >(res);

    return resres;
  }
};

int main(){
  DisplayOutput displayOutput;
  std::string displayOutputLua = displayOutput.luaDefinition();

  FindBestMatch findBestMatch;
  std::string findBestMatchLua = findBestMatch.luaDefinition();

  StereoTop stereoTop;
  std::string stereoTopLua = stereoTop.luaDefinition();

  for(int autofifo=0; autofifo<=1; autofifo++){
    for(int V=4; V<=64; V*=2){
      float VF = V;
      float cycles = ((W+OffsetX+SearchWindow+SADWidth)*(H+7))*((float)SearchWindow/VF);
    
      std::string outfile = "soc_stereo_full_64_"+std::to_string(V)+((autofifo==0)?"":"_autofifo");

      std::ofstream outdesign("out/"+outfile+".design.txt");
      outdesign << std::string("Stereo ")+std::to_string(SearchWindow)+" "+std::to_string(SADWidth)+"x"+std::to_string(SADWidth)+" full";
      outdesign.close();

      std::ofstream outdesignT("out/"+outfile+".designT.txt");
      outdesignT << VF/(float)SearchWindow;
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
      
      out << "local regs = SOC.axiRegs({},SDF{1,"+std::to_string(cycles)+"}):instantiate(\"regs\")\n"
        "local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate(\"ZynqNOC\")\n"
        "noc.extern=true\n";

      std::string MHz = "";
      if(V==16){
	MHz=",MHz=130";
      }else if(V==32){
	MHz=",MHz=95";
      }else if(V==64){
	MHz=",MHz=105";
      }
      
      out << displayOutputLua;
      out << findBestMatchLua;
      out << stereoTopLua;
      out << "harness({regs.start,\n"
        "         G.AXIReadBurst{\"stereo0000.raw\",{720,400},T.Tuple{T.Uint(8),T.Uint(8)},4,noc.read},\n"
        "         StereoTop,\n"
        "         G.AXIWriteBurst{\"out/"+outfile+"\",noc.write},\n"
        "         regs.done},{filename=\"out/"+outfile+"\""+MHz+"},{regs})\n";

      out.close();
    }
  }
  
  return 0;
}


