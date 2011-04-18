#############################################################################
#
# Airbus Flight Management.
#
# Abstract:
#    This is a utility helper class for the moment, later to be expanded to do more.
# 
# 
# Author: S.Hamilton Jan 2010
#
#
#   Copyright (C) 2010 Scott Hamilton
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

fms_trace = 1;


## mode constants
LNAV_OFF=0;
LNAV_HDG=1;
LNAV_TRACK=2;
LNAV_LOC=3;
LNAV_FMS=4;
LNAV_RWY=5;

VNAV_OFF=0;
VNAV_ALTs=1;
VNAV_VS=2;
VNAV_OPCLB=3;
VNAV_FPA=4;
VNAV_OPDES=5;
VNAV_CLB=6;
VNAV_ALTCRZ=7;
VNAV_DES=8;
VNAV_GS=9;
VNAV_SRS=10;
VNAV_LEVEL=11;

SPD_OFF=0;
SPD_TOGA=1;
SPD_FLEX=2;
SPD_THRCLB=3;
SPD_SPEED=4;
SPD_MACH=5;
SPD_CRZ=6;
SPD_THRDES=7;
SPD_THRIDL=8;

lnavStr = ["off","HDG","TRK","LOC","NAV","RWY"];
vnavStr = ["off","ALT(s)","V/S","OP CLB","FPA","OP DES","CLB","ALT CRZ","DES","G/S","SRS","LEVEL"];
spdStr  = ["off","TOGA","FLEX","THR CLB","SPEED","MACH","CRZ","THR DES","THR IDL"];

MANAGED_MODE = -1;
SELECTED_MODE = 0;






