#include <fstream>
#include <rigel.h>
#include <types.h>
#include <library.h>
#include <common.h>
#include <string>

using namespace Rigel;
using namespace Rigel::Lib;

constexpr unsigned int V = 8;
constexpr float VF = 8;
constexpr float ConvWidthF = 8;
constexpr int ConvWidth = 8;
constexpr unsigned int ConvRadius = 4;

constexpr unsigned int PadRadius = 8; //upToNearest(V, ConvRadius);

constexpr int GRAD_INT = true;
constexpr int GRAD_SCALE = 4; // <2 is bad

class ClampToInt8:public UserFunction{
public:
  ClampToInt8():UserFunction("ClampToInt8", FloatRec(32), true ){}
  Val define(Val i){
    Val v127 = FtoFR(Rigel::Const(Float(32),127));
    Val vm128 = FtoFR(Rigel::Const(Float(32),-128));
    Val tmp = Sel(Concat(GTF(Concat(i,v127)),v127,i));
    Val tmp1 = Sel(Concat(LTF(Concat(i,vm128)),vm128,tmp));
    return tmp1;
  }
};

class DXDYToInt8:public UserFunction{
public:
  DXDYToInt8():UserFunction("DXDYToInt8", Tuple( FloatRec(32), FloatRec(32) ), true ){}
  Val define(Val i){
    Val tmpcc = Concat( MulF<GRAD_SCALE,1>(i[0]), MulF<GRAD_SCALE,1>(i[1]) );
    Val tmp = TupleToArray(tmpcc);
    Val tmp1 = Map<ClampToInt8>(tmp);
    Val tmp2 = Map<FRtoI<8>>(tmp1);
    return ArrayToTuple(tmp2);
  }
};

class HarrisDXDYKernel:public UserFunction{
public:
  HarrisDXDYKernel():UserFunction("HarrisDXDYKernel", Array2d( FloatRec(32), 3, 3 ), true ){}
  Val define( Val i ){
    Val dx = SubF( Concat( Index<2,1>(i), Index<0,1>(i) ) );
    Val dx1 = MulF<1,2>(dx);

    Val dy = SubF( Concat( Index<1,2>(i), Index<1,0>(i) ) );
    Val dy1 = MulF<1,2>(dy);

    return Concat( dx1, dy1 );
  }
};

class HarrisHarrisKernel:public UserFunction{
public:
  HarrisHarrisKernel():UserFunction("HarrisHarrisKernel", Tuple( FloatRec(32), FloatRec(32) ) ){}
  Val define(Val i){
    Val dx = i[0];
    Val dy = i[1];
    Val Ixx = MulF( Concat( dx, dx) );
    Val Ixy = MulF( Concat( dx, dy) );
    Val Iyy = MulF( Concat( dy, dy) );
    Val det = SubF( Concat( MulF( Concat(Ixx,Iyy) ), MulF( Concat(Ixy,Ixy) ) ));
    Val tr = AddF( Concat( Ixx, Iyy ) );
    Val trsq = MulF( Concat(tr, tr) );

    float K = 0.00000001;
    Val Krigel = ToFloatRec<32>(Const<FloatValue<8,24>,K>(ValueToTrigger(i)));
    Val out = SubF( Concat( det, MulF( Concat( trsq, Krigel) ) ) );
    return out;
  }
};

class HarrisNMS:public UserFunction{
public:
  HarrisNMS():UserFunction("HarrisNMS", Array2d( FloatRec(32), 3, 3 ), true ){}
  Val define(Val inp){
    Val N = GTF(Index<1,1>(i),Index<1,0>(i));
    Val S = GTF(Index<1,1>(i),Index<1,2>(i));
    Val E = GTF(Index<1,1>(i),Index<2,1>(i));
    Val W = GTF(Index<1,1>(i),Index<0,1>(i));
    Val nms = And(And(And(N,S),E),W);

    float THRESH = 0.001f;
    Val THRESHrigel = ToFloatRec<32>(Const<T.Float32,THRESH>(ValueToTrigger(i)));
    Val aboveThresh = GTF(Index<1,1>(i),THRESHrigel);
    Val out = And( Concat(nms, aboveThresh) );
    return out;
  }
};

