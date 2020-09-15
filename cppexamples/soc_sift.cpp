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

constexpr int GRAD_INT = true;
constexpr int GRAD_SCALE = 4; // <2 is bad

constexpr int W = 1920;
constexpr int H = 1080;

constexpr int TILES = 4;
constexpr int TILES_X = TILES;
constexpr int TILES_Y = TILES;
constexpr int TILE_W = 4;
constexpr int TILE_H = 4;

constexpr int FILTER_FIFO = 512*4;
constexpr int OUTPUT_COUNT = 3599;

constexpr int FILTER_RATE_N = OUTPUT_COUNT;
constexpr int FILTER_RATE_D = (W+15)*(H+15);

float GAUSS1D[5] = {14,62,104,62,14};

class ConvolveX:public UserFunction{
public:
  ConvolveX():UserFunction("ConvolveX", Array2d(FloatRec(32),5,1), true ){}
  Val define(Val i){
    
    Val c = Const( Float(32), 5, 1, GAUSS1D );
    Val c1 = Map<ToFloatRec<32>>(c);
    Val packed = Zip( Concat( i, c1 ) );
    Val conv = Map<MulF>(packed);
    Val conv1 = Reduce<AddF>(conv);
    Val conv2 = MulF<1,256>(conv1);
    return conv2;
  }
};

class ConvolveY:public UserFunction{
public:
  ConvolveY():UserFunction("ConvolveY", Array2d(FloatRec(32),1,5), true ){}
  Val define(Val i){
    //    float GAUSS[5] = {14,62,104,62,14};
    Val c = Const( Float(32), 1, 5, GAUSS1D );
    Val c1 = Map<ToFloatRec<32>>(c);
    Val packed = Zip( Concat( i, c1 ) );
    Val conv = Map<MulF>(packed);
    Val conv1 = Reduce<AddF>(conv);
    Val conv2 = MulF<1,256>(conv1);
    return conv2;
  }
};

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

HarrisDXDYKernel harrisDXDYKernel;

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

    //float K = 0.00000001f;

    Val Krigel = ToFloatRec<32>(Const<FloatValue<8,24>,1,100000000>(ValueToTrigger(i)));
    Val out = SubF( Concat( det, MulF( Concat( trsq, Krigel) ) ) );
    return out;
  }
};

class HarrisNMS:public UserFunction{
public:
  HarrisNMS():UserFunction("HarrisNMS", Array2d( FloatRec(32), 3, 3 ), true ){}
  Val define(Val i){
    Val N = GTF( Concat(Index<1,1>(i),Index<1,0>(i)));
    Val S = GTF( Concat(Index<1,1>(i),Index<1,2>(i)));
    Val E = GTF( Concat(Index<1,1>(i),Index<2,1>(i)));
    Val W = GTF( Concat(Index<1,1>(i),Index<0,1>(i)));
    Val nms = And(Concat(And(Concat(And(Concat(N,S)),E)),W));

    //float THRESH = 0.001f;
    Val THRESHrigel = ToFloatRec<32>(Const<FloatValue<8,24>,1,1000>(ValueToTrigger(i)));
    Val aboveThresh = GTF( Concat(Index<1,1>(i),THRESHrigel));
    Val out = And( Concat(nms, aboveThresh) );
    return out;
  }
};

class HarrisDXDY:public UserFunction{
public:
  HarrisDXDY():UserFunction("HarrisDXDY", Array2d( Uint(8), W, H ) ){}
  Val define(Val i){
    Val blurX =  Pad<2,2,0,0>(i);
    Val blurX1 = Map<ToFloatRec<32>>(blurX);
    Val blurX2 = Stencil<-4,0,0,0>(blurX1);
    Val blurX3 = Map<ConvolveX>(blurX2);
    Val blurX4 = Crop<4,0,0,0>(blurX3);

    Val blurXY = Pad<0,0,2,2>(blurX4);
    Val blurXY1 = Stencil<0,0,-4,0>(blurXY);
    Val blurXY2 = Map<ConvolveY>(blurXY1);
    Val blurXY3 = Crop<0,0,4,0>(blurXY2);

    Val dxdy = Pad<1,1,1,1>(blurXY3);
    Val dxdy1 = Stencil<-2,0,-2,0>(dxdy);
    Val dxdy2 = Map<HarrisDXDYKernel>(dxdy1);
    Val dxdy3 = Crop<2,0,2,0>(dxdy2);
  
    return dxdy3;
  }
};

