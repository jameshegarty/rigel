#include <fstream>
#include <rigel.h>
#include <types.h>
#include <library.h>
#include <string>

using namespace Rigel;
using namespace Rigel::Lib;

class Add200:public UserFunction{
public:
  Add200():UserFunction("Add200",Trigger()){}
  Val define(Val inp){
    Val readStream = AXIReadBurst<128,64,8>(inp);
    Val offset = Map< Add<200> >(readStream);
    return AXIWriteBurst(offset);
  }
};


int main(){
  Add200 add200;
  std::string add200lua = add200.luaDefinition();

  std::ofstream out("out/soc_simple.lua");
  out << add200lua;
  out.close();

  return 0;
}
