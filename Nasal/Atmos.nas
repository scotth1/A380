#
#   Simple utility to perform atmospheric conversions
#
#
#   Copyright (C) 2011 Scott Hamilton
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#


###### Constants ############

p0             = 101325.0;                     # [N/m^2] = [Pa]
p1             = 22632.22842714;               # [N/m^2] = [Pa]

p0hPa          = 1013.25;                      # [hPa]
p0inHG         =   29.92;                      # [inHG] Truncated 29.9213
p0mmHG         = p0inHG*25.4;                  # [mmHG] with 25.4 [mm] = 1.0 [in]

T0             =    288.15;                    # [K]
T1             =    216.65;                    # [K]

h1             =  36089.2388451444;            # [ft]
h2             =  65616.7979002625;            # [ft]

dTdh0          =     -0.0019812;               # [K/ft]
dTdh0SI        =     -0.0065;                  # [K/m]

CPascalTOPSI   = 0.000145037737730209;         # 1.45037737730209e-04
ChPaTOinHG     = p0inHG/p0hPa;
ChPaTOmmHG     = p0mmHG/p0hPa;

ClbPft3TOkgPm3 = 16.0184633739601;                 # [lb/ft^3] to [kg/m^3]

CftTOm         =      0.3048;
CftTOnm        = 1.64578833693305e-04;

CnmTOm         =   1852.0;

CftPsTOkn      = CftTOnm*3600.0;
CftPsTOmph     = 3600.0/5280.0;
CftPsTOkph     = CftTOm*3600.0/1000.0;

CmPsTOkn       = 3600.0/CnmTOm;

CknTOftPs      = 1.0/(CftTOnm*3600.0);

CRGasSI        =    287.053;                       # [m^2/(s^2*K)] = [J/(kg*K)]

CgSI           =      9.80665;                     # [m/s^2]

CgRGas         = (CgSI*CftTOm)/CRGasSI;
CgRGasSI       = CgSI/CRGasSI;

CgRGas         = (CgSI*CftTOm)/CRGasSI;

CGamma         =      1.4;                         # [-]
CGammaRGas     = (CGamma*CRGasSI)/(CftTOm*CftTOm); # [ft^2/(s^2*K)]

CaSLSI         = math.sqrt(CGamma*CRGasSI*T0);
CPressureSLSI  = 101325;                           # [Pa] = [N/m^2]
CaSLNU         = CaSLSI*CmPsTOkn;                  # [kts] Nautical Unit


CKelvinTOCelsius                 = 273.15;
CKelvinTORankine                 =   1.8;

CCelsiusTOFahrenheitLinear       =  32.0;
CCelsiusTOFahrenheitProportional =   1.8;


var Atmos = {

    new : func(){
        var m = {parents:[Atmos]};
        return m;
    },


  #
  # now the utility functions
  #

  psi2pa : func(psi) {
    return psi/CPascalTOPSI;
  },


  inHg2psi : func(inHg) {
    var p = inHg/2.036259;
    return p;
  },

  inHg2pa : func(inHg) {
    return (inHg/ChPaTOinHG)*100.0;
  },


  calculateCrossover : func(kts, mach) {
    var CAS = kts;
    var alt = 0.0;

    var Pressure = (p0*((math.pow(((math.pow(CAS, 2)/(5*math.pow(CaSLNU, 2))) + 1), (CGamma/(CGamma - 1)))) - 1))/((math.pow((((math.pow(mach, 2))/5) + 1), (CGamma/(CGamma - 1)))) - 1);

    if (Pressure < p1) {
      alt = h1 - (T1/CgRGas)*math.ln(Pressure/p1);
    } else {
      alt = (((T0*(math.pow((Pressure/p0) , (-dTdh0SI/CgRGasSI)))) - T0)/dTdh0);
    }

    return alt;  # in ft
  },


  #
  # convert from height to pressure
  # inputUnits can be one of;
  #   * feet
  #   * metre
  #
  # outputUnits can be one of;
  #  * hectoPascal
  #  * Pascal
  #  * psi
  #  * inHg
  convertAltitudePressure : func(inputUnits, value, outputUnits) {
    var h = 0.0;
    if (inputUnits == "feet") {
      h = value;
    }
    if (inputUnits == "metre") {
      h = value/CftTOm;
    }

    # Sanity Checks ...
    if (h > h2) {
      h = h2;
    }
    var T = 0.0;
    var p = 0.0;   # in Pascals

    #
    # Calculations
    #
    if (h <= h1) {
      # Troposphere
      T = T0 + dTdh0*h;
      p = p0*math.pow((T0/T), (CgRGasSI/dTdh0SI));
    } else {
      # Tropopause
      T = T1;
      p = p1*math.exp((CgRGas/T1)*(h1 - h));
    }
    var Rho = p/(CRGasSI*T);
    var a   = math.sqrt(CGammaRGas*T);


    if (outputUnits == "hectoPascal") {
      p = p/100.0;
    }
    if (outputUnits == "psi") {
      p = p*CPascalTOPSI;
    }
    if (outputUnits == "inHg") {
      p = p/100.0;
      p = p*ChPaTOinHG;
    }
    return p;
  },


  #
  # convert from pressure to altitude
  #
  convertPressureAltitude : func(inputUnits, value, outputUnits) {
  
    var p = 0.0;
    if (inputUnits == "hectoPascal") {
      p = value*100.0;
    }
    if (inputUnits == "Pascal") {
      p =  value;
    }
    if (inputUnits == "psi") {
      p = value/CPascalTOPSI;
    }
    if (inputUnits == "inHg") {
      p = value*100.0/ChPaTOinHG;
    }
    if (inputUnits == "mmHg") {
      p = value*100.0/ChPaTOmmHG;
    }

    if (p >= p1) {
      # Troposphere
      h = T0*(math.pow((p0/p), (dTdh0SI/CgRGasSI)) - 1.0)/dTdh0;
    } else {
      # Tropopause
      h = h1 - math.ln(p/p1)*T1/CgRGas;
    }

    var alt = 0.0;
    if (outputUnits == "feet") {
      alt = h;
    }
    if (outputUnits == "metre") {
      alt = h*CftTOm;
    }
    return alt;
}

};
