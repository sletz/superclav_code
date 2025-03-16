declare options "[midi:on][nvoices:16]";
import("stdfaust.lib");
import("akjrev_48000.dsp");

gate = button("v:midi/[0]gate[hidden:1]");
gain = hslider("v:midi/[1]gain[hidden:1]",0.1,0,1,0.01);
mkey = hslider("v:midi/[2]key",60,36,96,1);

freq = midikey2hz(mkey-36)
with {
    ///////////////////////////////////////////////////////////////////////////
    // johnson-secor_rwt.scl (Johnson/Secor Rational Well-Temperment with    //
    // five 24/19 major thirds)                                              //
    //                                                                       //
    // It's laid out here in a 4-octave keyboard setup, perfect for a little //
    // 49-key controller to simulate a 'clav' sound with an authentic        //
    // range/gamut. As a result, MIDI key #36 should map to index 0 in the   //
    // tables below. This is why we subtract 36 in the 'mkey' declarations.  //
    ///////////////////////////////////////////////////////////////////////////
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

///////////////////////////////////////////////////////////////////////////////
// Basic params!                                                             //
//                                                                           //
// You will notice that the older version had nine dials, and this has now   //
// been reduced to just a master volume, basically, b/c I wanted to find     //
// ideal settings, and then "set it and forget it". A factor contributing to //
// parameter reduction was that I went back to a more basic design with the  //
// following ideas in mind:                                                  //
//                                                                           //
//    * No additional vco wave, just pink noise in the excitation            //
//    * Bringing a filter back into the main resonator feedback. This gives  //
//      a more "naturalistic" decay character, as it corresponds to hi-freq  //
//      energy loss in a string model, and allows me not to have need for a  //
//      secondary post-string-model filter to gain back naturalism.          //
//    * As mentioned, after empirical experimentation, lock in values, in so //
//      doing, reducing the need for a dial to tweak to get a good sound.    //
//                                                                           //
// I wanted the lowest note to ring for ~10 seconds, and the hightest for    //
// just about ~3-4 seconds. This suited the music and wasn't really based on //
// looking to precisely emulated a real clavichord. In addition, I wanted to //
// have the ring of the note be a certain brightness that sounded good while //
// also staying within those time contraints. And brightness and decay being //
// related, this meant bringing a "sustain" parameter to assist the decay    //
// to be slightly faster, because the slightly brighter sound I wanted would //
// naturally ring a bit longer otherwise...                                  //
///////////////////////////////////////////////////////////////////////////////
bright_C1  = 97;     // not magic, emprically getting appropriate brightness and decay
bright_C5  = 67;     // same thing
sustain    = 0.9984; // adjustment that allows note to stay bright but decay a bit faster
master_vol = hslider("master_vol[midi:ctrl 48]",0.5,0,1,0.007874);

/////////////////////////////////////////
// The Superclav instrument definition //
/////////////////////////////////////////
superclav = excitation : fi.highpass(2,35) : resonator(delsmps)*env*master_vol
            <: _,de.sdelay(2048,2048,delay_smps)
with {
    //////////////////////////////////////////////////////////
    // Convert desired voice frequency to number of samples //
    //                                                      //
    // Think of this as frequency -> string (delay) length  //
    //////////////////////////////////////////////////////////
    delsmps        = ma.SR/freq;
    /////////////////////////////////////////////////////////////
    // Envelope params, used by excition and wrapping envelope //
    /////////////////////////////////////////////////////////////
    attack_numer   = 0.0125+(mkey-36)*(0.0125/48); // kbd tracking
    attack         = attack_numer/freq;
    decay          = attack;
    exc_rel        = attack;
    release        = attack*6;
    ///////////////////////////
    // Pink-noise excitation //
    ///////////////////////////
    exc_factor     = 1/(2.0+(mkey-36)*(-1/48)); // kbd tracking
    exc_window     = ba.spulse(int(delsmps)*exc_factor,gate);
    exc_env        = en.are(attack,exc_rel,gate);
    inv_gain       = 1-(gain*0.5+0.3);                // make noise respond to velocity/gain
    exc_filt       = *(1-inv_gain) : + ~ *(inv_gain); // filter for velocity response
    excitation     = no.pink_noise*gain*exc_env*exc_window : exc_filt;
    /////////////////////////////////////
    // Resonator filter and its params //
    /////////////////////////////////////
    brightness     = bright_C1+(bright_C5-bright_C1)*((mkey-36)*(1/48));
    tau            = 1/((freq*2*ma.PI)+(freq*brightness*gain*2*ma.PI));
    pole_val       = ba.tau2pole(tau);
    flt            = *(1-pole_val) : + ~ *(pole_val); // standard 1-pole lowpass equation
    ///////////////////////////////////////
    // The actual string model resonator //
    ///////////////////////////////////////
    resonator(ds)  = (+ : de.fdelay2(4096, ds-1)) ~ (flt*sustain) : fi.dcblocker;
    ////////////////////////////////////////////////////////////
    // Wrap it all in an anti-click and MIDI-playing envelope //
    ////////////////////////////////////////////////////////////
    env            = en.adsre(attack,0,1,release,gate);
    //////////////////////////////////////////
    // Stereo imaging using the Haas Effect //
    //////////////////////////////////////////
    frq_smps       = ma.SR/freq;
    frq_smp_quad   = frq_smps/4;
    hass_delay     = hslider("hass_delay[midi:ctrl 41]",0.03,0.01,0.04,0.0023622);
    hass_delsmps   = ma.SR*hass_delay;
    del_units      = floor(hass_delsmps/frq_smps);
    delay_smps     = (frq_smps*del_units)+frq_smp_quad;
};

process = superclav;
effect  = akjrev_demo;
