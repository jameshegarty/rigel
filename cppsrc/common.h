#pragma once

constexpr int upToNearest( int roundto, int x ){
  return x + roundto - 1 - ((x + roundto - 1) % roundto);
}