HarrisDXDY harrisDXDY;

class BucketReduce:public UserFunction{
public:
  BucketReduce():UserFunction("BucketReduce", Tuple( Array2d( Int(32), 8 ), Array2d( Int(32), 8 ) ), true ){}
  Val define(Val i){
    Val z = Zip(i);
    return Map<AddAsync>(z);
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

    Val rhs = Map<And>(Zip( Concat( Xgt, Ygt) ));
  
    Val lhs = iFO[0];
    Val res = Zip( Concat( lhs, rhs ) );

    Val res2 = Map<And>(res);

    return res2;
  }
};

FilterCrop filterCrop;

class Bucketize:public UserFunction{
public:
  Bucketize():UserFunction("Bucketize", Tuple( FloatRec(32), FloatRec(32), FloatRec(32) ), true ){}
  Val define(Val i){
    Val dx = i[0];

    Val dy = i[1];
    Val mag = MulF<1024,GRAD_SCALE>(i[2]);
    Val mag1 = FRtoI<32>(mag);

    Val zero = Const( Int(32), 0 );

    Val zf = Const( FloatRec(32), 0 );
  
    Val dx_ge_0 = GEF( Concat( dx, zf) );
    Val dy_ge_0 = GEF( Concat( dy, zf) );
    Val dx_gt_dy = GTF( Concat( dx, dy) );
    Val dx_gt_negdy = GTF( Concat( dx, NegF(dy)) );
    Val dy_gt_negdx = GTF( Concat( dy, NegF(dx)) );
    Val negdx_gt_negdy = GTF( Concat( NegF(dx), NegF(dy)) );
    
    Val v0 = Sel( Concat( And(Concat(dx_ge_0,And(Concat(dy_ge_0,dx_gt_dy)))),mag1,zero) );
    Val v1 = Sel( Concat( And(Concat(dx_ge_0,And(Concat(dy_ge_0,Not(dx_gt_dy))))),mag1,zero) );
    Val v7 = Sel( Concat( And(Concat(dx_ge_0,And(Concat(Not(dy_ge_0),dx_gt_negdy)))),mag1,zero) );
    Val v6 = Sel( Concat( And(Concat(dx_ge_0,And(Concat(Not(dy_ge_0),Not(dx_gt_negdy))))),mag1,zero) );
    Val v2 = Sel( Concat( And(Concat(Not(dx_ge_0),And(Concat(dy_ge_0,dy_gt_negdx)))),mag1,zero) );
    Val v3 = Sel( Concat( And(Concat(Not(dx_ge_0),And(Concat(dy_ge_0,Not(dy_gt_negdx))))),mag1,zero) );
    Val v4 = Sel( Concat( And(Concat(Not(dx_ge_0),And(Concat(Not(dy_ge_0),negdx_gt_negdy)))),mag1,zero) );
    Val v5 = Sel( Concat( And(Concat(Not(dx_ge_0),And(Concat(Not(dy_ge_0),Not(negdx_gt_negdy))))),mag1,zero) );

    return TupleToArray( Concat(v0,v1,v2,v3,v4,v5,v6,v7) );
  }
};

class SiftMagPre:public UserFunction{
public:
  SiftMagPre():UserFunction("SiftMagPre", Tuple( FloatRec(32), FloatRec(32) ), true ){}
  Val define(Val i){
    Val dx = i[0];
    Val dy = i[1];
    Val magsq = AddF( Concat( MulF( Concat( dx, dx) ), MulF( Concat( dy, dy) ) ) );
    return magsq;
  }
};

