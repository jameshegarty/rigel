#pragma once
#include <string>

class RigelType{
public:
  virtual std::string toLua() const = 0;
};


class UintType : public RigelType{
public:
  UintType( unsigned int prec, unsigned int exp):prec(prec),exp(exp){}
  virtual std::string toLua() const{return std::string("T.Uint(")+std::to_string(prec)+","+std::to_string(exp)+")";}
private:
  unsigned int prec;
  unsigned int exp;
};

UintType* Uint( unsigned int prec, unsigned int exp ){
  return new UintType(prec,exp);
}

UintType* Uint( unsigned int prec ){
  return new UintType(prec,0);
}

class IntType : public RigelType{
public:
  IntType( unsigned int prec, unsigned int exp):prec(prec),exp(exp){}
  virtual std::string toLua() const{return std::string("T.Int(")+std::to_string(prec)+","+std::to_string(exp)+")";}
private:
  unsigned int prec;
  unsigned int exp;
};

class Array2dType : public RigelType{
public:
  Array2dType(  RigelType* over,int W,int H):over(over),W(W),H(H){}
  RigelType* over;
  int W;
  int H;
  virtual std::string toLua() const{return std::string("T.Array2d("+over->toLua()+","+std::to_string(W)+","+std::to_string(H)+")");}
};

Array2dType* Array2d( RigelType* over, int W, int H){
  return new Array2dType( over, W, H);
}

class TupleType : public RigelType{
public:
  TupleType( RigelType* lhs, RigelType* rhs ){
    list.push_back(lhs);
    list.push_back(rhs);
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

class TriggerType : public RigelType{
public:
  virtual std::string toLua() const{return std::string("T.Trigger");}
};

TriggerType* Trigger(){ return new TriggerType; }
