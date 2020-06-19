#include <cstdlib>
#include <cstdio>

const unsigned int W = 1920;
const unsigned int H = 1080;
const unsigned int CONVWIDTH = 8;

// this is what the HW block should do
void doConvolve( unsigned char* input, unsigned char* output, unsigned char* coeffs ){
  for( int y=0; y<H; y++){
    for( int x=0; x<W; x++){
      unsigned int acc = 0;

      for( int j=0; j<CONVWIDTH; j++){
        for( int i=0; i<CONVWIDTH; i++){
          int cx = x+i-3;
          int cy = y+j-3;
          if( cx>=0 && cx<W && cy>=0 && cy<H ){
            acc += (unsigned int)input[ cy*W+cx ] * (unsigned int)coeffs[ j*CONVWIDTH+i ];
          }
        }
      }
      output[ y*W+x ] = acc >> 11;
    }
  }
}

int main( int argc, char* argv[] ){
  printf("Usage: conv input.raw output.raw\n");
  printf("input/output are 1920x1080 pixel uint8 images\n");

  if( argc!= 3 ){
    printf("Incorrect args!\n");
    return 1;
  }
  
  FILE* infile = fopen( argv[1], "rb" );
  if( infile==0 ){
    printf("error, could not find file %s\n",argv[1]);
    return 1;
  }

  unsigned char* inp = (unsigned char*) malloc(W*H);
  unsigned char* out = (unsigned char*) malloc(W*H);
  int size = fread( inp, 1, W*H, infile );

  if( size!=W*H ){
    printf("Error reading input\n");
    return 1;
  }

  fclose(infile);
  
  // these coeffs _should not_ be hardcoded, but we include a default convolution kernel here for testing
  unsigned char coeffs[CONVWIDTH*CONVWIDTH];
  for(int i=0; i<CONVWIDTH*CONVWIDTH; i++){ coeffs[i]=i+1; }

  doConvolve( inp, out, coeffs );

  FILE* outfile = fopen( argv[2], "wb" );
  fwrite( out, W*H, 1, outfile );
  fclose( outfile );

  return 0;
}
