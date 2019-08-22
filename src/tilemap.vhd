-- Copyright (c) 2019 Josh Bassett
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.types.all;

entity tilemap is
  port (
    -- clock
    clk : in std_logic;

    -- video signals
    video : in video_t;

    -- graphics data
    data : out byte_t
  );
end tilemap;

architecture arch of tilemap is
  -- RAM signals
  signal ram_addr : std_logic_vector(TILE_RAM_ADDR_WIDTH-1 downto 0);
  signal ram_dout : byte_t;

  -- ROM signals
  signal tile_rom_addr : std_logic_vector(TILE_ROM_ADDR_WIDTH-1 downto 0);
  signal tile_rom_dout : byte_t;

  -- tile data
  signal tile_data : std_logic_vector(15 downto 0);

  -- graphics data
  signal gfx_data : byte_t;

  -- tile code
  signal code : unsigned(9 downto 0);

  -- tile colour
  signal color : nibble_t;

  -- pixel data
  signal pixel : nibble_t;

  -- extract the components of the video position vectors
  alias col      : unsigned(4 downto 0) is video.pos.x(8 downto 4);
  alias row      : unsigned(3 downto 0) is video.pos.y(7 downto 4);
  alias offset_x : unsigned(3 downto 0) is video.pos.x(3 downto 0);
  alias offset_y : unsigned(3 downto 0) is video.pos.y(3 downto 0);
begin
  tile_ram : entity work.single_port_rom
  generic map (
    ADDR_WIDTH => TILE_RAM_ADDR_WIDTH,
    INIT_FILE  => "rom/tiles.mif",

    -- XXX: for debugging
    ENABLE_RUNTIME_MOD => "YES"
  )
  port map (
    clk  => clk,
    addr => ram_addr,
    dout => ram_dout
  );

  tile_rom : entity work.single_port_rom
  generic map (
    ADDR_WIDTH => TILE_ROM_ADDR_WIDTH,
    INIT_FILE  => "rom/fg.mif"
  )
  port map (
    clk  => clk,
    addr => tile_rom_addr,
    dout => tile_rom_dout
  );

  -- load tile data for each 8x8 tile
  tile_data_pipeline : process (clk)
  begin
    if rising_edge(clk) then
      case to_integer(offset_x) is
        when 10 =>
          -- load high byte from the scroll RAM
          ram_addr <= std_logic_vector('1' & (col+1));

        when 11 =>
          -- latch high byte
          tile_data(15 downto 8) <= ram_dout;

          -- load low byte from the scroll RAM
          ram_addr <= std_logic_vector('0' & (col+1));

        when 12 =>
          -- latch low byte
          tile_data(7 downto 0) <= ram_dout;

        when 13 =>
          -- latch code
          code <= unsigned(tile_data(9 downto 0));

        when 15 =>
          -- latch colour
          color <= tile_data(15 downto 12);

        when others => null;
      end case;
    end if;
  end process;

  -- Load graphics data from the tile ROM.
  --
  -- While the current two pixels are being rendered, we need to fetch data for
  -- the next two pixels, so they are loaded in time to render them on the
  -- screen.
  load_gfx_data : block
    signal x : unsigned(2 downto 0);
    signal y : unsigned(3 downto 0);
  begin
    x <= offset_x(3 downto 1)+1;
    y <= offset_y(3 downto 0);

    tile_rom_addr <= std_logic_vector(code & y(3) & x(2) & y(2 downto 0) & x(1 downto 0));
  end block;

  -- Latch the graphics data from the tile ROM when rendering odd pixels (i.e.
  -- the second pixel in every pair of pixels).
  latch_gfx_data : process (clk)
  begin
    if rising_edge(clk) then
      if video.pos.x(0) = '1' then
        gfx_data <= tile_rom_dout;
      end if;
    end if;
  end process;

  -- decode high/low pixels from the graphics data
  pixel <= gfx_data(7 downto 4) when video.pos.x(0) = '0' else gfx_data(3 downto 0);

  -- set layer data
  data <= color & pixel;
end arch;