class HarrisDXDY:public UserFunction{
public:
  HarrisDXDY():UserFunction("HarrisDXDY", Array2d( Uint(8), 3, 3 ) ){}
  Val define(Val i){
    Val blurX =  Pad<2,2,0,0>(i);
    Val blurX = Map<ToFloatRec<32>(blurX);
    Val blurX = Stencil<-4,0,0,0>(blurX);
    Val blurX = Map<ConvolveFloat(5,1,GAUSS,8)>(blurX);
    Val blurX = Crop<4,0,0,0>(blurX);

    Val blurXY = Pad<0,0,2,2>(blurX);
    Val blurXY = Stencil<0,0,-4,0>(blurXY);
    Val blurXY = Map<ConvolveFloat(1,5,GAUSS,8)>(blurXY);
    Val blurXY = Crop<0,0,4,0>(blurXY);

    Val dxdy = Pad<1,1,1,1>(blurXY);
    Val dxdy = Stencil<-2,0,-2,0>(dxdy);
    Val dxdy = Map<harrisDXDYKernel>(dxdy);
    Val dxdy = Crop<2,0,2,0>(dxdy);
  
    return dxdy;
  }
};

class BucketReduce:public UserFunction{
public:
  BucketReduce():UserFunction("BucketReduce", Tuple( Array2d( Int(32), 8 ), Array2d( Int(32), 8 ) ), true ){}
  Val define(Val i){
    Val z = Zip(i);
    return Map<Add<R.Async>>(z);
  }
};

class FilterCrop:public UserFunction{
public:
  FilterCrop():UserFunction("FilterCrop", Array2d( Bool(), Uniform(W+15), H+15 ) ){}
  Val define(Val i){
    Val iFO = FanOut<2>(i);
  
    Val posTrig = Map<ValueToTrigger>(iFO[1]);

    Val pos = PosCounter<true>(posTrig);

    Val X = Map<Index<0>>(pos);
    Val Y = Map<Index<1>>(pos);

    Val Xgt = Map<GT<14>>(X);
    Val Ygt = Map<GT<14>>(Y);

    Val rhs = Map<And>(Zip(Xgt,Ygt));
  
    Val lhs = iFO[0];
    Val res = Zip(lhs,rhs);

    Val res2 = Map<And>(res);

    return res2;
  }
};

class Bucketize:public UserFunction{
public:
  Bucketize():UserFunction("Bucketize", Tuple( FloatRec(32), FloatRec(32), FloatRec(32) ), true ){}
  Val define(Val i){
    Val dx = i[0];

    Val dy = i[1];
    Val mag = MulF<1024/GRAD_SCALE>(i[2]);

    Val mag = FRtoI<32>(mag);

    Val zero = R.c( T.I32, 0 );

    Val zf = R.c( types.FloatRec(32), 0 );
  
    Val dx_ge_0 = GEF( dx, zf );
    Val dy_ge_0 = GEF( dy, zf );
    Val dx_gt_dy = GTF( dx, dy );
    Val dx_gt_negdy = GTF( dx, NegF(dy) );
    Val dy_gt_negdx = GTF( dy, NegF(dx) );
    Val negdx_gt_negdy = GTF( NegF(dx), NegF(dy) );
    
    Val v0 = Sel(And(dx_ge_0,And(dy_ge_0,dx_gt_dy)),mag,zero);
    Val v1 = Sel(And(dx_ge_0,And(dy_ge_0,Not(dx_gt_dy))),mag,zero);
    Val v7 = Sel(And(dx_ge_0,And(Not(dy_ge_0),dx_gt_negdy)),mag,zero);
    Val v6 = Sel(And(dx_ge_0,And(Not(dy_ge_0),Not(dx_gt_negdy))),mag,zero);
    Val v2 = Sel(And(Not(dx_ge_0),And(dy_ge_0,dy_gt_negdx)),mag,zero);
    Val v3 = Sel(And(Not(dx_ge_0),And(dy_ge_0,Not(dy_gt_negdx))),mag,zero);
    Val v4 = Sel(And(Not(dx_ge_0),And(Not(dy_ge_0),negdx_gt_negdy)),mag,zero);
    Val v5 = Sel(And(Not(dx_ge_0),And(Not(dy_ge_0),Not(negdx_gt_negdy))),mag,zero);

    return TupleToArray( Concat(v0,v1,v2,v3,v4,v5,v6,v7) );
  }
};

