`ifndef MACROS_VH
`define MACROS_VH


//`define MMIO_OFFSET_SIZE        16
//`define MMIO_TRIBUF_NUM         3
//`define MMIO_CAM_NUM            2
//`define MMIO_SIZE               `MMIO_OFFSET_SIZE*(2+`MMIO_CAM_NUM+`MMIO_TRIBUF_NUM)
//
//`define MMIO_BASIC_OFFSET       0*`MMIO_OFFSET_SIZE
//`define MMIO_CMD                `MMIO_BASIC_OFFSET+0
//    `define CMD_START 5
//    `define CMD_STOP 9
//
//`define MMIO_DEBUG_OFFSET       1*`MMIO_OFFSET_SIZE
//`define MMIO_DEBUG(n)           (`MMIO_DEBUG_OFFSET + (n))
//
//`define MMIO_CAM_OFFSET(n)      (2+(n))*`MMIO_OFFSET_SIZE
//`define MMIO_CAM_CMD(n)         `MMIO_CAM_OFFSET(n)+0
//`define MMIO_CAM_RESP(n)        `MMIO_CAM_OFFSET(n)+1
//`define MMIO_CAM_RESP_CNT(n)    `MMIO_CAM_OFFSET(n)+2
//
//`define MMIO_TRIBUF_OFFSET(n)   (2+`MMIO_CAM_NUM+(n))*`MMIO_OFFSET_SIZE
//`define MMIO_FRAME_BYTES(n)     `MMIO_TRIBUF_OFFSET(n)+0
//`define MMIO_TRIBUF_ADDR(n)     `MMIO_TRIBUF_OFFSET(n)+1

`define MMIO_CAM_NUM            2
`define MMIO_TRIBUF_NUM         3

`define MMIO_BASIC_SIZE         1
`define MMIO_BASIC_OFFSET       0
`define MMIO_CMD                (`MMIO_BASIC_OFFSET+0)
    `define CMD_START           5
    `define CMD_STOP            9

`define MMIO_DEBUG_SIZE         16
`define MMIO_DEBUG_OFFSET       (`MMIO_BASIC_OFFSET + `MMIO_BASIC_SIZE)
`define MMIO_DEBUG(n)           (`MMIO_DEBUG_OFFSET + (n))

`define MMIO_CAM_SIZE           3
`define MMIO_CAM_OFFSET(n)      (`MMIO_DEBUG_OFFSET + `MMIO_DEBUG_SIZE + (`MMIO_CAM_SIZE * (n)))
`define MMIO_CAM_CMD(n)         (`MMIO_CAM_OFFSET(n)+0)
`define MMIO_CAM_RESP(n)        (`MMIO_CAM_OFFSET(n)+1)
`define MMIO_CAM_RESP_CNT(n)    (`MMIO_CAM_OFFSET(n)+2)

`define MMIO_TRIBUF_SIZE        2
`define MMIO_TRIBUF_OFFSET(n)   (`MMIO_CAM_OFFSET(`MMIO_CAM_NUM) + (`MMIO_TRIBUF_SIZE * (n)))
`define MMIO_FRAME_BYTES(n)     (`MMIO_TRIBUF_OFFSET(n)+0)
`define MMIO_TRIBUF_ADDR(n)     (`MMIO_TRIBUF_OFFSET(n)+1)

`define MMIO_PIPE_SIZE          4
`define MMIO_PIPE_OFFSET        `MMIO_TRIBUF_OFFSET(`MMIO_TRIBUF_NUM)
`define MMIO_PIPE(n)            (`MMIO_PIPE_OFFSET + (n))

`define MMIO_SIZE               (`MMIO_PIPE_OFFSET + `MMIO_PIPE_SIZE)
`define MMIO_STARTADDR          32'h7000_0000




`define REG(clk, r, init, in) \
    always @(posedge clk or negedge rst_n) begin \
        if (!rst_n) r <= (init); \
        else r <= (in); \
    end

`define REG_ERR(clk, r, cond) \
    always @(posedge clk or negedge rst_n) begin \
        if (!rst_n) r <= 1'b0; \
        else r <= (cond) ? 1'b1 : r; \
    end



`endif
