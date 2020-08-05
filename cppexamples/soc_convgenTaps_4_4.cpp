#include <fstream>
#include <rigel.h>
#include <types.h>
#include <library.h>
#include <string>

using namespace Rigel;
using namespace Rigel::Lib;

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

int main(){
  ConvInner convInner;
  std::string convInnerLua = convInner.luaDefinition();

  std::ofstream out("out/soc_convgenTaps_4_4.lua");
  out << convInnerLua;
  out.close();

  return 0;
}