var AirbusFMS = {
   
   new : func() {
     var m = {parents : [AirbusFMS]};
     m.FMSnode = props.globals.getNode("/instrumentation/fms",1);
     m.activeFpln = m.FMSnode.getNode("plan[0]",1);
     m.secFpln = m.FMSnode.getNode("plan[1]",1);
     m.activePlan = [];
     m.lastWP = 0;
     m.secondPlan = [];
     m.depDB = nil;
     m.arvDB = nil;
     setprop("instrumentation/fms/plan[0]/display-nodes/current-page",0);
     setprop("instrumentation/fms/plan[0]/display-nodes/current-wp",0);
     m.version = "V1.0.6";

     setlistener("/sim/signals/fdm-initialized", func m.init());
     setlistener("/autopilot/route-manager/current-wp", func m.updateCurrentWP());
     return m;
   },

#############################################################################
#  output a debug message to stdout or file.
#############################################################################
tracer : func(msg) {
  var timeStr = getprop("/sim/time/gmt-string");
  var curAltStr = getprop("/position/altitude-ft");
  var curVnav    = getprop("/instrumentation/flightdirector/vnav");
  var curLnav    = getprop("/instrumentation/flightdirector/lnav");
  var curSpd     = getprop("/instrumentation/flightdirector/spd");
  var athrStr   = getprop("/instrumentation/flightdirector/at-on");
  var ap1Str     = getprop("/instrumentation/flightdirector/ap");
  var altHold = getprop("/autopilot/settings/target-altitude-ft");
  var vsHold  = getprop("/autopilot/settings/vertical-speed-fpm");
  var spdHold = getprop("/autopilot/settings/target-speed-kt");
  if (curVnav == nil) curVnav = "0";
  if (curLnav == nil) curLnav = "0";
  if (curSpd  == nil) curSpd  = "0";
  if (fms_trace > 0) {
    print("[AFMS] time: "~timeStr~" alt: "~curAltStr~", - "~msg);
    if (fms_trace > 1) {
      print("[AFMS] vnav: "~me.afs.vertical_text[curVnav]~", lnav: "~me.afs.lateral_text[curLnav]~", spd: "~me.afs.spd_text[curSpd]);
    }
  }
},

   ####
   # init
   ####
   init : func() {
      print("AFMS "~me.version~" ready");
      for(var w=0; w < 9; w=w+1) {
        var wp = me.activeFpln.getNode("display-nodes/wp["~w~"]",1);
        wp.getNode("id",1).setValue("");
        wp.getNode("parent",1).setValue("");
        wp.getNode("spd-lim-display",1).setValue("0.00");
        wp.getNode("alt-lim-display",1).setValue("FL000");
        wp.getNode("time-utc-display",1).setValue("00:00");
        wp.getNode("active", 1).setBoolValue(0);
        wp.getNode("track",1).setDoubleValue(0.0);
        wp.getNode("dist",1).setIntValue(0);
      }
      ##settimer(func me.update(), 0);
      ##settimer(func me.slow_update(), 0);
    },

   ### for high prio tasks ###
   update : func() {
     settimer(func me.update(), 1);
   }, 

   ### for low prio tasks ###
   slow_update : func() {
     me.tracer("FMS update");
     settimer(func me.slow_update(), 3);
   },

   ####
   # evaluate managed VNAV
   ####
   evaluateManagedVNAV : func() {
     var retVNAV = VNAV_OFF;
     me.tracer("evaluateManagedVNAV");
     ##var curAlt = getprop("/instrumentation/altimeter/indicated-altitude-ft");
     var curAlt = getprop("/position/altitude-ft");
     var curFlightMode = getprop("/instrumentation/ecam/flight-mode");
     var redAlt = getprop("/instrumentation/afs/thrust-reduce-alt");
     var accAlt = getprop("/instrumentation/afs/thrust-accel-alt");
     var crzAlt = getprop("/instrumentation/afs/thrust-cruise-alt");
     var crzAcquire = getprop("/instrumentation/afs/acquire_crz");
     var accelArm = getprop("/instrumentation/flightdirector/accel-arm");
     var clbArm   = getprop("/instrumentation/flightdirector/climb-arm");
     var flapPos = me.getFlapConfig();
     var vnavMode = getprop("/instrumentation/flightdirector/vnav");
     var lnavMode = getprop("/instrumentation/flightdirector/lnav");
     var spdMode = getprop("/instrumentation/flightdirector/spd");
     var vsi = getprop("/instrumentation/vertical-speed-indicator/indicated-speed-fpm");
     var altSelect = getprop("/instrumentation/afs/vertical-alt-mode");
     var vsSelect = getprop("/instrumentation/afs/vertical-vs-mode");
     var spdSelect = getprop("/instrumentation/afs/speed-mode");
     var apMode = getprop("/instrumentation/flightdirector/autopilot-on");
     var bothSelect = MANAGED_MODE;
     if (altSelect == SELECTED_MODE or vsSelect == SELECTED_MODE) {
       bothSelect = SELECTED_MODE;
     }
      me.tracer("bothSelect: "~bothSelect);
      me.tracer("clbArm: "~clbArm);
      me.tracer("spdMode: "~spdMode);
      me.tracer("flapPos: "~flapPos);
       ## managed Speed Reference System mode
       if (curAlt < accAlt and clbArm == 0 and bothSelect == MANAGED_MODE and (spdMode == SPD_FLEX or spdMode == SPD_TOGA or spdMode == SPD_THRCLB) and flapPos > 0 ) {
         retVNAV = VNAV_SRS;
         me.tracer("retVNAV = VNAV_SRS");
       }
       ## managed climb
       if (curAlt >= accAlt and curAlt < (crzAlt-100) and crzAcquire == 0) {
         if (lnavMode == LNAV_FMS) {
           retVNAV = VNAV_CLB;
           me.tracer("retVNAV = VNAV_CLB");
         } else {
           retVNAV = VNAV_OPCLB;
           me.tracer("retVNAV = VNAV_OPCLB");
         }
       }
       ## managed cruise alt
       if (curAlt > (crzAlt-5000) and bothSelect == MANAGED_MODE) {
         retVNAV = VNAV_ALTCRZ;
         me.tracer("retVNAV = VNAV_ALTCRZ");
       }
       ## managed descend
       var wpLen = getprop("/autopilot/route-manager/route/num");
       var curWp = getprop("/autopilot/route-manager/current-wp");
       var foundTD = 0;
       if (curWp > 0) {
         for(w=0; w < curWp; w=w+1) {
           var wpName = getprop("/autopilot/route-manager/route/wp["~w~"]/id");
           if (wpName == "T/D") {
             foundTD = 1;
           }
         }
         me.tracer("foundTD: "~foundTD~", bothSelect: "~bothSelect~", lnavMode: "~lnavMode);
         if(foundTD == 1 and curAlt > 400 and bothSelect == MANAGED_MODE) {
           if (lnavMode == LNAV_FMS) {
             retVNAV = VNAV_DES;
             me.tracer("retVNAV = VNAV_DES");
           } else {
             retVNAV = VNAV_OPDES;
             me.tracer("retVNAV = VNAV_OPDES");
           }
         }
       }
       if (getprop("/position/altitude-agl-ft") < 400 and vnavMode == VNAV_GS and lnavMode == LNAV_LOC) {
         ## combined LAND mode....
       }
     
     return retVNAV;
   },

   ##########
   # evaluate VNAV
   ##########
   evaluateVNAV : func() {
     var retVNAV = VNAV_OFF;
     var apMode = getprop("/instrumentation/flightdirector/autopilot-on");
     if (apMode == 1) {
       retVNAV = me.evaluateManagedVNAV();

       var altSelect = getprop("/instrumentation/afs/vertical-alt-mode");
       var vsSelect = getprop("/instrumentation/afs/vertical-vs-mode");
       if (altSelect == SELECTED_MODE) {
         retVNAV = VNAV_ALTs;
       }
       if (vsSelect == SELECTED_MODE) {
         retVNAV = VNAV_VS;
       }
     }
     return retVNAV;
   },


   #############
   # evaluate managed LNAV
   #
   evaluateManagedLNAV : func() {
     var retLNAV = LNAV_OFF;

     var agl = getprop("/position/altitude-agl-ft");
     

     return retLNAV;
   },



   ####
   #  calculate the current flap position
   #
   getFlapConfig : func() {
     var flapConfig = 0;
     var currFlapPos = getprop("/fdm/jsbsim/fcs/flap-cmd-norm");
     if (currFlapPos == 0.2424) {
       flapConfig = 1;
     }
     if (currFlapPos == 0.5151) {
      flapConfig = 2;
     }
     if (currFlapPos == 0.7878) {
       flapConfig = 3;
     }
     if (currFlapPos == 1.0) {
       flapConfig = 4;
     }
     return flapConfig;
    },

    ###################################
    #  called from the autopilot/route-manager/current-wp tied property listener
    #
    updateCurrentWP : func() {
      var rteWP = getprop("autopilot/route-manager/current-wp");
      var rteWPId = getprop("autopilot/route-manager/route/wp["~rteWP~"]/id");
      var planIdx = me.findWPName(rteWPId);
      if (planIdx != nil) {
        var tmp = int(planIdx/9);
        var mod = (planIdx-(tmp*9));
        setprop("instrumentation/fms/plan[0]/display-nodes/current-wp", mod);
        var currPage = getprop("instrumentation/fms/plan[0]/display-nodes/current-page");
        if (tmp != currPage) {
          setprop("instrumentation/fms/plan[0]/display-nodes/current-page", tmp);
          me.updateDisplay();
        }
      }
    },

    ####
    # copy current page from active flight plan to display nodes
    #
    updateDisplay : func() {
      var startPage = getprop("instrumentation/fms/plan[0]/display-nodes/current-page");
      var startWP = startPage*9;
      var max = size(me.activePlan);
      if (max > 9) {
        max = 9;
      }
      for(var w = 0; w != max; w=w+1) {
        var pos = startWP+w;
        var dn = me.activeFpln.getNode("display-nodes/wp["~w~"]",1);
        ###var wp = me.activeFpln.getNode("wp["~pos~"]",0);
        var wp = me.activePlan[pos];
        if (wp != nil) {
          dn.getNode("id",1).setValue(wp.wp_name);
          dn.getNode("parent",1).setValue(wp.wp_parent_name);
          var spdLim = wp.spd_csrt;
          if (spdLim < 1 and spdLim > 0) {
            dn.getNode("spd-lim-display",1).setValue(sprintf("%01.2f", spdLim));
          } else {
            dn.getNode("spd-lim-display",1).setValue(sprintf("%5.0f", spdLim));
          }
          var altLim = wp.alt_csrt;
          if (altLim > 10000) {
            dn.getNode("alt-lim-display",1).setValue(sprintf("FL%3.0f",(altLim/100)));
          } else {
            dn.getNode("alt-lim-display",1).setValue(sprintf("%5.0f",altLim));
          }
          dn.getNode("wp-type",1).setValue(wp.wp_type);
          ##dn.getNode("time-utc-display",1).setValue(sprintf("%2f:%2f",wp.getNode("time-utc-hours").getIntValue(),wp.getNode("time-utc-mins").getIntValue()));
          dn.getNode("time-utc-display",1).setValue("00:00");
          dn.getNode("active", 1).setBoolValue(1);
          dn.getNode("track",1).setDoubleValue(wp.leg_bearing);
          dn.getNode("dist",1).setIntValue(wp.leg_distance);
        } else {
          dn.getNode("active",1).setBoolValue(0);
        }
      }
    },

    ######
    # add WP to FMS plan.
    #
    appendWP : func(wp) {
      me.tracer("Append WP: "~wp.wp_name~" at pos: "~me.lastWP);
      append(me.activePlan, wp);
      me.lastWP = me.lastWP+1;
      me.updateDisplay();
      return me.lastWP-1;
    },

    ###################
    # insert a WP into FMS plan at positon
    #
    insertWPBefore : func(wp, idx) {
      me.tracer("insert WP: "~wp.wp_name~" at pos: "~idx);
      if (idx > size(me.activePlan)-1) {
        append(me.activePlan, wp);
      } else {
        me.activePlan = setsize(me.activePlan, size(me.activePlan)+1);
        # shuffle down all elements
        for(var p = size(me.activePlan)-1; p > idx; p=p-1) {
          me.activePlan[p] = me.activePlan[p-1];
        }
        me.activePlan[idx] = wp;
        me.lastWP = me.lastWP+1;
      }
      me.updateDisplay();
    },

    ##################
    # replace a WP in plan at specified index
    #
    replaceWPAt : func(wp, idx) {
      me.tracer("replace WP: "~wp.wp_name~" at pos: "~idx);
      if (idx > size(me.activePlan)-1) {
        append(me.activePlan, wp);
      } else {
        me.activePlan[idx] = wp;
      }
      me.updateDisplay();
    },

    ##################
    # find index of WP in plan of the same wp_name
    #
    findWPName : func(name) {
      var retValue = nil;
      forindex(i; me.activePlan) {
        if (me.activePlan[i].wp_name == name) {
          retValue = i;
          break;
        }
      }
      return retValue;
    },

    ###################
    # find index of WP by type
    #
    findWPType : func(type) {
      var retValue = nil;
      forindex(i; me.activePlan) {
        if (me.activePlan[i].wp_type == type) {
          retValue = i;
          break;
        }
      }
      return retValue;
    },

    ##################
    # get WP from display by index
    #
    getWPIdx : func(idx) {
      var startPage = getprop("instrumentation/fms/plan[0]/display-nodes/current-page");
      var wpIdx = startPage*9+idx;
      return me.activePlan[wpIdx];
    },

    ##################
    # get WP from plan by index
    #
    getWP : func(idx) {
      return me.activePlan[idx];
    },

    ###################
    # clear plan
    #
    clearPlan : func() {
      me.lastPos = 0;
      setsize(me.activePlan, 0);
    },

    ###################
    #  get plan size
    #
    getPlanSize : func() {
      return size(me.activePlan);
    }

};

