#include <fstream>
#include <rigel.h>
#include <types.h>
#include <library.h>
#include <common.h>
#include <string>
#include <math.h>

using namespace Rigel;
using namespace RigelLibrary;

//constexpr unsigned int V = 8;
//constexpr float VF = 8;
constexpr float ConvWidthF = 12;
//constexpr int ConvWidth = 8;
//constexpr unsigned int ConvRadius = 4;

constexpr unsigned int PadRadius = 6;

constexpr int FIFOSIZE = 128;

constexpr int CONVWIDTH = 12;

class Fdenom:public UserFunction{
public:
  Fdenom():UserFunction("Fdenom", Array2d(Int(20,-2),4,1), true ){}
  Val define(Val i){
    Val lhs = MulE(Concat(i[0],i[3]));
    Val rhs = MulE(Concat(i[1],i[2]));
    Val fdenom = SubE(Concat(lhs,rhs));
    Val fdenom1 = RemoveLSBsE<10>(fdenom);
    return fdenom1;
  }
};

Fdenom fdenom;

class Fout:public UserFunction{
public:
  Fout():UserFunction("Fout", Tuple(Array2d(Int(20,-2),4,1), Int(40,-35-10)), true ){}
  Val define(Val i){
    Val fmatrix = FanOut<4>(i[0]);
    Val i0 = NAUTOFIFO<128>(fmatrix[0][0]);
    Val i1 = NAUTOFIFO<128>(fmatrix[1][1]);
    Val i2 = NAUTOFIFO<128>(fmatrix[2][2]);
    Val i3 = NAUTOFIFO<128>(fmatrix[3][3]);
    Val fdet = FanOut<4>(i[1]);

    Val OT0 = MulE(Concat(NAUTOFIFO<128>(fdet[0]),i3));
    Val OT1 = MulE(Concat(Neg(NAUTOFIFO<128>(fdet[1])),i1));
    Val OT2 = MulE(Concat(Neg(NAUTOFIFO<128>(fdet[2])),i2));
    Val OT3 = MulE(Concat(NAUTOFIFO<128>(fdet[3]),i0));
    
    Val R0_0 = RemoveMSBs<15>(OT0);
    Val R1_0 = RemoveMSBs<15>(OT1);
    Val R2_0 = RemoveMSBs<15>(OT2);
    Val R3_0 = RemoveMSBs<15>(OT3);

    Val R0 = RemoveLSBsE<26>(R0_0);
    Val R1 = RemoveLSBsE<26>(R1_0);
    Val R2 = RemoveLSBsE<26>(R2_0);
    Val R3 = RemoveLSBsE<26>(R3_0);
    
    return TupleToArray(Concat(R0,R1,R2,R3));
  }
};

Fout fout;

class Invert2x2:public UserFunction{
public:
  Invert2x2():UserFunction("Invert2x2", Array2d(Int(20,-2),4), true ){}
  Val define(Val i){
    Val iFO = FanOut<2>(i);
    Val denom = fdenom( NAUTOFIFO<128>(iFO[0]) );
    //Val det = Fmap{C.lutinvert(denom.type:deInterface())}(denom);
    Val det = LUTInvert(denom);
    Val res = fout( Concat(NAUTOFIFO<128>(iFO[1]), det) );
    return res;
  }
};

class Dx:public UserFunction{
public:
  Dx():UserFunction("Dx", Array2d(Uint(8),3,1), true ){}
  Val define(Val i){
    Val iFO = FanOut<2>(i);
    Val outl = UtoI(AddMSBs<1>(iFO[0][2]));
    Val outr = UtoI(AddMSBs<1>(iFO[1][0]));
    Val outt = SubE(Concat(outl,outr));
    Val out = RshiftE<1>(outt);
    return out;
  }
};

class Dy:public UserFunction{
public:
  Dy():UserFunction("Dy", Array2d(Uint(8),1,3), true ){}
  Val define(Val i){
    Val iFO = FanOut<2>(i);
    Val outl = UtoI(AddMSBs<1>(Index<0,2>(iFO[0])));
    Val outr = UtoI(AddMSBs<1>(Index<0,0>(iFO[1])));
    Val outt = SubE(Concat(outl,outr));
    return RshiftE<1>(outt);
  }
};

