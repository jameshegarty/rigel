#pragma once
#include <rigel.h>
#include <types.h>

using namespace Rigel;

namespace Rigel::Lib{

  template< unsigned int l, unsigned int r, unsigned int b, unsigned int t>
  Val Crop(Val i){
    //CoreFunction(std::string();
    Val res;
    return res;
  }

  template< unsigned int W, unsigned int H, unsigned int V>
  Val AXIReadBurst( Val i ){
    CoreFunction fn( std::string("G.AXIReadBurst{\"frame_128.raw\",{")+std::to_string(W)+","+std::to_string(H)+"}, u(8), "+std::to_string(V)+", noc.read}" );
    return new ApplyValue(fn,i);
  }

  Val AXIWriteBurst( Val i ){
    CoreFunction fn( std::string("G.AXIWriteBurst{\"out/soc_simple\"}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int C >
  Val Rshift( Val i ){
    CoreFunction fn( std::string("G.Rshift{"+std::to_string(C)+"}") );
    return new ApplyValue(fn,i);
  }

  template< unsigned int C >
  Val Add( Val i ){
    CoreFunction fn( std::string("G.Add{"+std::to_string(C)+"}") );
    return new ApplyValue(fn,i);
  }

  Val AddAsync( Val i ){
    CoreFunction fn( std::string("G.Add{R.Async}") );
    return new ApplyValue(fn,i);
  }

  Val Mul( Val i ){
    CoreFunction fn( std::string("G.Mul") );
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

  Val TupleToArray( Val i ){
    CoreFunction fn( std::string("G.TupleToArray") );
    return new ApplyValue(fn,i);
  }

  Val ArrayToTuple( Val i ){
    CoreFunction fn( std::string("G.ArrayToTuple") );
    return new ApplyValue(fn,i);
  }

  template<Val (*FN)(Val)>
  Val Map( Val i ){
    Val tmp = FN(i);
    ApplyValue* tmpa = dynamic_cast<ApplyValue*>(tmp);
    
    CoreFunction fn( std::string("G.Map{"+tmpa->fn.callstring+"}") );
    return new ApplyValue(fn,i);
  }

  template<Val (*FN)(Val)>
  Val Reduce( Val i ){
    Val tmp = FN(i);
    ApplyValue* tmpa = dynamic_cast<ApplyValue*>(tmp);
    
    CoreFunction fn( std::string("G.Reduce{"+tmpa->fn.callstring+"}") );
    return new ApplyValue(fn,i);
  }

  
}
