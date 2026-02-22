# Signoff SDC for Layr Chip
#
# Compared to the implementation SDC, this relaxes max capacitance and
# max transition constraints to the actual library limits. These are
# intentionally over-constrained during PNR to yield better results.

# ---- Clock Definition ----
create_clock [get_pins clk_pad/p2c] -name clk -period $::env(CLOCK_PERIOD)

# ---- I/O Delays ----
set input_delay_value  [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]
set output_delay_value [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]
puts "\[INFO\] Setting input delay to: $input_delay_value"
puts "\[INFO\] Setting output delay to: $output_delay_value"

set clocks [get_clocks clk]

# Get all inputs except the clock pad pin
set all_inputs_wo_clk [lsearch -inline -all -not -exact [all_inputs] [get_ports clk_PAD]]

set_input_delay  $input_delay_value  -clock $clocks $all_inputs_wo_clk
set_output_delay $output_delay_value -clock $clocks [all_outputs]

# ---- Design Constraints (relaxed for signoff) ----
set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]

# No set_max_transition -- use library defaults (2.5 ns stdcell, 1.2 ns IO)
# No set_max_capacitance -- use library defaults (0.3 pF)

# ---- Driving Cell and Load ----
if { ![info exists ::env(SYNTH_CLK_DRIVING_CELL)] } {
    set ::env(SYNTH_CLK_DRIVING_CELL) $::env(SYNTH_DRIVING_CELL)
}

set_driving_cell \
    -lib_cell [lindex [split $::env(SYNTH_DRIVING_CELL) "/"] 0] \
    -pin [lindex [split $::env(SYNTH_DRIVING_CELL) "/"] 1] \
    $all_inputs_wo_clk

set cap_load [expr $::env(OUTPUT_CAP_LOAD) / 1000.0]
puts "\[INFO\] Setting load to: $cap_load"
set_load $cap_load [all_outputs]

# ---- Clock Constraints ----
puts "\[INFO\] Setting clock uncertainty to: $::env(CLOCK_UNCERTAINTY_CONSTRAINT)"
set_clock_uncertainty $::env(CLOCK_UNCERTAINTY_CONSTRAINT) $clocks

# ---- On-Chip Variation (OCV) ----
puts "\[INFO\] Setting timing derate to: $::env(TIME_DERATING_CONSTRAINT)%"
set_timing_derate -early [expr 1 - [expr $::env(TIME_DERATING_CONSTRAINT) / 100]]
set_timing_derate -late  [expr 1 + [expr $::env(TIME_DERATING_CONSTRAINT) / 100]]

# ---- Use Propagated (Real) Clocks ----
set_propagated_clock [all_clocks]
