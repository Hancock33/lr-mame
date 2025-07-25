// license:BSD-3-Clause
// copyright-holders:Sandro Ronco, hap
/*******************************************************************************

Saitek RISC 2500, Mephisto Montreux

The chess engine (The King) is also compatible with Tasc's The ChessMachine
software. The hardware+software appears to have been subcontracted to Tasc.
It has similarities with Tasc R30.

To make sure it continues the game at next power-on, press the OFF button before
exiting MAME. If nvram is broken somehow, boot with the BACK button held down.

Hardware notes:
- PCB label: TASC23C
- ARM2 CPU(VY86C010) @ 14.16MHz
- 128KB ROM, 128KB RAM*
- SED1520, custom LCD screen
- 8*8 chessboard buttons, 16 leds, piezo

*: Sold with 128KB RAM by default. This can be easily increased up to 2MB
by the user(chesscomputer owner, but also the MAME user in this case).
The manual also says that RAM is expandable.

According to Saitek's repair manual, there is a GAL and a clock frequency
divider chip, ROM access goes through it. This allows reading from slow EPROM
while the chess engine resides in faster RAM. The piezo output routine is
also in ROM, it would be way too high-pitched at full speed.

Undocumented buttons:
- hold LEFT+RIGHT on boot to start the QC TestMode
- hold UP+DOWN on boot to start the TestMode

TODO:
- bootrom disable timer shouldn't be needed, real ARM has already fetched the next opcode
- More accurate dynamic cpu clock divider, without the cost of emulation speed.
  The current implementation catches almost everything, luckily ARM opcodes have a
  fixed length. It only fails to detect ALU opcodes that directly modify pc(R15).
  It also possibly has problems with very short subroutine calls from ROM to RAM,
  but I tested for those and the shortest one is more than 50 cycles.

*******************************************************************************/

#include "emu.h"

#include "cpu/arm/arm.h"
#include "machine/nvram.h"
#include "machine/ram.h"
#include "machine/sensorboard.h"
#include "sound/dac.h"
#include "video/pwm.h"
#include "video/sed1520.h"

#include "emupal.h"
#include "screen.h"
#include "speaker.h"

// internal artwork
#include "mephisto_montreux.lh"
#include "saitek_risc2500.lh"


namespace {

class risc2500_state : public driver_device
{
public:
	risc2500_state(const machine_config &mconfig, device_type type, const char *tag) :
		driver_device(mconfig, type, tag),
		m_maincpu(*this, "maincpu"),
		m_boot_view(*this, "boot_view"),
		m_rom(*this, "maincpu"),
		m_ram(*this, "ram"),
		m_nvram(*this, "nvram"),
		m_board(*this, "board"),
		m_led_pwm(*this, "led_pwm"),
		m_lcdc(*this, "lcdc"),
		m_screen(*this, "screen"),
		m_dac(*this, "dac"),
		m_inputs(*this, "IN.%u", 0),
		m_lcd_dmz(*this, "dmz%u.%u.%u", 0U, 0U, 0U),
		m_lcd_digit(*this, "digit%u", 0U),
		m_lcd_seg(*this, "seg%u.%u", 0U, 0U),
		m_lcd_sym(*this, "sym%u", 0U)
	{ }

	DECLARE_INPUT_CHANGED_MEMBER(on_button);

	void risc2500(machine_config &config);
	void montreux(machine_config &config);

protected:
	virtual void machine_start() override ATTR_COLD;
	virtual void machine_reset() override ATTR_COLD;

private:
	required_device<arm_cpu_device> m_maincpu;
	memory_view m_boot_view;
	required_region_ptr<u32> m_rom;
	required_device<ram_device> m_ram;
	required_device<nvram_device> m_nvram;
	required_device<sensorboard_device> m_board;
	required_device<pwm_display_device> m_led_pwm;
	required_device<sed1520_device> m_lcdc;
	required_device<screen_device> m_screen;
	required_device<dac_2bit_ones_complement_device> m_dac;
	required_ioport_array<8> m_inputs;
	output_finder<12, 7, 6> m_lcd_dmz;
	output_finder<12> m_lcd_digit;
	output_finder<12, 8> m_lcd_seg;
	output_finder<14> m_lcd_sym;

	emu_timer *m_boot_timer;

	bool m_power = false;
	u32 m_control = 0;
	u32 m_prev_pc = 0;
	u64 m_prev_cycle = 0;

	void risc2500_mem(address_map &map) ATTR_COLD;

	u32 screen_update(screen_device &screen, bitmap_rgb32 &bitmap, const rectangle &cliprect);
	SED1520_UPDATE_CB(sed1520_update);

	u32 input_r();
	void control_w(offs_t offset, u32 data, u32 mem_mask = ~0);
	u32 rom_r(offs_t offset);
	void power_off();