class CalcA:public UserFunction{
public:
  CalcA():UserFunction("CalcA", Tuple( Array2d( Int(10,-1), 12, 12),
                                       Array2d( Int(10,-1), 12, 12) ) ){}
  Val define(Val inp){
    Val inpFO = FanOut<2>(inp);

    Val Fdx = inpFO[0][0];
    Val FdxFO = FanOut<3>(Fdx);

    Val Fdy = inpFO[1][1];
    Val FdyFO = FanOut<3>(Fdy);

    Val inp0 = Zip( Concat( NAUTOFIFO<1>(FdxFO[0]),NAUTOFIFO<1>(FdxFO[1]) ));
    Val out0 = Map<MulE>(inp0);
    
    out0 = Reduce<AddAsync>(out0);
    
    Val inp1 = Zip( Concat( NAUTOFIFO<1>(FdxFO[2]),NAUTOFIFO<1>(FdyFO[0]) ));
    Val out1 = Map<MulE>(inp1);
    out1 = Reduce<AddAsync>(out1);

    Val out1FO = FanOut<2>(out1);
    
    Val inp3 = Zip( Concat( NAUTOFIFO<8>(FdyFO[1]),NAUTOFIFO<8>(FdyFO[2]) ));
    Val out3 = Map<MulE>(inp3);
    out3 = Reduce<AddAsync>(out3);
    
    Val out = Concat( NAUTOFIFO<1>(out0), NAUTOFIFO<1>(out1FO[0]), NAUTOFIFO<1>(out1FO[1]), NAUTOFIFO<1>(out3) );
    
    return TupleToArray(FanIn(out));
  }
};

class Minus:public UserFunction{
public:
  Minus():UserFunction("Minus", Tuple( Uint(8), Uint(8) ) ){}
  Val define(Val i){
    Val lhs = UtoI(AddMSBs<1>(i[0]));
    Val rhs = UtoI(AddMSBs<1>(i[1]));
    return SubE(Concat(lhs,rhs));
  }
};

class CalcB:public UserFunction{
public:
  CalcB():UserFunction("CalcB", Tuple( Array2d( Uint(8),12,12),
                                       Array2d( Uint(8),12,12),
                                       Array2d( Int(10,-1),12,12),
                                       Array2d( Int(10,-1),12,12) ) ){}
  Val define(Val i){
    Val iFO = FanOut<4>(i);
    Val frame0 = NAUTOFIFO<FIFOSIZE>(iFO[0][0]);
    Val frame1 = NAUTOFIFO<FIFOSIZE>(iFO[1][1]);
    Val Fdx = NAUTOFIFO<FIFOSIZE>(iFO[2][2]);
    Val Fdy = NAUTOFIFO<FIFOSIZE>(iFO[3][3]);

    Val gmf = Concat(frame1,frame0).setName("gmf");
    Val gmf_1 = Zip(gmf).setName("gmf_zip");
    Val gmf_2 = Map<Minus>(gmf_1);
    Val gmf_3 = NAUTOFIFO<FIFOSIZE>(gmf_2);
    Val gmfFO = FanOut<2>(gmf_3);

    Val Fdx1 = NAUTOFIFO<1>(Fdx);
    Val gmf0 = NAUTOFIFO<1>(gmfFO[0]).setName("gmf0");
    
    Val out_0 = Concat(Fdx1, gmf0).setName("out_0_concat");
    Val out_0_1 = Zip(out_0).setName("out_0_zip");
    Val out_0_2 = Map<MulE>(out_0_1);
    Val out_0_3 = Reduce<AddAsync>(out_0_2);
                      
    Val Fdy1 = NAUTOFIFO<1>(Fdy);
    Val gmf1 = NAUTOFIFO<1>(gmfFO[1]);
    
    Val out_1 = Concat( Fdy1, gmf1 ).setName("out_1_concat");
    Val out_1_1 = Zip(out_1);
    Val out_1_2 = Map<MulE>(out_1_1);
    Val out_1_3 = Reduce<AddAsync>(out_1_2);
    
    Val out = FanIn( Concat( out_0_3, out_1_3 ));
    Val out1 = TupleToArray(out);
    
    return out1;
  }
};

class Solve:public UserFunction{
public:
  Solve():UserFunction("Solve", Tuple( Array2d(Int(19,-11-10),4),
                                       Array2d(Int(20,-1),2) ), true ){}
  Val define(Val i){
    Val iFO = FanOut<2>(i);
    Val Ainv = FanOut<4>(iFO[0][0]);
    Val b = FanOut<2>(iFO[1][1]);
    Val b0 = b[0][0];
    Val b1 = b[1][1];
    Val b0_1 = FanOut<2>(Neg(b0));
    Val b1_1 = FanOut<2>(Neg(b1));
    Val Ainv0 = NAUTOFIFO<128>(Ainv[0][0]);
    Val Ainv1 = NAUTOFIFO<128>(Ainv[1][1]);
    Val Ainv2 = NAUTOFIFO<128>(Ainv[2][2]);
    Val Ainv3 = NAUTOFIFO<128>(Ainv[3][3]);

    Val out_0_lhs = MulE( Concat( NAUTOFIFO<128>(Ainv0), NAUTOFIFO<128>(b0_1[0]) ) );
    Val out_0_rhs = MulE( Concat( NAUTOFIFO<128>(Ainv1), NAUTOFIFO<128>(b1_1[0]) ) );
    Val out_0 = AddE( Concat(out_0_lhs, out_0_rhs) );
    
    Val out_1_lhs = MulE( Concat( NAUTOFIFO<128>(Ainv2), NAUTOFIFO<128>(b0_1[1]) ) );
    Val out_1_rhs = MulE( Concat( NAUTOFIFO<128>(Ainv3), NAUTOFIFO<128>(b1_1[1]) ) );
    Val out_1 = AddE( Concat(out_1_lhs, out_1_rhs) );
    
    return TupleToArray( Concat(out_0, out_1) );
  }
};

