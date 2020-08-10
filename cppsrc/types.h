#pragma once
#include <string>
#include <uniform.h>

class RigelType{
public:
  virtual std::string toLua() const = 0;
};

template< unsigned int prec, unsigned int exp>
class UintValue : public RigelType{
public:
  UintValue(){}
  virtual std::string toLua() const{return std::string("T.Uint(")+std::to_string(prec)+","+std::to_string(exp)+")";}
private:
};

class UintType : public RigelType{
public:
  UintType( unsigned int prec, int exp):prec(prec),exp(exp){}
  virtual std::string toLua() const{return std::string("T.Uint(")+std::to_string(prec)+","+std::to_string(exp)+")";}
private:
  unsigned int prec;
  int exp;
};

UintType* Uint( unsigned int prec, int exp ){
  return new UintType( prec, exp );
}

UintType* Uint( unsigned int prec ){
  return new UintType(prec,0);
}

class IntType : public RigelType{
public:
  IntType( unsigned int prec, int exp):prec(prec),exp(exp){}
  virtual std::string toLua() const{return std::string("T.Int(")+std::to_string(prec)+","+std::to_string(exp)+")";}
private:
  unsigned int prec;
  int exp;
};

IntType* Int( unsigned int prec, int exp ){
  return new IntType(prec,exp);
}

IntType* Int( unsigned int prec ){
  return new IntType(prec,0);
}

class FloatRecType : public RigelType{
public:
  FloatRecType( int exp, int sig):exp(exp),sig(sig){}
  virtual std::string toLua() const{return std::string("T.FloatRec(")+std::to_string(exp)+","+std::to_string(sig)+")";}
private:
  int exp;
  int sig;
};

FloatRecType* FloatRec( unsigned int prec ){
  return new FloatRecType( 8, 24 );
}

template< unsigned int exp, unsigned int sig>
class FloatValue : public RigelType{
public:
  FloatValue(){}
  virtual std::string toLua() const{return std::string("T.Float(")+std::to_string(exp)+","+std::to_string(sig)+")";}
private:
};

class FloatType : public RigelType{
public:
  FloatType( int exp, int sig):exp(exp),sig(sig){}
  virtual std::string toLua() const{return std::string("T.Float(")+std::to_string(exp)+","+std::to_string(sig)+")";}
private:
  int exp;
  int sig;
};

FloatType* Float( unsigned int prec ){
  return new FloatType( 8, 24 );
}

template< class Ty, unsigned int W, unsigned int H>
class Array2dValue : public RigelType{
public:
  Array2dValue(){}
  virtual std::string toLua() const{
    Ty over;
    return std::string("T.Array2d("+over.toLua()+","+std::to_string(W)+","+std::to_string(H)+")");
  }
};

class Array2dType : public RigelType{
public:
  Array2dType(  RigelType* over,int W,int H):over(over),W(W),H(H),Wuni(Uniform(0)),Wisuni(false),Vwisuni(false),Vw(W),Vh(H),Vwuni(Uniform(0)){}
  Array2dType(  RigelType* over,Uniform W,int H):over(over),Wuni(W),H(H),Wisuni(true),Vh(H),Vwisuni(true),Vwuni(W){}
  Array2dType(  RigelType* over,Uniform W,int H, int Vw, int Vh):over(over),Wuni(W),H(H),Wisuni(true),Vw(Vw),Vh(Vh),Vwisuni(false),Vwuni(Uniform(0)){}
  RigelType* over;
  int W;
  Uniform Wuni;
  bool Wisuni;
  int H;
  int Vw;
  Uniform Vwuni;
  bool Vwisuni;
  int Vh;
  virtual std::string toLua() const{
    if( Wisuni ){
      if( Vwisuni ){
        return std::string("T.Array2d("+over->toLua()+","+Wuni.toLua()+","+std::to_string(H)+","+Vwuni.toLua()+","+std::to_string(Vh)+")");
      }else{
        return std::string("T.Array2d("+over->toLua()+","+Wuni.toLua()+","+std::to_string(H)+","+std::to_string(Vw)+","+std::to_string(Vh)+")");
      }
    }else{
      return std::string("T.Array2d("+over->toLua()+","+std::to_string(W)+","+std::to_string(H)+")");
    }
  }
};

Array2dType* Array2d( RigelType* over, Uniform W, int H){
  return new Array2dType( over, W, H);
}

Array2dType* Array2d( RigelType* over, Uniform W, int H, int Vw, int Vh){
  return new Array2dType( over, W, H, Vw, Vh );
}

Array2dType* Array2d( RigelType* over, int W, int H){
  return new Array2dType( over, W, H);
}

Array2dType* Array2d( RigelType* over, int W ){
  return new Array2dType( over, W, 1);
}

class TupleType : public RigelType{
public:
  TupleType( RigelType* lhs, RigelType* rhs ){
    list.push_back(lhs);
    list.push_back(rhs);
  }

  TupleType( RigelType* lhs, RigelType* rhs, RigelType* rhs1 ){
    list.push_back(lhs);
    list.push_back(rhs);
    list.push_back(rhs1);
  }

  TupleType( RigelType* lhs, RigelType* rhs, RigelType* rhs1, RigelType* rhs2 ){
    list.push_back(lhs);
    list.push_back(rhs);
    list.push_back(rhs1);
    list.push_back(rhs2);
  }

  std::vector<RigelType*> list;
  virtual std::string toLua() const{
    std::string t = std::string("T.Tuple{");
    for(int i=0; i<list.size(); i++){
      t += list[i]->toLua();
      if(i<list.size()-1){
        t+=",";
      }
    }
    return t+"}";
  }
};

TupleType* Tuple( RigelType* lhs, RigelType* rhs){
  return new TupleType(lhs,rhs);
}

TupleType* Tuple( RigelType* lhs, RigelType* rhs, RigelType* rhs1){
  return new TupleType(lhs,rhs, rhs1);
}

TupleType* Tuple( RigelType* lhs, RigelType* rhs, RigelType* rhs1, RigelType* rhs2){
  return new TupleType(lhs,rhs,rhs1,rhs2);
}

class TriggerType : public RigelType{
public:
  virtual std::string toLua() const{return std::string("T.Trigger");}
};

TriggerType* Trigger(){ return new TriggerType; }

class BoolType : public RigelType{
public:
  virtual std::string toLua() const{return std::string("T.Bool");}
};

BoolType* Bool(){ return new BoolType; }