SiftMagPre siftMagPre;

class SiftMag:public UserFunction{
public:
  SiftMag():UserFunction("SiftMag", Tuple( FloatRec(32), FloatRec(32), FloatRec(32) ) ){}
  Val define(Val inp){
    Val i = FanOut<2>(inp);
    Val gauss_weight = i[1][2];
    Val gauss_weight1 = NAUTOFIFO<128>(gauss_weight);
  
    Val magsq = siftMagPre(Slice<0,1>(i[0]));
    Val mag = BoostRate<SqrtF>( magsq );
    Val mag1 = NAUTOFIFO<1>(mag);

    Val out = MulF( FanIn( Concat( mag1, gauss_weight1) ) );
    return out;
  }
};

float GAUSS[] = {0.003184357568177f,0.003184357568177f,0.005802277792141f,0.005802277792141f,0.003184357568177f,0.003184357568177f,0.005802277792141f,0.005802277792141f,0.005802277792141f,0.005802277792141f,0.010572439450149f,0.010572439450149f,0.005802277792141f,0.005802277792141f,0.010572439450149f,0.010572439450149f,0.0086559813128914f,0.0086559813128914f,0.010572439450149f,0.010572439450149f,0.0086559813128914f,0.0086559813128914f,0.010572439450149f,0.010572439450149f,0.015772226286048f,0.015772226286048f,0.019264240688106f,0.019264240688106f,0.015772226286048f,0.015772226286048f,0.019264240688106f,0.019264240688106f,0.010572439450149f,0.010572439450149f,0.0086559813128914f,0.0086559813128914f,0.010572439450149f,0.010572439450149f,0.0086559813128914f,0.0086559813128914f,0.019264240688106f,0.019264240688106f,0.015772226286048f,0.015772226286048f,0.019264240688106f,0.019264240688106f,0.015772226286048f,0.015772226286048f,0.005802277792141f,0.005802277792141f,0.003184357568177f,0.003184357568177f,0.005802277792141f,0.005802277792141f,0.003184357568177f,0.003184357568177f,0.010572439450149f,0.010572439450149f,0.005802277792141f,0.005802277792141f,0.010572439450149f,0.010572439450149f,0.005802277792141f,0.005802277792141f,0.0086559813128914f,0.0086559813128914f,0.015772226286048f,0.015772226286048f,0.0086559813128914f,0.0086559813128914f,0.015772226286048f,0.015772226286048f,0.010572439450149f,0.010572439450149f,0.019264240688106f,0.019264240688106f,0.010572439450149f,0.010572439450149f,0.019264240688106f,0.019264240688106f,0.023529396710314f,0.023529396710314f,0.028738870039822f,0.028738870039822f,0.023529396710314f,0.023529396710314f,0.028738870039822f,0.028738870039822f,0.028738870039822f,0.028738870039822f,0.035101735133046f,0.035101735133046f,0.028738870039822f,0.028738870039822f,0.035101735133046f,0.035101735133046f,0.028738870039822f,0.028738870039822f,0.023529396710314f,0.023529396710314f,0.028738870039822f,0.028738870039822f,0.023529396710314f,0.023529396710314f,0.035101735133046f,0.035101735133046f,0.028738870039822f,0.028738870039822f,0.035101735133046f,0.035101735133046f,0.028738870039822f,0.028738870039822f,0.015772226286048f,0.015772226286048f,0.0086559813128914f,0.0086559813128914f,0.015772226286048f,0.015772226286048f,0.0086559813128914f,0.0086559813128914f,0.019264240688106f,0.019264240688106f,0.010572439450149f,0.010572439450149f,0.019264240688106f,0.019264240688106f,0.010572439450149f,0.010572439450149f,0.010572439450149f,0.010572439450149f,0.019264240688106f,0.019264240688106f,0.010572439450149f,0.010572439450149f,0.019264240688106f,0.019264240688106f,0.0086559813128914f,0.0086559813128914f,0.015772226286048f,0.015772226286048f,0.0086559813128914f,0.0086559813128914f,0.015772226286048f,0.015772226286048f,0.028738870039822f,0.028738870039822f,0.035101735133046f,0.035101735133046f,0.028738870039822f,0.028738870039822f,0.035101735133046f,0.035101735133046f,0.023529396710314f,0.023529396710314f,0.028738870039822f,0.028738870039822f,0.023529396710314f,0.023529396710314f,0.028738870039822f,0.028738870039822f,0.035101735133046f,0.035101735133046f,0.028738870039822f,0.028738870039822f,0.035101735133046f,0.035101735133046f,0.028738870039822f,0.028738870039822f,0.028738870039822f,0.028738870039822f,0.023529396710314f,0.023529396710314f,0.028738870039822f,0.028738870039822f,0.023529396710314f,0.023529396710314f,0.019264240688106f,0.019264240688106f,0.010572439450149f,0.010572439450149f,0.019264240688106f,0.019264240688106f,0.010572439450149f,0.010572439450149f,0.015772226286048f,0.015772226286048f,0.0086559813128914f,0.0086559813128914f,0.015772226286048f,0.015772226286048f,0.0086559813128914f,0.0086559813128914f,0.005802277792141f,0.005802277792141f,0.010572439450149f,0.010572439450149f,0.005802277792141f,0.005802277792141f,0.010572439450149f,0.010572439450149f,0.003184357568177f,0.003184357568177f,0.005802277792141f,0.005802277792141f,0.003184357568177f,0.003184357568177f,0.005802277792141f,0.005802277792141f,0.015772226286048f,0.015772226286048f,0.019264240688106f,0.019264240688106f,0.015772226286048f,0.015772226286048f,0.019264240688106f,0.019264240688106f,0.0086559813128914f,0.0086559813128914f,0.010572439450149f,0.010572439450149f,0.0086559813128914f,0.0086559813128914f,0.010572439450149f,0.010572439450149f,0.019264240688106f,0.019264240688106f,0.015772226286048f,0.015772226286048f,0.019264240688106f,0.019264240688106f,0.015772226286048f,0.015772226286048f,0.010572439450149f,0.010572439450149f,0.0086559813128914f,0.0086559813128914f,0.010572439450149f,0.010572439450149f,0.0086559813128914f,0.0086559813128914f,0.010572439450149f,0.010572439450149f,0.005802277792141f,0.005802277792141f,0.010572439450149f,0.010572439450149f,0.005802277792141f,0.005802277792141f,0.005802277792141f,0.005802277792141f,0.003184357568177f,0.003184357568177f,0.005802277792141f,0.005802277792141f,0.003184357568177f,0.003184357568177f};

