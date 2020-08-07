#pragma once

template< unsigned int N, unsigned int D>
class SDF{
 public:
  std::string toLua(){return std::string("SDF{"+std::to_string(N)+","+std::to_string(D)+"}");}
};
