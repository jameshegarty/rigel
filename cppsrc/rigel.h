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
    void setName(std::string nam){name=nam;}
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
      //lst.push_back(std::string("  local ")+name+" = "+inp+"["+std::to_string(idx)+"]\n" );

      return inp+"["+std::to_string(idx)+"]";
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
    Val& setName( std::string name ){
      v->setName(name);
      return *this;
    }
  private:
    Value* v;
  };

  class Function{
  public:
    Function( std::string callstr ):callstring(callstr){}
    std::string callstring;
    Val operator()( Val inp );
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
    UserFunction( std::string name, RigelType* ty ):inputType(ty),Function(name),staticInterface(false){}
    UserFunction( std::string name, RigelType* ty, bool sfn ):inputType(ty),Function(name),staticInterface(sfn){}
    
    std::string luaDefinition(){
      Value* inp = new ParameterValue( inputType );
      out = define(inp);

      std::string res;
      if(staticInterface){
        res = std::string("local ")+callstring+" = G.Fmap{G.Function{ \""+callstring+"\", T.rv("+inputType->toLua()+std::string("),\nfunction("+inp->name+")\n");
      }else{
        res = std::string("local ")+callstring+" = G.SchedulableFunction{ \""+callstring+"\", "+inputType->toLua()+std::string(",\nfunction("+inp->name+")\n");
      }
      
      std::vector<std::string> lst;
      std::set<Value*> seen;

      std::string outName = out->toLua( lst, seen );
      
      for(const std::string& val: lst) {
        res += val;
      }

      res += std::string("  return ")+outName+"\n";
      
      if(staticInterface){
        res += "end}}\n";
      }else{
        res += "end}\n";
      }
      
      return res;
    }

    virtual Val define(Val i) = 0;
  private:
    const RigelType* inputType;
    const Value* out;
    const bool staticInterface;
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
      if(seen.count((Value*)this)==0){
        lst.push_back(std::string("  local ")+name+" = "+fn.callstring+"("+inp+")\n" );
      }
      seen.insert((Value*)this);
      return name;
    }
    Function fn;
  private:

  };

  Val Function::operator()( Val inp ) {
    return new ApplyValue( *this, inp );
  }

  class ConcatValue : public Value{
  public:
    ConcatValue( Value* lhs, Value* rhs ){
      inputs.push_back(lhs);
      inputs.push_back(rhs);
    }

    ConcatValue( Value* lhs, Value* rhs, Value* rhs2 ){
      inputs.push_back(lhs);
      inputs.push_back(rhs);
      inputs.push_back(rhs2);
    }

    ConcatValue( Value* lhs, Value* rhs, Value* rhs2, Value* rhs3 ){
      inputs.push_back(lhs);
      inputs.push_back(rhs);
      inputs.push_back(rhs2);
      inputs.push_back(rhs3);
    }

    ConcatValue( Value* lhs, Value* rhs, Value* rhs2, Value* rhs3, Value* rhs4, Value* rhs5, Value* rhs6, Value* rhs7 ){
      inputs.push_back(lhs);
      inputs.push_back(rhs);
      inputs.push_back(rhs2);
      inputs.push_back(rhs3);
      inputs.push_back(rhs4);
      inputs.push_back(rhs5);
      inputs.push_back(rhs6);
      inputs.push_back(rhs7);
    }

    ConcatValue( const std::vector<Value*>& arr ){
      inputs = arr;
    }

    virtual std::string toLua( std::vector<std::string>& lst, std::set<Value*>& seen ) const{
      if(seen.count((Value*)this)==0){
        std::string out = std::string("  local ")+name+" = R.concat{";
        for( const Value* v: inputs ){
          std::string inp = v->toLua(lst,seen);
          out += inp+", ";
        }
        out += "}\n";
        lst.push_back( out );
      }
      seen.insert((Value*)this);
      return name;
    }
  private:

  };

  Val Concat( Val lhs, Val rhs ){
    return Val(new ConcatValue(lhs,rhs));
  }

  Val Concat( const std::vector<Value*>& arr ){
    return Val(new ConcatValue(arr));
  }

  Val Concat( Val lhs, Val rhs, Val rhs2 ){
    return Val(new ConcatValue(lhs,rhs,rhs2));
  }

  Val Concat( Val lhs, Val rhs, Val rhs2, Val rhs3 ){
    return Val(new ConcatValue(lhs,rhs,rhs2,rhs3));
  }

  Val Concat( Val lhs, Val rhs, Val rhs2, Val rhs3, Val rhs4, Val rhs5, Val rhs6, Val rhs7 ){
    return Val(new ConcatValue(lhs,rhs,rhs2,rhs3,rhs4,rhs5,rhs6,rhs7));
  }

  class ConstValue : public Value{
  public:
    ConstValue( RigelType* ty, int val ):type(ty),intValue(val){}
    ConstValue( RigelType* ty, float* val ):type(ty),floatArrayValue(val){}
    virtual std::string toLua( std::vector<std::string>& lst, std::set<Value*>& seen ) const{
      if(seen.count((Value*)this)==0){
        Array2dType* array2dType = dynamic_cast<Array2dType*>(type);
        if( array2dType!=0 ){
          std::string t = std::string("  local ")+name+" = R.c("+type->toLua()+",{";
          for(int i=0; i< array2dType->W * array2dType->H; i++){
            //t += std::to_string(floatArrayValue[i])+", ";
            char tmp[100];
            snprintf(tmp, 100, "%1.15f",floatArrayValue[i]);
            t += std::string(tmp)+", ";
          }
          t+="})\n";
          lst.push_back( t );
        }else{
          lst.push_back(std::string("  local ")+name+" = R.c("+type->toLua()+","+std::to_string(intValue)+")\n" );
        }
      }
      seen.insert((Value*)this);
      return name;
    }

  private:
    RigelType* type;
    int intValue;
    float* floatArrayValue;
  };

  Val Const( RigelType* ty, int val ){
    return Val( new ConstValue( ty, val) );
  }

  Val Const( RigelType* over, int W, int H, float* val ){
    return Val( new ConstValue( Array2d( over, W, H ), val ) );
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