float gaussFN(int i){
  return GAUSS[i];
}

class SiftDescriptor:public UserFunction{
public:
  SiftDescriptor():UserFunction("SiftDescriptor", Array2d(Array2d(Tuple(Int(8),Int(8)),TILE_W,TILE_H),TILES_X,TILES_Y) ){}
  Val define(Val inp){
    Val inpb = FanOut<3>(inp);
  
    Val gtrig = ValueToTrigger(inpb[0]);
    Val gtrig2 = NAUTOFIFO<128>(gtrig);

    //Val gweight = Const< Array2dValue<Array2dValue<FloatValue<8,24>,TILE_W,TILE_H>,TILES_X,TILES_Y>,GAUSS>(gtrig2);
    Val gweight = Const< FloatValue<8,24>, TILE_W, TILE_H, TILES_X, TILES_Y, gaussFN >(gtrig2);
    
    Val dx_first1 = Map<Map<Index<0>>>(inpb[1]);
    Val dx = NAUTOFIFO<128>(dx_first1);
    Val dy_first1 = Map<Map<Index<1>>>(inpb[2]);
    Val dy = NAUTOFIFO<128>(dy_first1);

    if(GRAD_INT){
      dx = Map<Map<ItoFR>>(dx);
      dy = Map<Map<ItoFR>>(dy);
      gweight = Map<Map<Identity>>(gweight);
      gweight = Map<Map<FtoFR>>(gweight);
    }

    Val dxFO = FanOut<2>(dx);
    Val dyFO = FanOut<2>(dy);

    Val dx0 = dxFO[0];
    Val dx0_1 = NAUTOFIFO<128>(dx0);

    Val dy0 = dyFO[0];
    Val dy0_1 = NAUTOFIFO<128>(dy0);

    Val maginp = Concat( dx0_1, dy0_1, gweight );

    Val maginp1 = FanIn(maginp);
    Val maginp2 = Zip(maginp1);
    Val maginp3 = Map<Zip>(maginp2);

    Val mag = Map<Map<SiftMag>>(maginp3);

    Val dx1 = dxFO[1];
    Val dx1_1 = NAUTOFIFO<128>(dx1);

    Val dy1 = dyFO[1];
    Val dy1_1 = NAUTOFIFO<128>(dy1);

    Val bucketInp = Concat(dx1_1,dy1_1,mag);
    Val bucketInp1 = FanIn(bucketInp);
    Val bucketInp2 = Zip(bucketInp1);
    Val bucketInp3 = Map<Zip>(bucketInp2);

    Val out = Map<Map<Bucketize>>(bucketInp3);
    return out;
  }
};

