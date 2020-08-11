#pragma once
#include <rigel.h>
#include <types.h>
#include <sdf.h>
#include <size.h>

using namespace Rigel;

namespace RigelLibrary{

  template< unsigned int l, unsigned int r, unsigned int b, unsigned int t>
  Val Crop(Val i){
    CoreFunction fn( std::string("G.Crop{{")+std::to_string(l)+","+std::to_string(r)+","+std::to_string(b)+","+std::to_string(t)+"}}" );
    return new ApplyValue(fn,i);
  }

  template< unsigned int l, unsigned int r, unsigned int b, unsigned int t>
  Val Pad(Val i){
    CoreFunction fn( std::string("G.Pad{{")+std::to_string(l)+","+std::to_string(r)+","+std::to_string(b)+","+std::to_string(t)+"}}" );
    return new ApplyValue(fn,i);
  }

  template< int l, int r, int b, int t>
  Val Stencil(Val i){
    CoreFunction fn( std::string("G.Stencil{{")+std::to_string(l)+","+std::to_string(r)+","+std::to_string(b)+","+std::to_string(t)+"}}" );
    return new ApplyValue(fn,i);
  }

  template< int l, int r, int b, int t, int W, int H>
  Val StencilOfStencils(Val i){
    CoreFunction fn( std::string("G.StencilOfStencils{{")+std::to_string(l)+","+std::to_string(r)+","+std::to_string(b)+","+std::to_string(t)+"},{"+std::to_string(W)+","+std::to_string(H)+"}}" );
    return new ApplyValue(fn,i);
  }

  template< int l, int r, int b, int t, class SDF>
  Val Stencil(Val i){
    SDF sdf;
    CoreFunction fn( std::string("G.Stencil{{")+std::to_string(l)+","+std::to_string(r)+","+std::to_string(b)+","+std::to_string(t)+"},"+sdf.toLua()+"}" );
    return new ApplyValue(fn,i);
  }