class SiftMagPre:public UserFunction{
public:
  SiftMagPre():UserFunction("SiftMagPre", Tuple( FloatRec(32), FloatRec(32) ), true ){}
  Val define(Val i){
    Val dx = i[0];
    Val dy = i[1];
    Val magsq = AddF( MulF(dx,dx), MulF(dy,dy) );
    return magsq;
  }
};

class SiftMag:public UserFunction{
public:
  SiftMag():UserFunction("SiftMag", Tuple( FloatRec(32), FloatRec(32), FloatRec(32) ) ){}
  Val define(Val inp){
    Val i = FanOut<2>(inp);
    Val gauss_weight = i[1][2];
    Val gauss_weight = NAUTOFIFO<128>(gauss_weight);
  
    Val magsq = Fmap<SiftMagPre>(Slice<<0,1>>(i[0]));
    Val mag = BoostRate<SqrtF>( magsq );
    Val mag = NAUTOFIFO<1>(mag);

    Val out = MulF(FanIn(mag,gauss_weight));
    return out;
  }
};

class SiftDescriptor:public UserFunction{
public:
  SiftDescriptor():UserFunction("SiftDescriptor", Array2d(Array2d(Tuple{T.I8,T.I8},TILE_W,TILE_H),TILES_X,TILES_Y) ){}
  Val define(Val inp){
    Val inpb = FanOut<3>(inp);
  
    Val gtrig = ValueToTrigger(inpb[0]);
    Val gtrig = NAUTOFIFO<128>(gtrig);

    Val gweight = Const<T.Array2d(T.Array2d(T.Float32,TILE_W,TILE_H),TILES_X,TILES_Y),value=GAUSS>(gtrig);

    Val dx = Map<Map<Index<0>>>(inpb[1]);
    Val dx = NAUTOFIFO<128>(dx);
    Val dy = Map<Map<Index<1>>>(inpb[2]);
    Val dy = NAUTOFIFO<128>(dy);

    if(GRAD_INT){
      dx = Map<Map<ItoFR>>(dx);
      dy = Map<Map<ItoFR>>(dy);
      gweight = Map<Map<Identity>>(gweight);
      gweight = Map<Map<FtoFR>>(gweight);
    }

    Val dx = FanOut<2>(dx);;
    Val dy = FanOut<2>(dy);

    Val dx0 = dx[0];
    Val dx0 = NAUTOFIFO<128>(dx0);

    Val dy0 = dy[0];
    Val dy0 = NAUTOFIFO<128>(dy0);

    Val maginp = R.concat("maginp",{dx0,dy0,gweight>);

    Val maginp = FanIn(maginp);
    Val maginp = Zip(maginp);
    Val maginp = Map<Zip>(maginp);

    Val mag = Map<Map<SiftMag>>(maginp);

    Val dx1 = dx[1];
    Val dx1 = NAUTOFIFO<128>(dx1);

    Val dy1 = dy[1];
    Val dy1 = NAUTOFIFO<128>(dy1);

    Val bucketInp = R.concat("bktinp",{dx1,dy1,mag>);
    Val bucketInp = FanIn(bucketInp);
    Val bucketInp = Zip(bucketInp);
    Val bucketInp = Map<Zip>(bucketInp);

    Val out = Map<Map<Bucketize>>(bucketInp);
    return out;
  }
};

class AddDescriptorPos:public UserFunction{
public:
  AddDescriptorPos():UserFunction("AddDescriptorPos", Tuple( Array2d( FloatRec(32), TILES_X*TILES_Y*8 ), Uint(16), Uint(16)), true ){}
  Val define(Val i){
    Val desc = i[0];
    Val px = UtoFR(i[1]);
    Val py = UtoFR(i[2]);
  
    std::vector<Value*> a;
    a.push_back(px);
    a.push_back(py); 
    for( int i=0; i<TILES_X*TILES_Y*8; i++){
      table.insert(a,desc[i]);
    }

    Val out = TupleToArray(Concat(a));
    return out
  }
};

class SiftKernel:public UserFunction{
public:
  SiftKernel():UserFunction("SiftKernel", Tuple( Array2d(Tuple(Int(8),Int(8)),TILES_X*TILE_W,TILES_Y*TILE_H), Tuple{Uint(16),Uint(16)) } ){}
  Val define(Val i){
    //local dxdyType = types.I8
    //local dxdyPair = types.tuple{dxdyType,dxdyType}
    //local posType = types.uint(16)
  
    Val inp = FanOut<2>(i);

    Val pos = inp[0][1];

    Val pos = NAUTOFIFO<1024>(pos);
  
    Val posFO = FanOut<2>(pos);

    Val posX = posFO[0][0];
    Val posX = NAUTOFIFO<1024>(posX);
    Val posY = posFO[1][1];
    Val posY = NAUTOFIFO<1024>(posY);

    Val dxdy = inp[1][0];

    Val dxdyTiles = Tile<<TILE_W,TILE_H>>(dxdy);

    Val desc = SiftDescriptor(dxdyTiles);
    Val desc = Map<Reduce<BucketReduce>>(desc);

                                              // it seems like we shouldn't need a FIFO here, but we do: the changeRate downstream will only be ready every 1/8 cycles.
                                              // We need a tiny fifo to hold the reduceseq output, to keep it from stalling. (the scheduling isn't smart enough to know
                                              // that reduceSeq only has an output every 16 cycles, so it can't overlap them)

    Val desc = NAUTOFIFO<128>(desc);

                                 // sum and normalize the descriptors
    Val desc_broad = FanOut<2>(desc);

    Val desc0 = R.selectStream("d0",desc_broad,0);
    Val desc0 = NAUTOFIFO<256>(desc0);
  
    Val desc1 = R.selectStream("d1",desc_broad,1);
    Val desc1 = NAUTOFIFO<256>(desc1);

                                  // sum up all the mags in all the buckets
    Val desc1 = Flatten(desc1);

    Val desc1 = Map<ItoFR>(desc1);
  
    Val descpow2 = Map<Pow2>(desc1);
    Val desc_sum = Reduce<AddF>(descpow2);

    Val desc_sum = BoostRate<SqrtF>( desc_sum );
    Val desc_sum = Broadcast<<8,1>>(desc_sum);
    Val desc_sum = Broadcast<<TILES_X,TILES_Y>>(desc_sum);

    Val desc0 = Map<Map<ItoFR>>(desc0);

    Val desc = FanIn(desc0,desc_sum);

    Val desc = Zip(desc);
    Val desc = Map<Zip>(desc);
    Val desc = Map<Map<BoostRate<DivF>>>(desc);
    Val desc = Flatten(desc);
    Val desc = ReshapeArray<<TILES_X*TILES_Y*8,1>>(desc);
  
    Val desc_cc = R.concat{desc,posX,posY>;

    Val desc = FanIn(desc_cc);
    Val desc = Fmap{AddDescriptorPos>(desc);

    return desc;
  }
};

class AddImagePos:public UserFunction{
public:
  AddImagePos():UserFunction("AddImagePos", Array2d(IT,Uniform(W+15),H+15,0,0), true ){}
  Val define(Val i){
    Val trig = Map<ValueToTrigger>(i);
    Val pos = PosCounter<true>(trig);
    Val pos = Map<TupleToArray>(pos);
    Val pos = Map<Map<Sub<15>>>(pos);
    Val pos = Map<ArrayToTuple>(pos);
    Val res =  Zip(FanIn(i,pos));
    return res;
  }
};

class SiftTop:public UserFunction{
public:
  SiftTop():UserFunction("SiftTop",Array2d(Uint(8),1920,1080)){}
  Val define(Val inp){
    Val out = HarrisDXDY(inp);

    Val out = Pad<<7,8,7,8>>(out);
  
    Val dxdyBroad = FanOut<2>(out);

    Val internalW = W+15;
    Val internalH = H+15;

    //-------------------------------
    // right branch: make the harris bool
    Val right = R.selectStream("d1",dxdyBroad,1);
  
    Val right = NAUTOFIFO<128>(right);
  
    Val right = Map<harrisHarrisKernel>(right);
    Val harrisType = types.Float32;
  
    // now stencilify the harris
    Val right = Stencil<<-2,0,-2,0>>(right);
  
    Val right = Map<harrisNMS>(right);
    Val right = FilterCrop(right);
  
    //-------------------------------
    // left branch: make the dxdy int8 stencils
    Val left = R.selectStream("d0",dxdyBroad,0);

    if(GRAD_INT){
      left = Map<DXDYToInt8>(left);
    }

    Val left = NAUTOFIFO<2048/(types.tuple{GRAD_TYPE,GRAD_TYPE}:verilogBits())>(left);

    Val left = Stencil<<-TILES_X*TILE_W+1,0,-TILES_Y*TILE_H+1,0>>(left);

    Val left = Fmap<AddImagePos>(left);
    //-------------------------------

    // merge left/right
    Val out = Zip(left,right);

    Val out = Filter<<FILTER_RATE[1],FILTER_RATE[2]>,FILTER_FIFO>(out);
    Val out = NAUTOFIFO<FILTER_FIFO>(out);
    Val out = Map<SiftKernel>(out);

    // hack: we know how many descriptors will be written out, so just clamp the array to that size!
    // this will allow use to use the standard DMAs
    Val out = ClampToSize<<OUTPUT_COUNT,1>>(out);
    Val out = Flatten(out);

    // bitcast to uint8[8] for display...
    Val out = Map<Float>(out);
    Val out = Map<Bitcast<types.Array2d(types.Uint(8),4)>>(out);
    Val out = Flatten(out);
    Val out = Reshape<<(TILES_X*TILES_Y*8+2)*4,OUTPUT_COUNT>>(out);
  
    return out;
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
  
      std::ofstream out("out/soc_convgenTaps_8_"+std::to_string(V)+((autofifo==0)?"":"_autofifo")+".lua");
      out << header;
      if(autofifo==0){
        out << "R.AUTO_FIFOS = false\n";
      }else{
        out << "R.AUTO_FIFOS = true\n";
        out << "R.Z3_FIFOS = true\n";
      }
      
      out << "Val regs = SOC.axiRegs({},SDF{1,"+std::to_string(cycles)+"}):instantiate(\"regs\")\n";
        "local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate(\"ZynqNOC\")\n"
        "noc.extern=true\n";

      out << convInnerLua;
      out << convTopLua;
      out << "harness({regs.start,\n"
        "         G.AXIReadBurst{\"1080p.raw\",{1920,1080},T.Uint(8),noc.read},\n"
        "         ConvTop,\n"
        "         G.AXIWriteBurst{\"out/soc_convgenTaps_8_"+std::to_string(V)+((autofifo==0)?"":"_autofifo")+"\",noc.write},\n"
        "         regs.done},{filename=\"out/soc_convgenTaps_8_"+std::to_string(V)+((autofifo==0)?"":"_autofifo")+"\"},{regs})\n";

      out.close();
    }
  }
  
  return 0;
}