SiftDescriptor siftDescriptor;

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
      a.push_back( desc[i] );
    }

    Val out = TupleToArray(Concat(a));
    return out;
  }
};

AddDescriptorPos addDescriptorPos;

class SiftKernel:public UserFunction{
public:
  SiftKernel():UserFunction("SiftKernel", Tuple( Array2d( Tuple(Int(8),Int(8)), TILES_X*TILE_W, TILES_Y*TILE_H ), Tuple(Uint(16),Uint(16)) ) ){}
  Val define(Val i){
  
    Val inp = FanOut<2>(i);

    Val pos = inp[0][1];

    Val pos1 = NAUTOFIFO<1024>(pos);
  
    Val posFO = FanOut<2>(pos1);

    Val posX = posFO[0][0];
    Val posX1 = NAUTOFIFO<1024>(posX);
    Val posY = posFO[1][1];
    Val posY1 = NAUTOFIFO<1024>(posY);

    Val dxdy = inp[1][0];

    Val dxdyTiles = Tile< TILE_W, TILE_H >(dxdy);

    Val desc = siftDescriptor(dxdyTiles);
    Val desc_1 = Map<Reduce<BucketReduce>>(desc);
    
    // it seems like we shouldn't need a FIFO here, but we do: the changeRate downstream will only be ready every 1/8 cycles.
    // We need a tiny fifo to hold the reduceseq output, to keep it from stalling. (the scheduling isn't smart enough to know
    // that reduceSeq only has an output every 16 cycles, so it can't overlap them)

    Val desc2 = NAUTOFIFO<128>(desc_1);

    // sum and normalize the descriptors
    Val desc_broad = FanOut<2>(desc2);

    //Val desc0 = R.selectStream("d0",desc_broad,0);
    Val desc0 = desc_broad[0];
    Val desc0_1 = NAUTOFIFO<256>(desc0);
  
    //Val desc1 = R.selectStream("d1",desc_broad,1);
    Val desc1 = desc_broad[1];
    Val desc1_1 = NAUTOFIFO<256>(desc1);

    // sum up all the mags in all the buckets
    Val desc1_2 = Flatten(desc1_1);

    Val desc1_3 = Map<ItoFR>(desc1_2);
  
    Val descpow2 = Map<Pow2>(desc1_3);
    Val desc_sum = Reduce<AddF>(descpow2);

    Val desc_sum_1 = BoostRate<SqrtF>( desc_sum );
    Val desc_sum_2 = Broadcast<8,1>(desc_sum_1);
    Val desc_sum_3 = Broadcast<TILES_X,TILES_Y>(desc_sum_2);

    Val desc0_2 = Map<Map<ItoFR>>(desc0_1);

    Val desc_00 = FanIn( Concat( desc0_2, desc_sum_3 ) );

    Val desc_0 = Zip(desc_00);
    Val desc_1_1 = Map<Zip>(desc_0);
    Val desc_2 = Map<Map<BoostRate<DivF>>>(desc_1_1);
    Val desc_3 = Flatten(desc_2);
    Val desc_4 = ReshapeArray<TILES_X*TILES_Y*8,1>( desc_3 );
  
    Val desc_cc = Concat( desc_4, posX1, posY1 );

    Val desc_5 = FanIn(desc_cc);
    Val desc_6 = addDescriptorPos(desc_5);

    return desc_6;
  }
};

