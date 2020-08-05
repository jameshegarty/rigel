#pragma once
#include <string>
#include <vector>
#include <set>
#include <types.h>
#include <iostream>
                 
namespace Rigel{

  class Function{
  public:
    Function( std::string callstr ):callstring(callstr){}
    std::string callstring;
  };

  class Value{
  public:
    Value( Value* inp):i(inp),name(std::string("val")+std::to_string(valCount)){valCount++;}
    Value():i(0),name(std::string("val")+std::to_string(valCount)){valCount++;}
    static int valCount;
    virtual std::string toLua( std::vector<std::string>& lst, std::set<Value*>& seen ) const{return "UNDEFVAL?";}
    std::string name;
  protected:   
    Value* i;
  private:
  };

  int Value::valCount = 0;
  
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

    virtual Value* define(Value* i) = 0;
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
      std::string inp = i->toLua(lst,seen);
      lst.push_back(std::string("  local ")+name+" = "+fn.callstring+"("+inp+")\n" );
      return name;
    }
    Function fn;
  private:

  };

typedef Value* Val;
}


