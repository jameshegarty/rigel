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

module CamReader (d_i, vsync_i, href_i, pclk_i, rst_i, pixel_valid_o, pixel_o);
                     
    input       [7:0] d_i;        // D0 - D7
    input       vsync_i;          // VSYNC
    input       href_i;           // HREF
    input       pclk_i;           // PCLK
    input       rst_i;            // 0 - Reset.
    output reg  pixel_valid_o;     // Indicates that a pixel has been received.
    output reg  [15:0] pixel_o;   // RGB565 pixel.
    output reg  vstart_o;           // first pixel of frame
    output      hstart_o;           // first pixel of line
    
    reg         odd = 0;
    reg         frameValid = 0;
    reg         saw_vsync;
    reg         href_p2;
 
    // Only anding with pixel_valid just in case
    assign hstart = !href_p2 && href_i && pixel_valid_o;
    always @(posedge pclk_i) begin
        pixel_valid_o <= 0;
        vstart <= 1'b0;
        hstart <= 1'b0;
        href_p2 <= href_i;
        if (rst_i == 0) begin
            odd <= 0;
            frameValid <= 0;
            vstart <= 1'b0;
            hstart <= 1'b0;
            saw_vsync <= 1'b0;
        end else begin
            if (frameValid == 1 && vsync_i == 0 && href_i == 1) begin
                if (odd == 0) begin    
                    pixel_o[15:8] <= d_i;
                end
                else begin
                    pixel_o[7:0] <= d_i;
                    pixel_valid_o <= 1;
                    if (saw_vsync) begin
                        saw_vsync <= 1'b0;
                        vstart <=1'b0;
                    end
                end
                odd <= ~odd;
                // skip inital frame in case we started receiving in the middle of it
            end else if (frameValid == 0 && vsync_i == 1) begin
                frameValid <= 1;
                saw_vsync <= 1'b1;
            end
        end
    end
   
endmodule