class AddImagePos:public UserFunction{
public:
  AddImagePos():UserFunction("AddImagePos", Array2d(Array2d(Tuple(Int(8),Int(8)),TILES_X*TILE_W,TILES_Y*TILE_H),Uniform(W+15),H+15,0,0), true ){}
  Val define(Val i){
    Val trig = Map<ValueToTrigger>(i);
    Val pos = PosCounter<true>(trig);
    Val pos1 = Map<TupleToArray>(pos);
    Val pos2 = Map<Map<Sub<15>>>(pos1);
    Val pos3 = Map<ArrayToTuple>(pos2);
    Val res =  Zip(FanIn( Concat( i, pos3 ) ));
    return res;
  }
};

AddImagePos addImagePos;

class SiftTop:public UserFunction{
public:
  SiftTop():UserFunction("SiftTop",Array2d(Uint(8),1920,1080)){}
  Val define(Val inp){
    Val out = harrisDXDY(inp);

    Val out1 = Pad<7,8,7,8>(out);
  
    Val dxdyBroad = FanOut<2>(out1);

    int internalW = W+15;
    int internalH = H+15;

    //-------------------------------
    // right branch: make the harris bool
    //Val right = R.selectStream("d1",dxdyBroad,1);
    Val right = dxdyBroad[1];
  
    Val right1 = NAUTOFIFO<128>(right);
  
    Val right2 = Map<HarrisHarrisKernel>(right1);
    //Val harrisType = types.Float32;
  
    // now stencilify the harris
    Val right3 = Stencil<-2,0,-2,0>(right2);
  
    Val right4 = Map<HarrisNMS>(right3);
    Val right5 = filterCrop(right4);
  
    //-------------------------------
    // left branch: make the dxdy int8 stencils
    //Val left = R.selectStream("d0",dxdyBroad,0);
    Val left = dxdyBroad[0];

    if(GRAD_INT){
      left = Map<DXDYToInt8>(left);
    }

    //Val left1 = NAUTOFIFO<2048/(types.tuple{GRAD_TYPE,GRAD_TYPE}:verilogBits())>(left);
    Val left1 = NAUTOFIFO<128>(left);

    Val left2 = Stencil<-TILES_X*TILE_W+1,0,-TILES_Y*TILE_H+1,0>(left1);

    Val left3 = addImagePos(left2);
    //-------------------------------

    // merge left/right
    Val out2 = Zip( Concat( left3, right5) );

    Val out3 = Filter<Size<FILTER_RATE_N,FILTER_RATE_D>,FILTER_FIFO>(out2);
    Val out4 = NAUTOFIFO<FILTER_FIFO>(out3);
    Val out5 = Map<SiftKernel>(out4);

    // hack: we know how many descriptors will be written out, so just clamp the array to that size!
    // this will allow use to use the standard DMAs
    Val out6 = ClampToSize<OUTPUT_COUNT,1>(out5);
    Val out7 = Flatten(out6);

    // bitcast to uint8[8] for display...
    Val out8 = Map<ToFloat>(out7);
    Val out9 = Map<Bitcast<Array2dValue<UintValue<8,0>,4,1>>>(out8);
    Val out10 = Flatten(out9);
    Val out11 = ReshapeArray<(TILES_X*TILES_Y*8+2)*4,OUTPUT_COUNT>(out10);
  
    return out11;
  }
};

