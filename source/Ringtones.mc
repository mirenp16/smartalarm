// Ringtones.mc
// GENERATED from the user's .wav files.
//
// Connect IQ watch apps cannot play audio files, and the FR265S makes alarm
// sound with a piezo buzzer (its music feature only outputs to Bluetooth
// headphones). So each ringtone was re-created as a tone sequence: the pitch
// and rhythm were extracted from the original recording and rebuilt as
// (frequency Hz, duration ms) pairs played through Attention.ToneProfile.
// Each sequence fits inside the 3 s repeat interval so it loops seamlessly
// until you snooze or wake.

import Toybox.Lang;

const RINGTONE_NAMES = [
    "Alert",
    "Classic",
    "Digital",
    "Rooster",
    "Slot Machine",
    "Spaceship",
    "Vintage",
    "Wave"
];

// [ [freq, ms], ... ] per ringtone, indexed to match RINGTONE_NAMES.
// A frequency of 0 is a rest.
const RINGTONE_DATA = [
    // Alert: 18 notes, 1080 ms
    [[925,60], [1150,60], [1375,60], [1700,60], [1050,60], [1150,60], [1275,60], [1450,60], [1600,60], [1725,60], [925,60], [1150,60], [1375,60], [1700,60], [1050,60], [1150,60], [1275,60], [1450,60]],
    // Classic: 18 notes, 1860 ms
    [[2225,60], [1700,60], [1450,60], [1950,100], [0,250], [1950,100], [2225,60], [1950,60], [2225,60], [0,250], [1950,60], [925,100], [1700,60], [1450,60], [0,250], [2225,60], [1950,150], [2225,60]],
    // Digital: 3 notes, 1450 ms
    [[3925,450], [0,550], [3950,450]],
    // Rooster: 18 notes, 2180 ms
    [[1550,150], [0,100], [725,60], [850,60], [775,60], [0,100], [1150,60], [675,350], [1350,150], [650,100], [1325,60], [650,60], [750,300], [1450,60], [725,150], [1450,150], [725,150], [675,60]],
    // Slot Machine: 18 notes, 1240 ms
    [[925,60], [825,60], [1050,60], [1225,60], [925,60], [825,60], [1050,100], [925,60], [825,60], [1050,100], [925,60], [825,100], [1050,60], [925,60], [825,100], [1050,60], [925,60], [1100,60]],
    // Spaceship: 12 notes, 2270 ms
    [[250,150], [150,100], [200,200], [250,60], [0,500], [250,150], [150,100], [200,200], [250,60], [0,500], [250,150], [150,100]],
    // Vintage: 3 notes, 1500 ms
    [[1325,500], [0,500], [1325,500]],
    // Wave: 8 notes, 720 ms
    [[2150,60], [2250,60], [325,100], [450,100], [550,100], [325,100], [450,100], [2550,100]]
];