class Display:public UserFunction{
public:
  Display():UserFunction("Display", Array2d(Int(40,-12-10),2), true  ){}
  Val define(Val inp){
    Val inpFO = FanOut<2>(inp);
    
    //
    Val I_0 = inpFO[0][0];
    Val B_0 = MulE<32>(I_0);
    Val FF_0 = AddE<128>(B_0);
    Val FF1_0 = Abs(FF_0);
    Val FF2_0 = ItoU(FF1_0);
    Val FF_den_0 = Denormalize(FF2_0);
    Val FF_trunc_0 = RemoveMSBs<24-8>(FF_den_0);

    ////
    Val I_1 = inpFO[1][1];
    Val B_1 = MulE<32>(I_1);
    Val FF_1 = AddE<128>(B_1);
    Val FF1_1 = Abs(FF_1);
    Val FF2_1 = ItoU(FF1_1);
    Val FF_den_1 = Denormalize(FF2_1);
    Val FF_trunc_1 = RemoveMSBs<24-8>(FF_den_1);

    Val res = TupleToArray(Concat(FF_trunc_0,FF_trunc_1));

    return res;
  }
};

template< bool LOWV >
class LK:public UserFunction{
public:
  LK():UserFunction("LK", Array2d(Tuple(Uint(8),Uint(8)),Uniform(1932),1093) ){}
  Val define(Val inp){
    Val inpFO = FanOut<2>(inp);
      
    Val frame0 = Map<Index<0>>(NAUTOFIFO<FIFOSIZE>(inpFO[0]));
    Val frame0FO = FanOut<2>(frame0);
    Val frame0_0 = NAUTOFIFO<FIFOSIZE>(frame0FO[0]);
    Val frame0_1 = NAUTOFIFO<FIFOSIZE>(frame0FO[1]);

    Val frame1 = Map<Index<1>>(NAUTOFIFO<FIFOSIZE>(inpFO[1]));
    Val frame1_1 = NAUTOFIFO<FIFOSIZE>(frame1);
      
    Val lb0 = Stencil<-CONVWIDTH, 0, -CONVWIDTH, 0>(frame0_0);
      
    Val lb0_fd = Stencil<-2, 0, -2, 0>(frame0_1);

    Val lb0_fd_FO = FanOut<2>(lb0_fd);
    Val lb0_fd_0 = NAUTOFIFO<FIFOSIZE>(lb0_fd_FO[0]);
    Val lb0_fd_1 = NAUTOFIFO<FIFOSIZE>(lb0_fd_FO[1]);


    Val lb1 = Stencil<-CONVWIDTH, 0, -CONVWIDTH, 0>(frame1_1);
      
    Val fdx = Map<Slice<0,2,1,1>>(lb0_fd_0);

    //    if(VORIG<CONVWIDTH){
    if( LOWV ){
      fdx = NAUTOFIFO<2>(fdx);
    }
      
    Val fdx_1 = Map<Dx>(fdx);

    Val fdx_stencil = Stencil<-CONVWIDTH+1, 0, -CONVWIDTH+1, 0>( fdx_1 );
      
    Val fdx_stencilFO = FanOut<2>(fdx_stencil);
      
    Val fdy = Map<Slice<1,1,0,2>>(lb0_fd_1);

    //    if(VORIG<CONVWIDTH){
    if( LOWV ){
      fdy = NAUTOFIFO<2>(fdy);
    }
      
    Val fdy_1 = Map<Dy>(fdy);
      
    Val fdy_stencil = Stencil<-CONVWIDTH+1, 0, -CONVWIDTH+1, 0>(fdy_1);
      
    Val fdy_stencilFO = FanOut<2>(fdy_stencil);
      
    Val Ainpinp = Concat( NAUTOFIFO<FIFOSIZE>(fdx_stencilFO[0]), NAUTOFIFO<FIFOSIZE>(fdy_stencilFO[0]) );

    Val Ainp = Zip( Ainpinp  );
    Val A = Map<CalcA>(Ainp);
      
    Val Ainv = Map<Invert2x2>(A);
    Val Ainv_1 = NAUTOFIFO<FIFOSIZE>(Ainv);

    Val f0_slice = Map<Slice<0, CONVWIDTH-1, 0, CONVWIDTH-1>>(lb0);

    Val f0_slice_1 = Map<ToColumns>(f0_slice);

    Val f1_slice = Map<Slice<0, CONVWIDTH-1, 0, CONVWIDTH-1>>(lb1);

    Val f1_slice_1 = Map<ToColumns>(f1_slice);


    Val binp = Concat( NAUTOFIFO<FIFOSIZE>(f0_slice_1), NAUTOFIFO<FIFOSIZE>(f1_slice_1), NAUTOFIFO<FIFOSIZE>(fdx_stencilFO[1]), NAUTOFIFO<FIFOSIZE>(fdy_stencilFO[1]) );

    Val binp_1 = FanIn( binp );

    Val binp_2 = Zip( binp_1 );

    Val b = Map<CalcB>( binp_2 );

    Val zipcc = Concat( Ainv_1, b );

    Val zipcc_1 = FanIn(zipcc);

    Val sinp = Zip( zipcc_1 );

    Val vectorField = Map<Solve>(sinp);
      
    Val out = Map<Display>(vectorField);

    return out;
  }
};