int main(){
  ConvolveX convolveX;
  std::string convolveXLua = convolveX.luaDefinition();

  ConvolveY convolveY;
  std::string convolveYLua = convolveY.luaDefinition();

  ClampToInt8 clampToInt8;
  std::string clampToInt8Lua = clampToInt8.luaDefinition();

  DXDYToInt8 dXDYToInt8;
  std::string dXDYToInt8Lua = dXDYToInt8.luaDefinition();

  std::string harrisDXDYKernelLua = harrisDXDYKernel.luaDefinition();

  HarrisHarrisKernel harrisHarrisKernel;
  std::string harrisHarrisKernelLua = harrisHarrisKernel.luaDefinition();

  HarrisNMS harrisNMS;
  std::string harrisNMSLua = harrisNMS.luaDefinition();

  std::string harrisDXDYLua = harrisDXDY.luaDefinition();

  BucketReduce bucketReduce;
  std::string bucketReduceLua = bucketReduce.luaDefinition();

  std::string filterCropLua = filterCrop.luaDefinition();

  Bucketize bucketize;
  std::string bucketizeLua = bucketize.luaDefinition();

  std::string siftMagPreLua = siftMagPre.luaDefinition();

  SiftMag siftMag;
  std::string siftMagLua = siftMag.luaDefinition();

  std::string siftDescriptorLua = siftDescriptor.luaDefinition();

  std::string addDescriptorPosLua = addDescriptorPos.luaDefinition();

  SiftKernel siftKernel;
  std::string siftKernelLua = siftKernel.luaDefinition();

  std::string addImagePosLua = addImagePos.luaDefinition();

  SiftTop siftTop;
  std::string siftTopLua = siftTop.luaDefinition();


  for(int autofifo=0; autofifo<=1; autofifo++){
    for(int V=64; V<=256; V*=2){
      float VF = V;
      float invV = float(TILES_X*TILES_Y*TILE_W*TILE_H)/VF;
      float cycles = (W+15)*(H+15)*invV;
  
      std::string outfile = "soc_sift_4_"+std::to_string(V)+"_1080p"+((autofifo==0)?"":"_autofifo");

      std::ofstream outdesign("out/"+outfile+".design.txt");
      outdesign << std::string("SIFT 4 1080p");
      outdesign.close();

      std::ofstream outdesignT("out/"+outfile+".designT.txt");
      outdesignT << VF/256.f;
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

      out << "R.default_nettype_none = false\n";
      out << "local regs = SOC.axiRegs({},SDF{1,"+std::to_string(cycles)+"}):instantiate(\"regs\")\n"
        "local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate(\"ZynqNOC\")\n"
        "noc.extern=true\n";

      out << convolveXLua;
      out << convolveYLua;
      out << clampToInt8Lua;
      out << dXDYToInt8Lua;
      out << harrisDXDYKernelLua;
      out << harrisHarrisKernelLua;
      out << harrisNMSLua;
      out << harrisDXDYLua;
      out << bucketReduceLua;
      out << filterCropLua;
      out << bucketizeLua;
      out << siftMagPreLua;
      out << siftMagLua;
      out << siftDescriptorLua;
      out << addDescriptorPosLua;
      out << siftKernelLua;
      out << addImagePosLua;
      out << siftTopLua;

      std::string MHz = "";

      if(V==128){
	MHz = ",MHz=115";
      }else if(V==64){
	MHz = ",MHz=145";
      }else if(V==256){
	MHz = ",MHz=145";
      }
      
      out << "harness({regs.start,\n"
        "         G.AXIReadBurst{\"boxanim0000.raw\",{1920,1080},T.Uint(8),8,noc.read},\n"
        "         SiftTop,\n"
        "         G.AXIWriteBurst{\"out/"+outfile+"\",noc.write,R.Unoptimized},\n"
        "         regs.done},{filename=\"out/"+outfile+"\""+MHz+"},{regs})\n";

      out.close();
    }
  }
  
  return 0;
}


