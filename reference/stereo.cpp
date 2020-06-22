#include <cstdlib>
#include <cstdio>

const unsigned int W = 720;
const unsigned int H = 400;
const unsigned int SEARCH_WINDOW = 64;
const unsigned int SAD_WIDTH = 8;
const unsigned int OFFSET_X = 20;
const unsigned int THRESH = 1000;

// this is what the HW block should do
// search for matches in the left image
// here we send in left/right right as separate images, to make the code easier to read: but note that
//       the HW needs to consume both left and right as the same time, interleaved
void doStereo( unsigned char* left, unsigned char* right, unsigned char* output ){
  for( int y=0; y<H; y++){
    for( int x=0; x<W; x++){
      unsigned short lowestSAD = 65535;
      unsigned char bestIndex = 0;
      bool SADset = false;
      
      for( int idx=0; idx<SEARCH_WINDOW; idx++){
        unsigned int SAD = 0;
        // for each patch in the search, compute SAD:
        for( int j=0; j<SAD_WIDTH; j++){
          for( int i=0; i<SAD_WIDTH; i++){
            int rx = x+(i-SAD_WIDTH+1);
            int ry = y+j-3;

            int lx = x+(i-SAD_WIDTH+1)-OFFSET_X-SEARCH_WINDOW+idx+1;
            int ly = y+j-3;

            
            short leftV = 0; // int9
            short rightV = 0; // int9
            if( rx>=0 && rx<W && ry>=0 && ry<H ){
              rightV = right[ ry*W+rx ];
            }
            
            if( lx>=0 && lx<W && ly>=0 && ly<H ){
              leftV = left[ ly*W+lx ];
            }

            short diff = leftV-rightV;
            SAD += (diff<0)?(-diff):diff;
          }
        }

        if( SAD<lowestSAD || !SADset ){
          lowestSAD = SAD;
          bestIndex = OFFSET_X+SEARCH_WINDOW-idx;
          SADset = true;
        }
      }

      if( lowestSAD>THRESH ){
        // filter out really terrible matches
        output[ y*W+x ] = 0;
      }else{
        output[ y*W+x ] = bestIndex;
      }
    }
  }
}

int main( int argc, char* argv[] ){
  printf("Usage: stereo input.raw output.raw\n");
  printf("input is 720x400 pixel {uint8,uint8} images, i.e., left and right image interleaved\n");
  printf("output is 720x400 pixel uint8 depth match value\n");
  
  if( argc!= 3 ){
    printf("Incorrect args!\n");
    return 1;
  }
  
  FILE* infile = fopen( argv[1], "rb" );
  if( infile==0 ){
    printf("error, could not find file %s\n",argv[1]);
    return 1;
  }

  unsigned char* inpInterleaved = (unsigned char*) malloc(W*H*2);
  unsigned char* left = (unsigned char*) malloc(W*H);
  unsigned char* right = (unsigned char*) malloc(W*H);
  unsigned char* out = (unsigned char*) malloc(W*H);
  int size = fread( inpInterleaved, 1, W*H*2, infile );

  for(int i=0; i<W*H; i++){
    left[i] = inpInterleaved[i*2];
    right[i] = inpInterleaved[i*2+1];
  }
  
  if( size!=W*H*2 ){
    printf("Error reading input\n");
    return 1;
  }

  fclose(infile);
  
  doStereo( left, right, out );

  FILE* outfile = fopen( argv[2], "wb" );
  fwrite( out, W*H, 1, outfile );
  fclose( outfile );

  return 0;
}