	u32 disable_bootrom_r();
	TIMER_CALLBACK_MEMBER(disable_bootrom) { m_boot_view.select(1); }
};



/*******************************************************************************
    Initialization
*******************************************************************************/

void risc2500_state::machine_start()
{
	m_lcd_dmz.resolve();
	m_lcd_digit.resolve();
	m_lcd_seg.resolve();
	m_lcd_sym.resolve();

	m_boot_timer = timer_alloc(FUNC(risc2500_state::disable_bootrom), this);
	m_boot_view[1].install_ram(0, m_ram->size() - 1, m_ram->pointer());
	m_nvram->set_base(m_ram->pointer(), m_ram->size());

	// register for savestates
	save_item(NAME(m_power));
	save_item(NAME(m_control));
	save_item(NAME(m_prev_pc));
	save_item(NAME(m_prev_cycle));
}

void risc2500_state::machine_reset()
{
	m_boot_view.select(0);
	m_boot_timer->adjust(attotime::never);

	m_power = true;
	m_control = 0;
	m_prev_pc = m_maincpu->pc();
	m_prev_cycle = m_maincpu->total_cycles();
}



/*******************************************************************************
    Video
*******************************************************************************/

u32 risc2500_state::screen_update(screen_device &screen, bitmap_rgb32 &bitmap, const rectangle &cliprect)
{
	// forward to SED1520
	return m_lcdc->screen_update(screen, m_screen->curbitmap().as_ind16(), cliprect);
}

SED1520_UPDATE_CB(risc2500_state::sed1520_update)
{
	for (int c = 0; c < 12; c++)
	{
		u8 data = 0;

		// 12 characters 5 x 7
		for (int x = 0; x < 5; x++)
		{
			if (lcd_on)
				data = bitswap<8>(dram[c * 5 + x], 6,5,0,1,2,3,4,7);

			for (int y = 1; y < 8; y++)
				m_lcd_dmz[11 - c][y - 1][4 - x] = BIT(data, y);
		}

		// LCD digits and symbols
		int data_addr = 80 + c * 5;
		if (lcd_on)
		{
			data = ((dram[data_addr + 1] & 0x3) << 5) | ((dram[data_addr + 2] & 0x7) << 2) | (dram[data_addr + 4] & 0x3);
			data = bitswap<8>(data, 7,3,0,1,4,6,5,2) | ((dram[data_addr - 1] & 0x04) ? 0x80 : 0);
		}

		for (int s = 0; s < 8; s++)
			m_lcd_seg[11 - c][s] = BIT(data, s);

		m_lcd_digit[11 - c] = data;
		m_lcd_sym[c] = lcd_on ? BIT(dram[data_addr + 1], 2) : 0;
	}

	m_lcd_sym[12] = lcd_on ? BIT(dram[0x73], 0) : 0;
	m_lcd_sym[13] = lcd_on ? BIT(dram[0x5a], 0) : 0;

	return 0;
}



/*******************************************************************************
    I/O
*******************************************************************************/

// soft power on/off

INPUT_CHANGED_MEMBER(risc2500_state::on_button)
{
	if (newval && !m_power)
	{
		m_maincpu->set_input_line(INPUT_LINE_RESET, CLEAR_LINE);
		machine_reset();
	}
}

void risc2500_state::power_off()
{
	m_power = false;
	m_maincpu->set_input_line(INPUT_LINE_RESET, ASSERT_LINE);

	// clear display
	m_lcdc->reset();
	m_led_pwm->clear();
}


// main I/O

u32 risc2500_state::input_r()
{
	u32 data = 0;

	for (int i = 0; i < 8; i++)
	{
		if (BIT(m_control, i))
		{
			data |= m_inputs[i]->read() << 24;
			data |= m_board->read_rank(i, true);
		}
	}

	if (!machine().side_effects_disabled())
		m_maincpu->set_input_line(ARM_FIRQ_LINE, CLEAR_LINE);

	return data;
}

void risc2500_state::control_w(offs_t offset, u32 data, u32 mem_mask)
{
	if (mem_mask != 0xffffffff)
		logerror("control_w unexpected mem_mask %08X\n", mem_mask);

	// lcd
	if (BIT(m_control & ~data, 27))
	{
		if (BIT(data, 26))
			m_lcdc->data_write(data);
		else
			m_lcdc->control_write(data);
	}

	// leds
	m_led_pwm->matrix(data >> 30, ~data & 0xff);

	// speaker
	m_dac->write(data >> 28 & 3);

	// power-off
	if (BIT(m_control & ~data, 24))
		power_off();

	m_control = data;
}

u32 risc2500_state::disable_bootrom_r()
{
	// disconnect bootrom from the bus after next opcode
	if (!machine().side_effects_disabled() && m_boot_timer->remaining().is_never())
		m_boot_timer->adjust(m_maincpu->cycles_to_attotime(10));

	return 0;
}

u32 risc2500_state::rom_r(offs_t offset)
{
	if (!machine().side_effects_disabled())
	{
		// handle dynamic cpu clock divider when accessing rom
		s64 diff = m_maincpu->total_cycles() - m_prev_cycle;
		u32 pc = m_maincpu->pc();

		if (diff > 0)
		{
			static constexpr int arm_branch_cycles = 3;
			static constexpr int arm_max_cycles = 17; // datablock transfer
			static constexpr int divider = -8 + 1;

			// this takes care of almost all cases, otherwise, total cycles taken can't be determined
			if (diff <= arm_branch_cycles || (diff <= arm_max_cycles && (pc - m_prev_pc) == 4 && (pc & ~0x02000000) == (offset * 4)))
				m_maincpu->adjust_icount(divider * (int)diff);
			else
				m_maincpu->adjust_icount(divider);
		}

		m_prev_cycle = m_maincpu->total_cycles();
		m_prev_pc = pc;
	}

	return m_rom[offset];
}



/*******************************************************************************
    Address Maps
*******************************************************************************/

void risc2500_state::risc2500_mem(address_map &map)
{
	map(0x00000000, 0x001fffff).view(m_boot_view);
	m_boot_view[0](0x00000000, 0x0003ffff).r(FUNC(risc2500_state::rom_r));

	map(0x01000000, 0x01000003).rw(FUNC(risc2500_state::input_r), FUNC(risc2500_state::control_w));
	map(0x01800000, 0x01800003).r(FUNC(risc2500_state::disable_bootrom_r));
	map(0x02000000, 0x0203ffff).r(FUNC(risc2500_state::rom_r));
}



/*******************************************************************************
    Input Ports
*******************************************************************************/

static INPUT_PORTS_START( risc2500 )
	PORT_START("IN.0")
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("Pawn")     PORT_CODE(KEYCODE_1) PORT_CODE(KEYCODE_1_PAD)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("Back")     PORT_CODE(KEYCODE_B) PORT_CODE(KEYCODE_BACKSPACE)

