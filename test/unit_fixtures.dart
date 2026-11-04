// Generated from the edge-ml ml service (app/units): what it writes for a
// model trained on x in m/s^2 (acceleration), y in degC (temperature) and z
// in a custom unit, and its GET /ml/units/ catalog. Plain Dart (no dart:io),
// so the tests also run in the browser and on devices.
// ignore_for_file: lines_longer_than_80_chars

/// `input.units` of the model.
const inputUnitsJson = r'''[
  {
    "name": "x",
    "quantity": "acceleration",
    "unit": "m/s^2",
    "conversions": {
      "m/s^2": {
        "scale": 1.0,
        "offset": 0.0
      },
      "g": {
        "scale": 9.80665,
        "offset": 0.0
      },
      "mg": {
        "scale": 0.00980665,
        "offset": 0.0
      },
      "cm/s^2": {
        "scale": 0.01,
        "offset": 0.0
      }
    }
  },
  {
    "name": "y",
    "quantity": "temperature",
    "unit": "degC",
    "conversions": {
      "degC": {
        "scale": 1.0,
        "offset": 0.0
      },
      "K": {
        "scale": 1.0,
        "offset": -273.15
      },
      "degF": {
        "scale": 0.5555555555555556,
        "offset": -17.77777777777778
      }
    }
  },
  {
    "name": "z",
    "quantity": "strain",
    "unit": "ue",
    "conversions": {}
  }
]''';

