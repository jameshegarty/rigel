#pragma once

constexpr int upToNearest( int roundto, int x ){
  int ox = x + roundto - 1 - ((x + roundto - 1) % roundto);
  return ox;
}