	PORT_START("IN.1")
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("Knight")   PORT_CODE(KEYCODE_2) PORT_CODE(KEYCODE_2_PAD)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("Enter")    PORT_CODE(KEYCODE_ENTER) PORT_CODE(KEYCODE_ENTER_PAD)

	PORT_START("IN.2")
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("Bishop")   PORT_CODE(KEYCODE_3) PORT_CODE(KEYCODE_3_PAD)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("Down")     PORT_CODE(KEYCODE_DOWN)

	PORT_START("IN.3")
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("Rook")     PORT_CODE(KEYCODE_4) PORT_CODE(KEYCODE_4_PAD)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("Up")       PORT_CODE(KEYCODE_UP)

	PORT_START("IN.4")
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("Queen")    PORT_CODE(KEYCODE_5) PORT_CODE(KEYCODE_5_PAD)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("Menu")     PORT_CODE(KEYCODE_M)

	PORT_START("IN.5")
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("King")     PORT_CODE(KEYCODE_6) PORT_CODE(KEYCODE_6_PAD)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("Play")     PORT_CODE(KEYCODE_P)

	PORT_START("IN.6")
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("Right")    PORT_CODE(KEYCODE_RIGHT)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("New Game") PORT_CODE(KEYCODE_N)

	PORT_START("IN.7")
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("Left")     PORT_CODE(KEYCODE_LEFT)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("Off")      PORT_CODE(KEYCODE_F)