  template< class SDF, int FIFO_SIZE>
  Val Filter(Val i){
    SDF sdf;
    CoreFunction fn( std::string("G.Filter{"+sdf.toLua()+","+std::to_string(FIFO_SIZE)+"}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int W, unsigned int H, unsigned int V>
  Val AXIReadBurst( Val i ){
    CoreFunction fn( std::string("G.AXIReadBurst{\"frame_128.raw\",{")+std::to_string(W)+","+std::to_string(H)+"}, T.Uint(8), "+std::to_string(V)+", noc.read}" );
    return new ApplyValue(fn,i);
  }

  Val AXIWriteBurst( Val i ){
    CoreFunction fn( std::string("G.AXIWriteBurst{\"out/soc_simple\",noc.write}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int C >
  Val FanOut( Val i ){
    CoreFunction fn( std::string("G.FanOut{"+std::to_string(C)+"}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int C >
  Val NAUTOFIFO( Val i ){
    CoreFunction fn( std::string("G.NAUTOFIFO{"+std::to_string(C)+"}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int C >
  Val Rshift( Val i ){
    CoreFunction fn( std::string("G.Rshift{"+std::to_string(C)+"}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int C >
  Val RshiftE( Val i ){
    CoreFunction fn( std::string("G.RshiftE{"+std::to_string(C)+"}") );
    return new ApplyValue(fn,i);
  }

  template< class T, int W, int H, int (*FN)(int)>
  Val Const( Val i ){
    T ty;
    std::string inst = std::string("G.Const{T.Array2d(")+ty.toLua()+","+std::to_string(W)+","+std::to_string(H)+"),value={";
    for(int y=0; y<H; y++){
      for(int x=0; x<W; x++){
        inst += std::to_string(FN(y*W+x))+",";
      }
    }
    inst += "}}";
      
    CoreFunction fn( inst );
    return new ApplyValue(fn,i);
  }

  template< class T, int W, int H, float (*FN)(int)>
  Val Const( Val i ){
    T ty;
    std::string inst = std::string("G.Const{T.Array2d(")+ty.toLua()+","+std::to_string(W)+","+std::to_string(H)+"),value={";
    for(int y=0; y<H; y++){
      for(int x=0; x<W; x++){
        char tmp[100];
        float tf = FN(y*W+x);
        snprintf(tmp, 100, "%1.15f",tf);
        inst += std::string(tmp)+", ";

        //inst += std::to_string(FN(y*W+x))+",";
      }
    }
    inst += "}}";
      
    CoreFunction fn( inst );
    return new ApplyValue(fn,i);
  }

  template< class T, int iW, int iH, int oW, int oH, float (*FN)(int)>
  Val Const( Val i ){
    T ty;
    std::string inst = std::string("G.Const{T.Array2d(T.Array2d(")+ty.toLua()+","+std::to_string(iW)+","+std::to_string(iH)+"),"+std::to_string(oW)+","+std::to_string(oH)+"),value={";
    for(int oI=0; oI<oW*oH; oI++){
      inst += "{";
      for(int iI=0; iI<iW*iH; iI++){
        char tmp[100];
        float tf = FN( (oI*(iW*iH)) + iI );
        snprintf(tmp, 100, "%1.15f",tf);
        inst += std::string(tmp)+", ";

        //inst += std::to_string(FN(y*W+x))+",";
      }
      inst += "},";
    }
    inst += "}}";
      
    CoreFunction fn( inst );
    return new ApplyValue(fn,i);
  }

  template< class T, int C >
  Val Const( Val i ){
    T ty;
    CoreFunction fn( std::string("G.Const{"+ty.toLua()+","+std::to_string(C)+"}") );
    return new ApplyValue(fn,i);
  }

  // for floats
  template< class T, int N, int D >
  Val Const( Val i ){
    T ty;
    CoreFunction fn( std::string("G.Const{"+ty.toLua()+","+std::to_string(N)+"/"+std::to_string(D)+"}") );
    return new ApplyValue(fn,i);
  }

  template<class T>
  Val Bitcast( Val i ){
    T ty;
    CoreFunction fn( std::string("G.Bitcast{"+ty.toLua()+"}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int C >
  Val Add( Val i ){
    CoreFunction fn( std::string("G.Add{"+std::to_string(C)+"}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int C >
  Val Index( Val i ){
    CoreFunction fn( std::string("G.Index{"+std::to_string(C)+"}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int W, unsigned int H >
  Val Index( Val i ){
    CoreFunction fn( std::string("G.Index{{"+std::to_string(W)+","+std::to_string(H)+"}}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int W, unsigned int H >
  Val ReshapeArray( Val i ){
    CoreFunction fn( std::string("G.ReshapeArray{{"+std::to_string(W)+","+std::to_string(H)+"}}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int xl, unsigned int xh, unsigned int yl, unsigned int yh >
  Val Slice( Val i ){
    CoreFunction fn( std::string("G.Slice{{"+std::to_string(xl)+","+std::to_string(xh)+","+std::to_string(yl)+","+std::to_string(yh)+"}}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int l, unsigned int h >
  Val Slice( Val i ){
    CoreFunction fn( std::string("G.Slice{{"+std::to_string(l)+","+std::to_string(h)+"}}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int W, unsigned int H >
  Val Broadcast( Val i ){
    CoreFunction fn( std::string("G.Broadcast{{"+std::to_string(W)+","+std::to_string(H)+"}}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int W, unsigned int H >
  Val Tile( Val i ){
    CoreFunction fn( std::string("G.Tile{{"+std::to_string(W)+","+std::to_string(H)+"}}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int W, unsigned int H >
  Val ClampToSize( Val i ){
    CoreFunction fn( std::string("G.ClampToSize{{"+std::to_string(W)+","+std::to_string(H)+"}}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int C >
  Val FRtoI( Val i ){
    CoreFunction fn( std::string("G.FRtoI{"+std::to_string(C)+"}") );
    return new ApplyValue(fn,i);
  }

  Val Identity( Val i ){
    CoreFunction fn( std::string("G.Identity") );
    return new ApplyValue(fn,i);
  }

  Val FtoFR( Val i ){
    CoreFunction fn( std::string("G.FtoFR") );
    return new ApplyValue(fn,i);
  }

  Val UtoFR( Val i ){
    CoreFunction fn( std::string("G.UtoFR") );
    return new ApplyValue(fn,i);
  }

  Val ItoFR( Val i ){
    CoreFunction fn( std::string("G.ItoFR") );
    return new ApplyValue(fn,i);
  }

  Val AddAsync( Val i ){
    CoreFunction fn( std::string("G.Add{R.Async}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int C >
  Val GT( Val i ){
    CoreFunction fn( std::string("G.GT{"+std::to_string(C)+"}") );
    return new ApplyValue(fn,i);
  }

  Val GT( Val i ){
    CoreFunction fn( std::string("G.GT") );
    return new ApplyValue(fn,i);
  }

  Val GTF( Val i ){
    CoreFunction fn( std::string("G.GTF") );
    return new ApplyValue(fn,i);
  }

  Val GEF( Val i ){
    CoreFunction fn( std::string("G.GEF") );
    return new ApplyValue(fn,i);
  }

  Val LTF( Val i ){
    CoreFunction fn( std::string("G.LTF") );
    return new ApplyValue(fn,i);
  }

  Val And( Val i ){
    CoreFunction fn( std::string("G.And") );
    return new ApplyValue(fn,i);
  }

  Val SqrtF( Val i ){
    CoreFunction fn( std::string("G.SqrtF") );
    return new ApplyValue(fn,i);
  }

  Val Not( Val i ){
    CoreFunction fn( std::string("G.Not") );
    return new ApplyValue(fn,i);
  }

  Val Sel( Val i ){
    CoreFunction fn( std::string("G.Sel") );
    return new ApplyValue(fn,i);
  }

  Val SAD( Val i ){
    CoreFunction fn( std::string("G.SAD{T.Uint(16)}") );
    return new ApplyValue(fn,i);
  }

  Val ArgMin( Val i ){
    CoreFunction fn( std::string("G.ArgMin") );
    return new ApplyValue(fn,i);
  }

  Val Mul( Val i ){
    CoreFunction fn( std::string("G.Mul") );
    return new ApplyValue(fn,i);
  }

  Val MulF( Val i ){
    CoreFunction fn( std::string("G.MulF") );
    return new ApplyValue(fn,i);
  }

  Val DivF( Val i ){
    CoreFunction fn( std::string("G.DivF") );
    return new ApplyValue(fn,i);
  }

  Val MulE( Val i ){
    CoreFunction fn( std::string("G.MulE") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int C >
  Val MulE( Val i ){
    CoreFunction fn( std::string("G.MulE{"+std::to_string(C)+"}") );
    return new ApplyValue(fn,i);
  }

  template< int N, int D >
  Val MulF( Val i ){
    CoreFunction fn( std::string("G.MulF{"+std::to_string(N)+"/"+std::to_string(D)+"}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int C >
  Val AddE( Val i ){
    CoreFunction fn( std::string("G.AddE{"+std::to_string(C)+"}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int C >
  Val ToFloatRec( Val i ){
    CoreFunction fn( std::string("G.FloatRec{"+std::to_string(C)+"}") );
    return new ApplyValue(fn,i);
  }

  Val ToFloat( Val i ){
    CoreFunction fn( std::string("G.Float") );
    return new ApplyValue(fn,i);
  }

  Val AddE( Val i ){
    CoreFunction fn( std::string("G.AddE") );
    return new ApplyValue(fn,i);
  }

  Val AddF( Val i ){
    CoreFunction fn( std::string("G.AddF") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int C >
  Val Sub( Val i ){
    CoreFunction fn( std::string("G.Sub{"+std::to_string(C)+"}") );
    return new ApplyValue(fn,i);
  }

  Val SubE( Val i ){
    CoreFunction fn( std::string("G.SubE") );
    return new ApplyValue(fn,i);
  }

  Val SubF( Val i ){
    CoreFunction fn( std::string("G.SubF") );
    return new ApplyValue(fn,i);
  }

  Val Abs( Val i ){
    CoreFunction fn( std::string("G.Abs") );
    return new ApplyValue(fn,i);
  }

  Val UtoI( Val i ){
    CoreFunction fn( std::string("G.UtoI") );
    return new ApplyValue(fn,i);
  }

  Val ItoU( Val i ){
    CoreFunction fn( std::string("G.ItoU") );
    return new ApplyValue(fn,i);
  }

  Val LUTInvert( Val i ){
    CoreFunction fn( std::string("G.LUTInvert") );
    return new ApplyValue(fn,i);
  }

  Val Neg( Val i ){
    CoreFunction fn( std::string("G.Neg") );
    return new ApplyValue(fn,i);
  }

  Val NegF( Val i ){
    CoreFunction fn( std::string("G.NegF") );
    return new ApplyValue(fn,i);
  }

  Val Flatten( Val i ){
    CoreFunction fn( std::string("G.Flatten") );
    return new ApplyValue(fn,i);
  }

  Val Zip( Val i ){
    CoreFunction fn( std::string("G.Zip") );
    return new ApplyValue(fn,i);
  }

  Val ZipToArray( Val i ){
    CoreFunction fn( std::string("G.ZipToArray") );
    return new ApplyValue(fn,i);
  }

  Val ToColumns( Val i ){
    CoreFunction fn( std::string("G.ToColumns") );
    return new ApplyValue(fn,i);
  }

  Val FanIn( Val i ){
    CoreFunction fn( std::string("G.FanIn") );
    return new ApplyValue(fn,i);
  }

  Val Pow2( Val i ){
    CoreFunction fn( std::string("G.Pow2") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int C >
  Val AddMSBs( Val i ){
    CoreFunction fn( std::string("G.AddMSBs{"+std::to_string(C)+"}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int C >
  Val RemoveMSBs( Val i ){
    CoreFunction fn( std::string("G.RemoveMSBs{"+std::to_string(C)+"}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int C >
  Val RemoveLSBsE( Val i ){
    CoreFunction fn( std::string("G.RemoveLSBsE{"+std::to_string(C)+"}") );
    return new ApplyValue(fn,i);
  }

  template< bool C >
  Val PosCounter( Val i ){
    std::string t;
    if(C){
      t = std::string("G.PosCounter{true}");
    }else{
      t = std::string("G.PosCounter{false}");
    }
    CoreFunction fn( t );
    return new ApplyValue(fn,i);
  }

  Val Coeffs( Val i ){
    CoreFunction fn( std::string("RM.Storv(regs.coeffs)") );
    return new ApplyValue(fn,i);
  }

  Val TupleToArray( Val i ){
    CoreFunction fn( std::string("G.TupleToArray") );
    return new ApplyValue(fn,i);
  }

  Val ArrayToTuple( Val i ){
    CoreFunction fn( std::string("G.ArrayToTuple") );
    return new ApplyValue(fn,i);
  }

  Val ValueToTrigger( Val i ){
    CoreFunction fn( std::string("G.ValueToTrigger") );
    return new ApplyValue(fn,i);
  }

  Val Denormalize( Val i ){
    CoreFunction fn( std::string("G.Denormalize") );
    return new ApplyValue(fn,i);
  }

  template<Val (*FN)(Val)>
  Val Map( Val i ){
    Val tmp = FN(i);
    ApplyValue* tmpa = dynamic_cast<ApplyValue*>((Value*)tmp);
    
    CoreFunction fn( std::string("G.Map{"+tmpa->fn.callstring+"}") );
    return new ApplyValue(fn,i);
  }

  template<class T>
  Val Map( Val i ){
    T ifn;
    CoreFunction fn( std::string("G.Map{"+ifn.callstring+"}") );
    return new ApplyValue(fn,i);
  }

  template<Val (*FN)(Val)>
  Val Reduce( Val i ){
    Val tmp = FN(i);
    ApplyValue* tmpa = dynamic_cast<ApplyValue*>((Value*)tmp);
    
    CoreFunction fn( std::string("G.Reduce{"+tmpa->fn.callstring+"}") );
    return new ApplyValue(fn,i);
  }

  template< class T >
  Val Reduce( Val i ){
    T ifn;
    CoreFunction fn( std::string("G.Reduce{"+ifn.callstring+"}") );
    return new ApplyValue(fn,i);
  }

  template<Val (*FN)(Val)>
  Val BoostRate( Val i ){
    Val tmp = FN(i);
    ApplyValue* tmpa = dynamic_cast<ApplyValue*>((Value*)tmp);
    
    CoreFunction fn( std::string("G.BoostRate{"+tmpa->fn.callstring+"}") );
    return new ApplyValue(fn,i);
  }

  
}
