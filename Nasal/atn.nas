#############################################################################
#
# Aeronatical Telecommunications Network
#
# Abstract:
#    Provides Controller-Pilot and Pilot-Airline communications
# 
# 
# Author: S.Hamilton Jan 2012
#
#
#   Copyright (C) 2012 Scott Hamilton
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

atn_trace = 1;



var atn = {
   
   new : func() {
     var m = {parents : [atn]};
     m.atnNode = props.globals.getNode("/instrumentation/atn",1);
     m.version = "V1.0.0";
     m.baseURL = "http://example.com/";
     var baseURLNode = m.atnNode.getChild("atc-url-base",0);
     if (baseURLNode == nil) {
       print("[ATN] set <atc-url-base> in your aircraft -set.xml file");
       m.atnNode.getChild("atc-url-base",1).setValue(m.baseURL);
     } else {
       m.baseURL = baseURLNode.getValue();
       print("baseURL: "~m.baseURL);
     }
     m.sessionId = "";
     m.mseq = 1;

     setlistener("/sim/signals/fdm-initialized", func m.init());
     setlistener("/instrumentation/atn/http-complete", func m.atnHTTPStateChange());
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
  if (atn_trace > 0) {
    print("[ATN] time: "~timeStr~" alt: "~curAltStr~", - "~msg);
    if (atn_trace > 1) {
      print("[ATN] vnav: "~me.afs.vertical_text[curVnav]~", lnav: "~me.afs.lateral_text[curLnav]~", spd: "~me.afs.spd_text[curSpd]);
    }
  }
},

   ####
   # init
   ####
   init : func() {
      me.atnNode.getNode("serviceable", 1).setBoolValue(1);
      setlistener("/instrumentation/atn/serviceable", func me.serviceableUpdate());
      ##settimer(func me.update(), 0);
      settimer(func me.slow_update(), 5);
      print("ATN "~me.version~" ready");
    },


   ### for high prio tasks ###
   update : func() {
     settimer(func me.update(), 1);
   }, 


   ### listen for changes in serviceable ###
   serviceableUpdate : func() {
     me.tracer("serviceable change");
     if (me.atnNode.getNode("serviceable") == 1) {
       settimer(func me.slow_update(), 3);
     }
   },


   ### for low prio tasks ###
   slow_update : func() {
     if (me.sessionId != "0" and me.sessionId != "") {
       me.tracer("ATN poll");
       me.tracer("sessionId: "~me.sessionId);
       var cmd = getprop("instrumentation/atn/out-of-band/command");
       if (cmd != nil and cmd != "") {
         me.tracer("[OOB] execute command: "~cmd);
         setprop("instrumentation/atn/out-of-band/command", "");
       }
       var url = me.baseURL~"/pollCommands.jsf?xid="~me.sessionId;
       var params = props.Node.new( {"url": url, "targetnode": "/instrumentation/atn/out-of-band"} );
       fgcommand("xmlhttprequest", params);
     }
     if (me.atnNode.getNode("serviceable").getBoolValue() == 1) {
       settimer(func me.slow_update(), 15);
     }
   },


   ### announce ourselves to the local controller system ###
   doLogon : func() {
     var airport      = getprop("instrumentation/afs/ATC_logon_icao");
     var callSign     = getprop("instrumentation/afs/FLT_NBR");
     var username     = getprop("instrumentation/afs/ATC_logon_username");
     var aircraftType = getprop("instrumentation/afs/ATC_logon_acft-type");
     me.makeRequest("doLogon","callsign="~callSign~"&user="~username~"&type="~aircraftType~"&airport="~airport);
   },

   doLogonCallback : func() {
     xid = getprop("instrumentation/atn/received/session-id");
     me.tracer("[LOGON] set sessionId: "~xid);
     me.sessionId = xid;
   },

   ### logoff for completeness ###
   doLogoff : func() {
     if (me.sessionId != "") {
       var callSign = getprop("instrumentation/afs/FLT_NBR");
       me.makeRequest("doLogoff", "callsign="~callSign);
     }
   },


   ### request a company route, and load it into the FMS ###
   doGetCompanyRoute : func() {

   },


   ### send current fuel, weight and odometer to airline ###
   doSendFuelInfo : func() {
   
   },


   ### send a position report to controller ###
   doPositionReport : func() {
   
   },


   ### request ground clearance ###
   doRequestGroundClearance : func() {

   },


   ### arrival gate request ###
   doRequestGate : func() {

   },


   ### make a request ###
   makeRequest : func(function, params) {
     setprop("instrumentation/atn/req-func", function);
     var url = me.baseURL~"/"~function~".jsf?"~params~"&xid="~me.sessionId~"&seq="~me.mseq;
     me.mseq = me.mseq+1;
     var params = props.Node.new( {"url": url, "targetnode": "/instrumentation/atn/received", "status": "/instrumentation/atn/http-status", "complete": "instrumentation/atn/http-complete", "failure": "/instrumentation/atn/http-failure"} );
     me.tracer("[REQ] url: "~url);
     fgcommand("xmlhttprequest", params);
     me.tracer("[REQ] done");
   },


   ### listener HTTP State change ###
   atnHTTPStateChange : func() {
     var httpState = getprop("instrumentation/atn/http-status");
     var msg = sprintf("HTTP state change: %u\n",httpState);
     me.tracer(msg);
     var callBack = getprop("instrumentation/atn/req-func");
     if (callBack == "doLogon") {
       me.doLogonCallback();
     }

   }

};