#pragma once
#include <string>

class Uniform{
 public:
   Uniform( int v ):value(v){}
  std::string toLua() const{ return std::string("Uniform(")+std::to_string(value)+")"; }
 private:
  int value;
};