int main(){
  std::string fdenomLua = fdenom.luaDefinition();
  std::string foutLua = fout.luaDefinition();

  Invert2x2 invert2x2;
  std::string invert2x2Lua = invert2x2.luaDefinition();

  Dx dx;
  std::string dxLua = dx.luaDefinition();

  Dy dy;
  std::string dyLua = dy.luaDefinition();

  CalcA calcA;
  std::string calcALua = calcA.luaDefinition();

  Minus minus;
  std::string minusLua = minus.luaDefinition();

  CalcB calcB;
  std::string calcBLua = calcB.luaDefinition();

  Solve solve;
  std::string solveLua = solve.luaDefinition();

  Display display;
  std::string displayLua = display.luaDefinition();

  LK<true> lklow;
  std::string lklowLua = lklow.luaDefinition();

  LK<false> lkhigh;
  std::string lkhighLua = lkhigh.luaDefinition();

  int Vs[] = {1,2,3,4,6,12,24,48};
  for(int autofifo=0; autofifo<=1; autofifo++){
    for(int Vi=0; Vi<8; Vi++){
      int V = Vs[Vi];
      float VF = V;
      float invVF = VF/12.f;
      int invV = ceil(invVF);
      
      //float cycles = ((1920.f+PadRadius*2)*(1080.f+ConvWidthF))/(VF/ConvWidthF);
      float W = 1920.f;
      float H = 1080.f;
      int PadRadiusAligned = upToNearest( invV, PadRadius );
      int PadExtra = PadRadiusAligned - PadRadius;
      float cycles = float((W+PadRadiusAligned*2)*(H+PadRadius*2+1))/invVF;
      
      std::string outfile = "soc_lk_12_"+std::to_string(V)+((autofifo==0)?"":"_autofifo");

      std::ofstream outdesign("out/"+outfile+".design.txt");
      outdesign << "Lucas Kanade 1080 12x12";
      outdesign.close();

      std::ofstream outdesignT("out/"+outfile+".designT.txt");
      outdesignT << VF/12.f;
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

      out << fdenomLua;
      out << foutLua;
      out << invert2x2Lua;
      out << dxLua;
      out << dyLua;
      out << calcALua;
      out << minusLua;
      out << calcBLua;
      out << solveLua;
      out << displayLua;
      if(V<12){
        out << lklowLua;
      }else{
        out << lkhighLua;
      }

      std::string MHz="";
      if(V==12){
	MHz=",MHz=120";
      }else if(V==24){
	MHz=",MHz=100";
      }
      
      out << "harness({regs.start,\n"
        "         G.AXIReadBurst{\"packed_v0000.raw\",{1920,1080},T.Tuple{T.Uint(8),T.Uint(8)},4,noc.read},\n"
        "         G.Pad{{"+std::to_string(PadRadiusAligned)+", "+std::to_string(PadRadiusAligned)+", "+std::to_string(PadRadius+1)+", "+std::to_string(PadRadius)+"}},\n"
        "         LK,\n"
        "         G.Crop{{"+std::to_string(PadRadius*2+PadExtra)+", "+std::to_string(PadExtra)+", "+std::to_string(PadRadius*2+1)+", 0}},\n"
        "         G.AXIWriteBurst{\"out/"+outfile+"\",noc.write},\n"
        "         regs.done},{filename=\"out/"+outfile+"\""+MHz+"},{regs})\n";

      out.close();
    }
  }
  
  return 0;
}


