#pragma once

template< unsigned int N, unsigned int D>
class Size{
 public:
  std::string toLua(){return std::string("{"+std::to_string(N)+","+std::to_string(D)+"}");}
};