	PORT_START("RESET")
	PORT_BIT(0x01, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("On")       PORT_CODE(KEYCODE_O) PORT_CHANGED_MEMBER(DEVICE_SELF, FUNC(risc2500_state::on_button), 0)
INPUT_PORTS_END

static INPUT_PORTS_START( montreux ) // on/off buttons have different labels
	PORT_INCLUDE( risc2500 )

	PORT_MODIFY("IN.7")
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("Stop")     PORT_CODE(KEYCODE_S)

	PORT_MODIFY("RESET")
	PORT_BIT(0x01, IP_ACTIVE_HIGH, IPT_KEYPAD) PORT_NAME("Go")       PORT_CODE(KEYCODE_G) PORT_CHANGED_MEMBER(DEVICE_SELF, FUNC(risc2500_state::on_button), 0)
INPUT_PORTS_END



/*******************************************************************************
    Machine Configs
*******************************************************************************/

void risc2500_state::risc2500(machine_config &config)
{
	// basic machine hardware
	ARM(config, m_maincpu, 28.322_MHz_XTAL / 2);
	m_maincpu->set_addrmap(AS_PROGRAM, &risc2500_state::risc2500_mem);
	m_maincpu->set_copro_type(arm_cpu_device::copro_type::VL86C020);

	const attotime irq_period = attotime::from_hz(32.768_kHz_XTAL / 128); // 256Hz
	m_maincpu->set_periodic_int(FUNC(risc2500_state::irq1_line_assert), irq_period);

	RAM(config, m_ram).set_extra_options("128K, 256K, 512K, 1M, 2M");
	m_ram->set_default_size("128K");
	m_ram->set_default_value(0);

	NVRAM(config, "nvram", nvram_device::DEFAULT_NONE);

	SENSORBOARD(config, m_board);
	m_board->set_type(sensorboard_device::BUTTONS);
	m_board->init_cb().set(m_board, FUNC(sensorboard_device::preset_chess));
	m_board->set_delay(attotime::from_msec(100));
	m_board->set_nvram_enable(true);

	// video hardware
	SED1520(config, m_lcdc);
	m_lcdc->set_screen_update_cb(FUNC(risc2500_state::sed1520_update));

	SCREEN(config, m_screen, SCREEN_TYPE_SVG);
	m_screen->set_refresh_hz(60);
	m_screen->set_size(1920/5, 768/5);
	m_screen->set_visarea_full();
	m_screen->set_screen_update(FUNC(risc2500_state::screen_update));

	PWM_DISPLAY(config, m_led_pwm).set_size(2, 8);
	config.set_default_layout(layout_saitek_risc2500);

	// sound hardware
	SPEAKER(config, "speaker").front_center();
	DAC_2BIT_ONES_COMPLEMENT(config, m_dac).add_route(ALL_OUTPUTS, "speaker", 0.125);
}

void risc2500_state::montreux(machine_config &config)
{
	risc2500(config);
	config.set_default_layout(layout_mephisto_montreux);
}



/*******************************************************************************
    ROM Definitions
*******************************************************************************/

ROM_START( risc2500 ) // v1.04 21-Oct-92
	ROM_REGION( 0x40000, "maincpu", ROMREGION_ERASE00 )
	ROM_LOAD("st17_a22_u_7.u7", 0x000000, 0x020000, CRC(84a06178) SHA1(66f4d9f53de6da865a3ebb4af1d6a3e245c59a3c) ) // 27C010A-12

	ROM_REGION( 221222, "screen", 0 )
	ROM_LOAD("risc2500.svg", 0, 221222, CRC(73076886) SHA1(d278f071f8a92201a5aba59ad1c99234a389118f) )
ROM_END

ROM_START( risc2500a ) // v1.03 14-Oct-92
	ROM_REGION( 0x40000, "maincpu", ROMREGION_ERASE00 )
	ROM_LOAD("st17_a15.u7", 0x000000, 0x020000, CRC(7a707e82) SHA1(87187fa58117a442f3abd30092cfcc2a4d7c7efc) ) // 27C010A-15

	ROM_REGION( 221222, "screen", 0 )
	ROM_LOAD("risc2500.svg", 0, 221222, CRC(73076886) SHA1(d278f071f8a92201a5aba59ad1c99234a389118f) )
ROM_END

ROM_START( montreux ) // v1.00 10-Dec-94
	ROM_REGION( 0x40000, "maincpu", 0 )
	ROM_LOAD("rt17b_103_u_7.u7", 0x000000, 0x040000, CRC(db374cf3) SHA1(44dd60d56779084326c3dfb41d2137ebf0b4e0ac) ) // 27C020-15

	ROM_REGION( 221222, "screen", 0 )
	ROM_LOAD("risc2500.svg", 0, 221222, CRC(73076886) SHA1(d278f071f8a92201a5aba59ad1c99234a389118f) )
ROM_END

} // anonymous namespace



/*******************************************************************************
    Drivers
*******************************************************************************/

//    YEAR  NAME       PARENT    COMPAT  MACHINE   INPUT     CLASS           INIT        COMPANY, FULLNAME, FLAGS
SYST( 1992, risc2500,  0,        0,      risc2500, risc2500, risc2500_state, empty_init, "Saitek / Tasc", "Kasparov RISC 2500 (v1.04)", MACHINE_SUPPORTS_SAVE | MACHINE_IMPERFECT_TIMING )
SYST( 1992, risc2500a, risc2500, 0,      risc2500, risc2500, risc2500_state, empty_init, "Saitek / Tasc", "Kasparov RISC 2500 (v1.03)", MACHINE_SUPPORTS_SAVE | MACHINE_IMPERFECT_TIMING )

SYST( 1995, montreux,  0,        0,      montreux, montreux, risc2500_state, empty_init, "Saitek / Tasc", "Mephisto Montreux", MACHINE_SUPPORTS_SAVE | MACHINE_IMPERFECT_TIMING ) // after Saitek bought Hegener + Glaser
