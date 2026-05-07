import Foundation

// Read-only reference cards for the LP-100A SETUP screens. Source: LP-100A
// Quick Start Guide v4.1. Ported verbatim from the SETUP_SCREENS const in
// the server's reference web client (internal/web/static/index.html).
enum SetupScreens {
    struct Entry {
        let name: String
        let lcd: [String]
        let desc: String
    }

    static let all: [Entry] = [
        Entry(name: "Reference Screen",
              lcd: ["Re 1.82  AGC .684 78F", "AL:Reset  FS:TempF/C"],
              desc: "Reference voltage from the gain/phase detector, RSSI from the frequency-counter preamp, and temperature. Dn resets the microprocessor. Up toggles °F / °C."),
        Entry(name: "User Alarm Setting",
              lcd: ["User Alarm Setting", "       3.5"],
              desc: "User-defined SWR alarm setpoint. Range 1.0–5.0 in 0.1 steps. Used when Alarm cycles to the \"User\" position."),
        Entry(name: "AL Thresh / Pwr Mode",
              lcd: ["AL Thresh   Pwr Mode", "000.0W      Net"],
              desc: "SWR-alarm power threshold (0, 0.1, 1.0, 10.0, 100.0 W) and the power display mode: Net (Fwd − Ref) or Fwd. Default: Net, threshold 0 W (alarm active at all powers)."),
        Entry(name: "Range / Scale Max",
              lcd: ["CH1 Range  Scale Max", "High         1500W"],
              desc: "Maximum bargraph scale per range. Set Low / Mid / High independently. Defaults: 15 / 100 / 1500 W. Scaled ×1.67 with a 5 kW coupler, ×3.33 with 10 kW."),
        Entry(name: "Bargraph Tuning Range",
              lcd: ["Bargraph Tuning Range", "        12 dB"],
              desc: "Width of the bargraph in Average and Tune modes (dB below max). Used to optimize bargraph resolution while tuning. Peak mode is fixed at 13 dB."),
        Entry(name: "Avg. Samples PWR / SWR",
              lcd: ["Avg. Samples PWR  SWR", "           8    2"],
              desc: "Sample count for the numeric power and SWR readouts. Power: 2–24 samples; SWR: 0–5. Defaults: 8 and 2. Higher = smoother but slower."),
        Entry(name: "Peak Hold Time",
              lcd: ["Peak Hold Time", "      2.00 sec"],
              desc: "Hold time for peak-mode readings before they decay. Range 0.25–5.0 s. Default 2.0 s — good for SSB or CW."),
        Entry(name: "Bargraph Decay",
              lcd: ["Bargraph Decay", "        Med"],
              desc: "Decay rate of the bargraphs. Choices: Fast / Med / Slow (≈3 s). Slow smooths the response considerably for SSB. Default Med. Attack is always fast."),
        Entry(name: "Coupler Type",
              lcd: ["CH1   Coupler Type", "LPC1 3KW 1.8-54 MHz"],
              desc: "Selects max power and frequency range of the installed coupler. Choices: LPC1 / LPC2 / LPC3 / LPC4 / LPC5 / LPC6. Different couplers can be intermixed across CH1/CH2."),
        Entry(name: "SWR Resting Style",
              lcd: ["SWR Resting Style", "      < -.-- >"],
              desc: "How SWR is displayed when not transmitting. Choices: \"-.--\", \"1.00\", \". . . .\", blank, hold-last. Hold-last resets when you transmit again."),
        Entry(name: "Lower Bargraph Mode",
              lcd: ["Lower Bargraph Mode", "    >SWR    REF"],
              desc: "What the lower bargraph shows: SWR or Reflected Power. With Reflected Power, the reference depends on the AL Thresh power-mode setting (Net or Fwd)."),
        Entry(name: "Letter Pos'n / Callsign",
              lcd: ["Ltr Pos'n   Callsign", "    1         N8LP"],
              desc: "Per-character editor for the screen-saver callsign (6 chars). Dn picks the position 1–6; Up scrolls 0–9, A–Z, space, /, −. Wraps both directions."),
        Entry(name: "Display Brightness",
              lcd: ["Display Brightness", "Dim ----+--- Bright"],
              desc: "8 levels in 12.5 % steps. Default: 6 (≈75 %). Display is rated 50 000 hrs at full brightness; lower = longer life. Adjusts live as you scroll."),
        Entry(name: "SS Timers — Minutes",
              lcd: ["SS Timers - Minutes", "Scroll=02   Sleep= 05"],
              desc: "Screen-saver scroll start and sleep timers, in minutes. 0–10 each. The scroll timer must fire before the sleep timer. There's also a fixed 1-second post-TX dim."),
        Entry(name: "SS Reset Mode",
              lcd: ["SS Reset Mode", "Mode Button or RF Sense"],
              desc: "How the meter wakes from screen-saver / sleep. Choices: Mode Button or RF Sense / Mode Button only. Useful in 24/7 monitoring stations to reduce display wear."),
        Entry(name: "Opt. Mode Display",
              lcd: ["Opt. Mode Display", "dBm / RL         On"],
              desc: "Enable / disable the optional display modes: dBm/RL, Direct Input (FS), Peak-to-Average. All disabled by default. The web client should mirror these in [ui] enabled_views."),
        Entry(name: "SWR Power Threshold",
              lcd: ["SWR Power Threshold", "       0.50W"],
              desc: "Lower limit for SWR display. Choices: 0.05 / 0.5 / 2.0 / 5.0 / 10.0 W. Higher values ignore noisy low-power samples (e.g. between syllables) and smooth the SWR display."),
        Entry(name: "Pk. Tmr Reset Threshold",
              lcd: ["Pk. Tmr Reset Threshold", "  50 Percent of Peak"],
              desc: "How far below the peak power must drop before the peak-hold timer resets and grabs a new sample. Default 10 %. Useful for SSB peak tracking."),
        Entry(name: "Dual Coupler Option",
              lcd: ["Dual Coupler Option", "    Not Installed"],
              desc: "Enable / disable the dual-coupler feature. \"Installed\" reveals the up/down arrows that show which coupler is active. Most users keep this Off."),
    ]
}
