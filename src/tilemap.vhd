library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library pll;

use work.types.all;

entity tilemap is
  port (
    clk : in std_logic;
    vga_r, vga_g, vga_b : out std_logic_vector(5 downto 0);
    vga_csync : out std_logic
  );
end tilemap;

architecture arch of tilemap is
  signal clk_12 : std_logic;
  signal cen_6 : std_logic;

  signal video_pos   : pos_t;
  signal video_sync  : sync_t;
  signal video_blank : blank_t;

  signal video_on : std_logic;

  -- RAM signals
  signal ram_addr : std_logic_vector(5 downto 0);
  signal ram_dout : byte_t;

  -- ROM signals
  signal tile_rom_addr : std_logic_vector(16 downto 0);
  signal tile_rom_dout : byte_t;

  -- The register that contains the colour and code of the next tile to be
  -- rendered.
  --
  -- These 16-bit words aren't stored contiguously in RAM, instead they are
  -- split into high and low bytes. The high bytes are stored in the upper-half
  -- of the RAM, while the low bytes are stored in the lower-half.
  signal tile_data : std_logic_vector(15 downto 0);

  -- The register that contains next two 4-bit pixels to be rendered.
  signal gfx_data : byte_t;

  -- tile code
  signal code : unsigned(9 downto 0);

  -- tile colour
  signal color : nibble_t;

  -- pixel data
  signal pixel : nibble_t;
  signal pixel_2 : nibble_t;

  signal pos_x : unsigned(2 downto 0);

  -- extract the components of the video position vectors
  alias col      : unsigned(4 downto 0) is video_pos.x(8 downto 4);
  alias row      : unsigned(3 downto 0) is video_pos.y(7 downto 4);
  alias offset_x : unsigned(3 downto 0) is video_pos.x(3 downto 0);
  alias offset_y : unsigned(3 downto 0) is video_pos.y(3 downto 0);
begin
  my_pll : entity pll.pll
  port map (
    refclk   => clk,
    rst      => '0',
    outclk_0 => clk_12,
    locked   => open
  );

  -- generate the 6MHz clock enable signal
  clock_divider_6 : entity work.clock_divider
  generic map (DIVISOR => 2)
  port map (clk => clk_12, cen => cen_6);

  sync_gen : entity work.sync_gen
  port map (
    clk   => clk_12,
    cen   => cen_6,
    pos   => video_pos,
    sync  => video_sync,
    blank => video_blank
  );

  ram : entity work.single_port_rom
  generic map (
    ADDR_WIDTH         => 6,
    INIT_FILE          => "rom/tiles.mif",
    ENABLE_RUNTIME_MOD => "YES"
  )
  port map (
    clk  => clk_12,
    addr => ram_addr,
    dout => ram_dout
  );

  rom : entity work.single_port_rom
  generic map (
    ADDR_WIDTH => 17,
    INIT_FILE  => "rom/fg.mif"
  )
  port map (
    clk  => clk_12,
    addr => tile_rom_addr,
    dout => tile_rom_dout
  );

  -- load tile data for each 8x8 tile
  tile_data_pipeline : process (clk_12)
  begin
    if rising_edge(clk_12) then
      case to_integer(offset_x) is
        when 10 =>
          -- load high byte from the scroll RAM
          ram_addr <= std_logic_vector('1' & col);

        when 11 =>
          -- latch high byte
          tile_data(15 downto 8) <= ram_dout;

          -- load low byte from the scroll RAM
          ram_addr <= std_logic_vector('0' & col);

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

  pos_x <= offset_x(3 downto 1)+1;

  -- load graphics data from the tile ROM
  tile_rom_addr <= std_logic_vector(code & video_pos.y(3) & pos_x(2) & video_pos.y(2 downto 0) & pos_x(1 downto 0));

  -- latch graphics data when rendering odd pixels
  latch_gfx_data : process (clk_12)
  begin
    if rising_edge(clk_12) then
      if cen_6 = '1' and video_pos.x(0) = '1' then
        gfx_data <= tile_rom_dout;
      end if;
    end if;
  end process;

  -- decode high/low pixels from the graphics data
  pixel <= gfx_data(7 downto 4) when video_pos.x(0) = '1' else gfx_data(3 downto 0);

  video_on <= not (video_blank.hblank or video_blank.vblank);
  vga_csync <= not (video_sync.hsync xor video_sync.vsync);

  process (clk_12)
  begin
    if rising_edge(clk_12) then
      if cen_6 = '1' then
        pixel_2 <= pixel;
        if video_on = '1' then
          vga_r <= pixel_2 & pixel_2(3 downto 2);
          vga_g <= pixel_2 & pixel_2(3 downto 2);
          vga_b <= pixel_2 & pixel_2(3 downto 2);
        else
          vga_r <= (others => '0');
          vga_g <= (others => '0');
          vga_b <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end arch;
