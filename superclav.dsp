declare options "[midi:on][nvoices:16]";
import("stdfaust.lib");
import("akjrev_48000.dsp");

gate = button("v:midi/[0]gate[hidden:1]");
gain = hslider("v:midi/[1]gain[hidden:1]",0.1,0,1,0.01);
mkey = hslider("v:midi/[2]key",60,36,96,1);

freq = midikey2hz(mkey-36)
with {
    ///////////////////////////////////////////////////////////////////
    // johnson-secor_rwt.scl (Johnson/Secor Rational Well-Temperment //
    // with five 24/19 major thirds)                                 //
    // It's laid out here in a 4-octave keyboard setup, perfect for
    // a little 49-key controller to simulate a 'clav' sound with an //
    // authentic range/gamut. As a result, MIDI key #36 should map   //
    // to index 0 in the tables below. This is why we subtract 36 in //
    // the variable declarations.                                    //
    ///////////////////////////////////////////////////////////////////
    myhzvals = waveform{
        65.25,
        68.97401273911355,
        73.07542096695869,
        77.50818851695334,
        81.93181275331729,
        86.99999999999999,
        92.06926110620043,
        97.65419825172961,
        103.3442514075962,
        109.36584898752463,
        116.13106737084314,
        122.89771906854337,
        130.5,
        137.94802547822707,
        146.15084193391743,
        155.01637703390668,
        163.86362550663458,
        174.00000000000003,
        184.13852221240086,
        195.30839650345916,
        206.68850281519246,
        218.73169797504926,
        232.26213474168622,
        245.79543813708682,
        261.0,
        275.89605095645413,
        292.30168386783487,
        310.03275406781336,
        327.72725101326915,
        348.00000000000006,
        368.2770444248017,
        390.61679300691833,
        413.37700563038493,
        437.4633959500985,
        464.52426948337245,
        491.59087627417364,
        522.0,
        551.7921019129083,
        584.6033677356697,
        620.0655081356267,
        655.4545020265383,
        696.0000000000001,
        736.5540888496034,
        781.2335860138367,
        826.7540112607699,
        874.926791900197,
        929.0485389667449,
        983.1817525483473,
        1044.0
    };
    midikey2hz(mk) = myhzvals,int(mk) : rdtable;
};

//////////////////////
// excitation noise //
//////////////////////
saw_mix          = hslider("saw_mix[midi:ctrl 21]",0.177165,0,0.25,0.00197);
attack_bright_C1 = hslider("attack_bright_C1[midi:ctrl 22]",11.866141,1,16,0.11811);
attack_bright_C5 = hslider("attack_bright_C5[midi:ctrl 23]",5.370079,1,16,0.11811);
attack_bright    = attack_bright_C1+((mkey-36)*((attack_bright_C5-attack_bright_C1)/48));
/////////////////////////////////
// string feedback (resonance) //
/////////////////////////////////
// Uncomment the first of the following to get a dial for experimentation
// (and obviously only have one of the two lines
// The keyboard mapped expression was emperically derived based
// on what sounded good between the highest and lowest ranges.
feedback_C1 = hslider("feedback_C1[midi:ctrl 24]",15.763780,1,16,0.11811);
feedback_C5 = hslider("feedback_C5[midi:ctrl 25]",16.000000,1,16,0.11811);
feedback    = feedback_C1+((mkey-36)*((feedback_C5-feedback_C1)/48));
////////////////
// decay time //
////////////////
decay_time_C1 = hslider("decay_time_C1[midi:ctrl 26]",29.275591,1,64,0.49606); 
decay_time_C5 = hslider("decay_time_C5[midi:ctrl 27]",19.354330,1,64,0.49606);
decay_time    = decay_time_C1+((mkey-36)*((decay_time_C5-decay_time_C1)/48));
/////////////////
// body cutoff //
/////////////////
body_cutoff = hslider("body_cutoff_C1[midi:ctrl 28]",3543.181152,256,5000,37.35433);
/////////////////////
// gain correction //
/////////////////////
gain_scale  = hslider("gain_scale[midi:ctrl 48]",0.389764,0,1.5,0.01181);

///////////////////////////////////////
// The feedback comb filter 'string' //
///////////////////////////////////////
fb_fcomba(maxdel,N,b0,aN) = (+ <: de.fdelay1a(maxdel,float(N)-1.0),_) ~ *(-aN) : !,*(b0) : mem;

combString(freq,feedback,gate) = excitation
    : fi.highpass(2,30) : fi.lowpass(1,energy) : fb_fcomba(maxDel,N,b0,aN)
with {
    maxDel     = 1024;
    N          = ma.SR/freq;
    b0         = 1;
    aN         = ba.tau2pole(feedback*0.001)*-1;
    noise_vol  = 1-saw_mix;
    exc_numer  = 0.5+(mkey-36)*0.0104166;
    exc_attack = exc_numer/freq;
    energy     = freq*gain*attack_bright;
    excite_env = en.ar(exc_attack,exc_attack*2,gate);
    excitation = ((no.noise*noise_vol + os.sawtooth(freq)*saw_mix)
                  * excite_env
                  * gain) : fi.dcblocker;
};

///////////////////////////////////////////////
// The instrument, the 'string' source going //
// through lowpass.                          //
///////////////////////////////////////////////
superclav = (
    combString(freq,feedback,gate)*amp_env*gain_scale*0.5
    : fi.lowpass(2,cutoff) : fi.dcblocker <: _,de.sdelay(2048,2048,delay_smps)
)
with {
    exc_attack    = 1/freq;
    amp_env       = en.asre(exc_attack,gain,exc_attack*2,gate);
    cutoff_env    = en.adsre(exc_attack,decay_time,0.1,exc_attack*2,gate);  // pow(0.001,0.25)
    fast_cf_env   = en.ar(exc_attack,exc_attack,gate);
    cutoff        = ((pow(cutoff_env,4)*body_cutoff)
                     +(1.3*fast_cf_env*body_cutoff)
                     +freq);
    // stereo imaging
    frq_smps      = ma.SR/freq;
    frq_smp_quad  = frq_smps/4;
    hass_delay    = hslider("hass_delay[midi:ctrl 41]",0.03,0.01,0.04,0.0023622);
    hass_delsmps  = ma.SR*hass_delay;
    del_units     = floor(hass_delsmps/frq_smps);
    delay_smps    = (frq_smps*del_units)+frq_smp_quad;
};

process = superclav : *(0.5),*(0.5);
effect = akjrev_demo;
