library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library pll;

use work.types.all;

entity tilemap is
  port (
    clk : in std_logic;
    vga_hs, vga_vs : out std_logic;
    vga_r, vga_g, vga_b : out std_logic_vector(5 downto 0);
    vga_en : in std_logic
  );
end tilemap;

architecture arch of tilemap is
  signal clk_6 : std_logic;

  signal video_pos   : pos_t;
  signal video_sync  : sync_t;
  signal video_blank : blank_t;

  signal video_on : std_logic;
begin
  my_pll : entity pll.pll
  port map (
    refclk   => clk,
    rst      => '0',
    outclk_0 => clk_6,
    locked   => open
  );

  sync_gen : entity work.sync_gen
  port map (
    clk   => clk_6,
    cen   => '1',
    pos   => video_pos,
    sync  => video_sync,
    blank => video_blank
  );

  video_on <= not (video_blank.hblank or video_blank.vblank);
  vga_hs <= not (video_sync.hsync xor video_sync.vsync);
  vga_vs <= '1';
  vga_r <= "111111" when video_on = '1' and ((video_pos.x(2 downto 0) = "000") or (video_pos.y(2 downto 0) = "000")) else "ZZZZZZ";
  vga_g <= "111111" when video_on = '1' and video_pos.x(4) = '1' else "ZZZZZZ";
  vga_b <= "111111" when video_on = '1' and video_pos.y(4) = '1' else "ZZZZZZ";
end arch;
