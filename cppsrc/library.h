#pragma once
#include <rigel.h>
#include <types.h>
#include <sdf.h>

using namespace Rigel;

namespace Rigel::Lib{

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
    
  template< class T, int C >
  Val Const( Val i ){
    T ty;
    CoreFunction fn( std::string("G.Const{"+ty.toLua()+","+std::to_string(C)+"}") );
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
  Val Broadcast( Val i ){
    CoreFunction fn( std::string("G.Broadcast{{"+std::to_string(W)+","+std::to_string(H)+"}}") );
    return new ApplyValue(fn,i);
  }

  Val AddAsync( Val i ){
    CoreFunction fn( std::string("G.Add{R.Async}") );
    return new ApplyValue(fn,i);
  }

  Val GT( Val i ){
    CoreFunction fn( std::string("G.GT") );
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
    //    Val tmp = FN(i);
    //    ApplyValue* tmpa = dynamic_cast<ApplyValue*>((Value*)tmp);
    
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

  
}
