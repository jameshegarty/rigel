#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>//Used for UART
#include <fcntl.h>//Used for UART
#include <termios.h>//Used for UART
#include <math.h>

int uart0_filestream;

void init(char* device, int uartClock){
  //-------------------------
  //----- SETUP USART 0 -----
  //-------------------------
  //At bootup, pins 8 and 10 are already set to UART0_TXD, UART0_RXD (ie the alt0 function) respectively
  uart0_filestream = -1;
                                                                      
  //OPEN THE UART
  //The flags (defined in fcntl.h):
  //Access modes (use 1 of these):
  //O_RDONLY - Open for reading only.
  //O_RDWR - Open for reading and writing.
  //O_WRONLY - Open for writing only.
  //
  //O_NDELAY / O_NONBLOCK (same function) - Enables nonblocking mode. When set read requests on the file can return immediately with a failure status
  //if there is no input immediately available (instead of blocking). Likewise, write requests can also return
  //immediately with a failure status if the output can't be written immediately.
  //
  //O_NOCTTY - When set and path identifies a terminal device, open() shall not cause the terminal device to become the controlling terminal for the process.
  uart0_filestream = open(device, O_RDWR | O_NOCTTY | O_NDELAY);//Open in non blocking read/write mode
  if (uart0_filestream == -1)
    {
      //ERROR - CAN'T OPEN SERIAL PORT
      printf("Error - Unable to open UART %s.  Ensure it is not in use by another application\n",device);
      exit(1);
    }

  //  int ret = fcntl(uart0_filestream, F_SETFL, O_RDWR);
  //  if (ret < 0) {
  //    perror("fcntl");
  //    exit(-1);
  //  }

  //CONFIGURE THE UART
  //The flags (defined in /usr/include/termios.h - see http://pubs.opengroup.org/onlinepubs/007908799/xsh/termios.h.html):
  //Baud rate:- B1200, B2400, B4800, B9600, B19200, B38400, B57600, B115200, B230400, B460800, B500000, B576000, B921600, B1000000, B1152000, B1500000, B2000000, B2500000, B3000000, B3500000, B4000000
  //CSIZE:- CS5, CS6, CS7, CS8
  //CLOCAL - Ignore modem status lines
  //CREAD - Enable receiver
  //IGNPAR = Ignore characters with parity errors
  //ICRNL - Map CR to NL on input (Use for ASCII comms where you want to auto correct end of line characters - don't use for bianry comms!)
  //PARENB - Parity enable
  //PARODD - Odd parity (else even)
  struct termios options;
  tcgetattr(uart0_filestream, &options);

  options.c_cflag = CS8 | CLOCAL | CREAD;

  int serror = cfsetispeed(&options,uartClock);
  if(serror!=0){printf("Set speed error\n");}

  serror = cfsetospeed(&options,uartClock);
  if(serror!=0){printf("Set speed error\n");}

  /*
  if(uartClock==57600){
    options.c_cflag = B57600 | CS8 | CLOCAL | CREAD;//<Set baud rate
    printf("57600\n");
  }else if(uartClock==19200){
    options.c_cflag = B19200 | CS8 | CLOCAL | CREAD;//<Set baud rate
    printf("B19200\n");
  }else if(uartClock==9600){
    options.c_cflag = B9600 | CS8 | CLOCAL | CREAD;//<Set baud rate
    printf("9600 B \n");
  }else{
    printf("Unsupported uart clock %d\n",uartClock);
    exit(1);
    } */
  options.c_iflag = IGNPAR;
  options.c_oflag = 0;
  options.c_lflag = 0;

  cfmakeraw(&options); 

  tcflush(uart0_filestream, TCIFLUSH);
  tcsetattr(uart0_filestream, TCSANOW, &options);

  ////////
  struct termios readopt;
  tcgetattr(uart0_filestream, &readopt);
  int ispeed = cfgetispeed(&readopt);
  printf("READ SPEED %d\n",ispeed);

  int ospeed = cfgetispeed(&readopt);
  printf("Out SPEED %d\n",ospeed);
}

void transmit(unsigned char* tx_buffer, int size){
  //  printf("SEND %s\n",tx_buffer);
  printf("SEND\n");
  if (uart0_filestream != -1){
    int count = write(uart0_filestream, tx_buffer, size); //Filestream, bytes to write, number of bytes to write
    if (count < 0){
      printf("UART TX error\n");
    }
    printf("tx COUNT %d\n",count);
  }
}

int receive(unsigned char* rx_buffer, int expectedSize){
  //----- CHECK FOR ANY RX BYTES -----
  if (uart0_filestream != -1){
    // Read up to 255 characters from the port if they are there
    int rx_length = read(uart0_filestream, rx_buffer, expectedSize); //Filestream, buffer to store in, number of bytes to read (max)

    if (rx_length < 0){
      //An error occured (will occur if there are no bytes)
      printf("RX error, len <0\n");
    }else if (rx_length == 0){
      //No data waiting
      printf("Error, no data\n");
    }else{
      //Bytes received
      rx_buffer[rx_length] = '\0';
      //      printf("%d bytes read : %s\n", rx_length, rx_buffer);
      printf("%d bytes read\n", rx_length);
      //      printf("%d\n",rx_length);
    }

    return rx_length;
  }
}

void closeuart(){
  printf("Close UART\n");
  close(uart0_filestream);
}

int main(int argc, char* argv[]){

  int baud = 115200;
  init("/dev/tty.usbserial-142B",baud);

  FILE *f = fopen("frame_64.raw", "rb");
  fseek(f, 0, SEEK_END);
  long fsize = ftell(f);
  fseek(f, 0, SEEK_SET);  //same as rewind(f);

  unsigned char *txBuffer = malloc(fsize + 1);
  unsigned char *rxBuffer = malloc(fsize + 1);
  fread(txBuffer, fsize, 1, f);
  fclose(f);

  txBuffer[fsize] = 0;

  int block = 512;

  float sleepTime = (block*8)/((float)baud);
  sleepTime *= 1000000;
  sleepTime *= 2.0f;

  printf("TOT SIZE %d\n", fsize);
  for(int i=0; i<fsize; i+=block){
    transmit(txBuffer+i, block);
    printf("TXDONE\n");
    //sleep(1);
    usleep(sleepTime);
    receive(rxBuffer+i, block);
  }

  FILE *of = fopen("uart.raw","wb");
  fwrite(rxBuffer,1,fsize,of);
  fclose(of);
  
  closeuart();
}
