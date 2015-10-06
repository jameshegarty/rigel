
`include "../macros.vh"
////////////////////////////////////////////////////////////////////////////////////////////////////
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
// 02111-1307, USA.
//
// ©2013 - Roman Ovseitsev <romovs@gmail.com>
////////////////////////////////////////////////////////////////////////////////////////////////////

//##################################################################################################
//
// Module for receiving RGB565 pixel data from OV camera.
//
//##################################################################################################
// TODO Note this module reads in raw (1 byte) data
// This is also ordering the data as follows
// MSB |15-----8|7-----0| LSB
// PIX |  N+1   |   N   |
module CamReader (
    
    input       pclk,           // PCLK
    input       rst_n,            // 0 - Reset.
    input       [7:0] din,        // D0 - D7
    input       vsync,          // VSYNC
    input       href,           // HREF
    output reg  pixel_valid,     // Indicates that a pixel has been received.
    output reg  [15:0] pixel,   // RGB565 pixel.
    output      vstart,           // first pixel of frame
    output      hstart,           // first pixel of line

    input       raw,
    input       start, // pulse
    input       stop    // TODO does not do anythingh
    );

    reg         odd;
    reg         frameValid;
    reg         href_p2;
    reg         saw_vsync;
    
    // Only anding with pixel_valid just in case
    assign hstart = !href_p2 && href ;
    assign vstart = hstart && saw_vsync ;
    
    `REG(pclk, saw_vsync, 0, 
        vsync ? 1'b1 : (vstart ? 1'b0 : saw_vsync)
    )
    
    reg running;
    `REG(pclk, running, 0,
        start ? 1'b1 : running
    )
    wire [7:0] din2;
    assign din2 = din;//{din[0],din[1],din[2],din[3],din[4],din[5],din[6],din[7]};
    always @(posedge pclk or negedge rst_n) begin
        if (rst_n == 0) begin
            pixel_valid <= 0;
            odd <= 0;
            frameValid <= 0;
            href_p2 <= 1'b0;
        end 
        else begin
            href_p2 <= href;
            if (frameValid == 1 && vsync == 0 && href == 1) begin
                if (odd != raw ) begin    
                    pixel[7:0] <= din2;
                end
                else begin
                    pixel[15:8] <= din2;
                    pixel_valid <= 1;
                end
                odd <= ~odd;
                // skip inital frame in case we started receiving in the middle of it
            end 
            else if (running && frameValid == 0 && vsync == 1) begin
                frameValid <= 1;
            end
        end
    end
   
endmodule
