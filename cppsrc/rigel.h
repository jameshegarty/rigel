#pragma once
#include <string>
#include <vector>
#include <set>
#include <types.h>
#include <iostream>
                 
namespace Rigel{
  class Value{
  public:
    Value( Value* inp ):name(std::string("val")+std::to_string(valCount)){
      inputs.push_back(inp);
      valCount++;
    }
    Value():name(std::string("val")+std::to_string(valCount)){valCount++;}
    static int valCount;
    virtual std::string toLua( std::vector<std::string>& lst, std::set<Value*>& seen ) const{return "UNDEFVAL?";}
    std::string name;
  protected:   
    std::vector<Value*> inputs;
  private:
  };

  int Value::valCount = 0;

  class IndexValue : public Value{
  public:
    IndexValue( Value* inp, unsigned int idx ):Value(inp),idx(idx){}
    virtual std::string toLua( std::vector<std::string>& lst, std::set<Value*>& seen ) const{
      std::string inp = inputs[0]->toLua(lst,seen);
      lst.push_back(std::string("  local ")+name+" = "+inp+"["+std::to_string(idx)+"]\n" );

      return name;
    }
  private:
    unsigned int idx;
  };

  class Val{
  public:
    Val( Value* v ):v(v){}
    operator Value*() const { return v; }
    Val operator[](int i){
      return Val(new IndexValue( v, i));
    }
  private:
    Value* v;
  };

  class Function{
  public:
    Function( std::string callstr ):callstring(callstr){}
    std::string callstring;
    //    Val operator()( Val inp ) {
    //      return inp;
    //    }
  };

  class ParameterValue : public Value{
  public:
    ParameterValue( const RigelType* t ):ty(t){}
    virtual std::string toLua( std::vector<std::string>& lst, std::set<Value*>& seen ) const{return name;}
  private:
    const RigelType* ty;
  };

  // user defined function
  class UserFunction : public Function{
    public:
    UserFunction( std::string name, RigelType* ty ):inputType(ty),Function(name){
    }
      
    std::string luaDefinition(){
      Value* inp = new ParameterValue( inputType );
      out = define(inp);

      std::string res = std::string("local ")+callstring+" = G.SchedulableFunction{ \""+callstring+"\", "+inputType->toLua()+std::string(",\nfunction("+inp->name+")\n");

      std::vector<std::string> lst;
      std::set<Value*> seen;

      std::string outName = out->toLua( lst, seen );
      
      for(const std::string& val: lst) {
        res += val;
      }

      res += std::string("  return ")+outName+"\n";
      res += "end}\n";
      
      return res;
    }

    virtual Val define(Val i) = 0;
  private:
    const RigelType* inputType;
    const Value* out;
  };

  class CoreFunction : public Function{
  public:
    CoreFunction( std::string str ):Function(str){

    }
  };
  
  // apply a Function or FunctionGenerator
  class ApplyValue : public Value{
  public:
    ApplyValue( Function f, Value* inp ):fn(f),Value(inp){}
    virtual std::string toLua( std::vector<std::string>& lst, std::set<Value*>& seen ) const{
      std::string inp = inputs[0]->toLua(lst,seen);
      lst.push_back(std::string("  local ")+name+" = "+fn.callstring+"("+inp+")\n" );
      return name;
    }
    Function fn;
  private:

  };

  class ConcatValue : public Value{
  public:
    ConcatValue( Value* lhs, Value* rhs ){
      inputs.push_back(lhs);
      inputs.push_back(rhs);
    }
    
    virtual std::string toLua( std::vector<std::string>& lst, std::set<Value*>& seen ) const{
      
      std::string out = std::string("  local ")+name+" = R.concat{";
      for( const Value* v: inputs ){
        std::string inp = v->toLua(lst,seen);
        out += inp+", ";
      }
      out += "}\n";
        
      lst.push_back( out );
      return name;
    }
  private:

  };

  Val Concat( Val lhs, Val rhs ){
    return Val(new ConcatValue(lhs,rhs));
  }

  const char* header = "local R = require \"rigel\"\n"
"local SOC = require \"generators.soc\"\n"
"local harness = require \"generators.harnessSOC\"\n"
"local RM = require \"generators.modules\"\n"
"local C = require \"generators.examplescommon\"\n"
"local T = require \"types\"\n"
"local SDF = require \"sdf\"\n"
"local Zynq = require \"generators.zynq\"\n"
"local G = require \"generators.core\"\n"
"local Uniform = require \"uniform\"\n"
"local J = require \"common\"\n";

  std::string footer( Function fn, std::string filename ){
    return "harness({regs.start, "+fn.callstring+", regs.done},{filename=\"out/"+filename+"\"},{regs})\n";
  }
}


