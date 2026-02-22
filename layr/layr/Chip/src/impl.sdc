# Implementation SDC for Layr Chip (PNR constraints)
#
# This SDC intentionally over-constrains max_transition and max_capacitance
# so the PnR tools optimize more aggressively. The signoff SDC relaxes these.

# ---- Clock Definition ----
# Define clock on the internal net after the IO pad buffer, not on the
# external pad pin. This avoids STA-0441 warnings and correctly models
# the clock path.
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

# ---- Design Constraints (over-constrained for PNR) ----
set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]

# Over-constrain transition: library default is 2.5 ns, we use 1.0 ns
# to force the tools to insert buffers and keep edges sharp.
set_max_transition 1.0 [current_design]

# Over-constrain capacitance: library default is 0.3 pF, we use 0.15 pF
# to force the tools to buffer high-fanout nets.
set_max_capacitance 0.15 [current_design]

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

puts "\[INFO\] Setting clock transition to: $::env(CLOCK_TRANSITION_CONSTRAINT)"
set_clock_transition $::env(CLOCK_TRANSITION_CONSTRAINT) $clocks

# ---- On-Chip Variation (OCV) ----
puts "\[INFO\] Setting timing derate to: $::env(TIME_DERATING_CONSTRAINT)%"
set_timing_derate -early [expr 1 - [expr $::env(TIME_DERATING_CONSTRAINT) / 100]]
set_timing_derate -late  [expr 1 + [expr $::env(TIME_DERATING_CONSTRAINT) / 100]]

# ---- Use Propagated (Real) Clocks ----
set_propagated_clock [all_clocks]