/// `GET /ml/units/`.
const unitCatalogJson =
    r'''{"version": 1, "quantities": [{"id": "acceleration", "label": "Acceleration", "defaultUnit": "m/s^2", "units": [{"id": "m/s^2", "label": "m/s²", "scale": 1.0, "offset": 0.0, "aliases": ["m/s²", "m/s2"]}, {"id": "g", "label": "g", "scale": 9.80665, "offset": 0.0, "aliases": []}, {"id": "mg", "label": "mg", "scale": 0.00980665, "offset": 0.0, "aliases": []}, {"id": "cm/s^2", "label": "cm/s²", "scale": 0.01, "offset": 0.0, "aliases": ["cm/s²", "Gal"]}]}, {"id": "angular_velocity", "label": "Angular velocity", "defaultUnit": "deg/s", "units": [{"id": "deg/s", "label": "°/s", "scale": 1.0, "offset": 0.0, "aliases": ["°/s", "dps"]}, {"id": "rad/s", "label": "rad/s", "scale": 57.29577951308232, "offset": 0.0, "aliases": []}, {"id": "rpm", "label": "rpm", "scale": 6.0, "offset": 0.0, "aliases": []}]}, {"id": "angle", "label": "Angle", "defaultUnit": "deg", "units": [{"id": "deg", "label": "°", "scale": 1.0, "offset": 0.0, "aliases": ["°"]}, {"id": "rad", "label": "rad", "scale": 57.29577951308232, "offset": 0.0, "aliases": []}]}, {"id": "temperature", "label": "Temperature", "defaultUnit": "degC", "units": [{"id": "degC", "label": "°C", "scale": 1.0, "offset": 0.0, "aliases": ["°C", "C"]}, {"id": "K", "label": "K", "scale": 1.0, "offset": -273.15, "aliases": []}, {"id": "degF", "label": "°F", "scale": 0.5555555555555556, "offset": -17.77777777777778, "aliases": ["°F", "F"]}]}, {"id": "pressure", "label": "Pressure", "defaultUnit": "hPa", "units": [{"id": "Pa", "label": "Pa", "scale": 1.0, "offset": 0.0, "aliases": []}, {"id": "hPa", "label": "hPa", "scale": 100.0, "offset": 0.0, "aliases": []}, {"id": "kPa", "label": "kPa", "scale": 1000.0, "offset": 0.0, "aliases": []}, {"id": "mbar", "label": "mbar", "scale": 100.0, "offset": 0.0, "aliases": []}, {"id": "bar", "label": "bar", "scale": 100000.0, "offset": 0.0, "aliases": []}, {"id": "atm", "label": "atm", "scale": 101325.0, "offset": 0.0, "aliases": []}, {"id": "psi", "label": "psi", "scale": 6894.757293168, "offset": 0.0, "aliases": []}, {"id": "mmHg", "label": "mmHg", "scale": 133.322387415, "offset": 0.0, "aliases": []}]}, {"id": "magnetic_flux_density", "label": "Magnetic flux density", "defaultUnit": "uT", "units": [{"id": "T", "label": "T", "scale": 1.0, "offset": 0.0, "aliases": []}, {"id": "mT", "label": "mT", "scale": 0.001, "offset": 0.0, "aliases": []}, {"id": "uT", "label": "µT", "scale": 1e-06, "offset": 0.0, "aliases": ["µT", "μT"]}, {"id": "nT", "label": "nT", "scale": 1e-09, "offset": 0.0, "aliases": []}, {"id": "G", "label": "G (gauss)", "scale": 0.0001, "offset": 0.0, "aliases": ["gauss"]}, {"id": "mG", "label": "mG", "scale": 1e-07, "offset": 0.0, "aliases": []}]}, {"id": "relative_humidity", "label": "Relative humidity", "defaultUnit": "%", "units": [{"id": "%", "label": "%", "scale": 1.0, "offset": 0.0, "aliases": ["%RH"]}, {"id": "fraction", "label": "fraction (0–1)", "scale": 100.0, "offset": 0.0, "aliases": []}]}, {"id": "voltage", "label": "Voltage", "defaultUnit": "V", "units": [{"id": "V", "label": "V", "scale": 1.0, "offset": 0.0, "aliases": []}, {"id": "mV", "label": "mV", "scale": 0.001, "offset": 0.0, "aliases": []}, {"id": "uV", "label": "µV", "scale": 1e-06, "offset": 0.0, "aliases": ["µV", "μV"]}, {"id": "kV", "label": "kV", "scale": 1000.0, "offset": 0.0, "aliases": []}]}, {"id": "current", "label": "Electric current", "defaultUnit": "mA", "units": [{"id": "A", "label": "A", "scale": 1.0, "offset": 0.0, "aliases": []}, {"id": "mA", "label": "mA", "scale": 0.001, "offset": 0.0, "aliases": []}, {"id": "uA", "label": "µA", "scale": 1e-06, "offset": 0.0, "aliases": ["µA", "μA"]}]}, {"id": "length", "label": "Length / distance", "defaultUnit": "m", "units": [{"id": "m", "label": "m", "scale": 1.0, "offset": 0.0, "aliases": []}, {"id": "cm", "label": "cm", "scale": 0.01, "offset": 0.0, "aliases": []}, {"id": "mm", "label": "mm", "scale": 0.001, "offset": 0.0, "aliases": []}, {"id": "km", "label": "km", "scale": 1000.0, "offset": 0.0, "aliases": []}, {"id": "in", "label": "in", "scale": 0.0254, "offset": 0.0, "aliases": []}, {"id": "ft", "label": "ft", "scale": 0.3048, "offset": 0.0, "aliases": []}]}, {"id": "velocity", "label": "Velocity", "defaultUnit": "m/s", "units": [{"id": "m/s", "label": "m/s", "scale": 1.0, "offset": 0.0, "aliases": []}, {"id": "km/h", "label": "km/h", "scale": 0.2777777777777778, "offset": 0.0, "aliases": []}, {"id": "mph", "label": "mph", "scale": 0.44704, "offset": 0.0, "aliases": []}, {"id": "kn", "label": "kn", "scale": 0.5144444444444445, "offset": 0.0, "aliases": []}]}, {"id": "frequency", "label": "Frequency / rate", "defaultUnit": "Hz", "units": [{"id": "Hz", "label": "Hz", "scale": 1.0, "offset": 0.0, "aliases": []}, {"id": "kHz", "label": "kHz", "scale": 1000.0, "offset": 0.0, "aliases": []}, {"id": "bpm", "label": "bpm (per minute)", "scale": 0.016666666666666666, "offset": 0.0, "aliases": ["1/min"]}]}, {"id": "illuminance", "label": "Illuminance", "defaultUnit": "lx", "units": [{"id": "lx", "label": "lx", "scale": 1.0, "offset": 0.0, "aliases": ["lux"]}]}, {"id": "sound_level", "label": "Sound level", "defaultUnit": "dB", "units": [{"id": "dB", "label": "dB", "scale": 1.0, "offset": 0.0, "aliases": ["dBA", "dB(A)"]}]}, {"id": "mass", "label": "Mass", "defaultUnit": "kg", "units": [{"id": "kg", "label": "kg", "scale": 1.0, "offset": 0.0, "aliases": []}, {"id": "g", "label": "g", "scale": 0.001, "offset": 0.0, "aliases": []}]}, {"id": "force", "label": "Force", "defaultUnit": "N", "units": [{"id": "N", "label": "N", "scale": 1.0, "offset": 0.0, "aliases": []}, {"id": "kN", "label": "kN", "scale": 1000.0, "offset": 0.0, "aliases": []}]}, {"id": "power", "label": "Power", "defaultUnit": "W", "units": [{"id": "W", "label": "W", "scale": 1.0, "offset": 0.0, "aliases": []}, {"id": "mW", "label": "mW", "scale": 0.001, "offset": 0.0, "aliases": []}, {"id": "kW", "label": "kW", "scale": 1000.0, "offset": 0.0, "aliases": []}]}, {"id": "time", "label": "Duration", "defaultUnit": "s", "units": [{"id": "s", "label": "s", "scale": 1.0, "offset": 0.0, "aliases": []}, {"id": "ms", "label": "ms", "scale": 0.001, "offset": 0.0, "aliases": []}, {"id": "us", "label": "µs", "scale": 1e-06, "offset": 0.0, "aliases": ["µs", "μs"]}]}, {"id": "ratio", "label": "Ratio / dimensionless", "defaultUnit": "1", "units": [{"id": "1", "label": "1 (unitless)", "scale": 1.0, "offset": 0.0, "aliases": [""]}, {"id": "%", "label": "%", "scale": 0.01, "offset": 0.0, "aliases": []}]}]}''';
