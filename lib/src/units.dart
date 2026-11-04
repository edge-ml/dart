import 'errors.dart';

/// Converts a value from one unit to another: `value * scale + offset`.
class UnitConversion {
  /// Creates a conversion.
  const UnitConversion(this.scale, [this.offset = 0]);

  /// Parses `{scale, offset}`.
  factory UnitConversion.fromJson(Map<String, dynamic> json) =>
      UnitConversion((json['scale'] as num).toDouble(), (json['offset'] as num? ?? 0).toDouble());

  /// Factor applied first.
  final double scale;

  /// Added after scaling.
  final double offset;

  /// Whether the conversion leaves values unchanged.
  bool get isIdentity => scale == 1 && offset == 0;

  /// Converts [value].
  double apply(num value) => value * scale + offset;

  @override
  String toString() => 'UnitConversion(×$scale + $offset)';
}

/// The unit a model expects for one input (time-series), and how to convert
/// other units of the same quantity to it. Read from the model's manifest
/// (`input.units`) or from [ModelInfo.inputUnits].
class InputUnit {
  /// Creates an [InputUnit].
  const InputUnit({required this.name, this.quantity, this.unit = '', this.conversions = const {}});

  /// An input nothing is known about (models trained before units existed).
  const InputUnit.unknown(this.name) : quantity = null, unit = '', conversions = const {};

  /// Parses one entry of `input.units` / `inputUnits`.
  factory InputUnit.fromJson(Map<String, dynamic> json) => InputUnit(
    name: json['name'] as String,
    quantity: _nonEmpty(json['quantity'] as String?),
    unit: json['unit'] as String? ?? '',
    conversions: {
      for (final e in ((json['conversions'] as Map?) ?? const {}).entries)
        '${e.key}': UnitConversion.fromJson((e.value as Map).cast<String, dynamic>()),
    },
  );

  /// The expected unit of every input of a manifest's `input` object, ONNX
  /// and ExecuTorch alike, in `input.timeseries` order. Exports made before
  /// units existed have no `units`: every input is unknown.
  static List<InputUnit> listFromManifestInput(Map<String, dynamic> input) {
    final names = (input['timeseries'] as List).cast<String>();
    final byName = {
      for (final u in ((input['units'] as List?) ?? const []).cast<Map<String, dynamic>>())
        u['name'] as String: InputUnit.fromJson(u),
    };
    return [for (final n in names) byName[n] ?? InputUnit.unknown(n)];
  }

  /// Time-series name.
  final String name;

  /// Quantity id of the unit catalog (e.g. `acceleration`), a custom label,
  /// or `null` when unknown.
  final String? quantity;

  /// The unit the model expects, e.g. `m/s^2`; empty when unknown.
  final String unit;

  /// Conversion to [unit] from every catalog unit of [quantity], by unit id.
  final Map<String, UnitConversion> conversions;

  /// Whether the model knows the unit of this input. Values of unknown
  /// inputs are passed to the model as they are.
  bool get isKnown => quantity != null || unit.isNotEmpty;

  /// JSON as in the manifest.
  Map<String, Object?> toJson() => {
    'name': name,
    'quantity': quantity,
    'unit': unit,
    'conversions': {
      for (final e in conversions.entries) e.key: {'scale': e.value.scale, 'offset': e.value.offset},
    },
  };

  @override
  String toString() =>
      isKnown ? 'InputUnit($name: $unit${quantity != null ? ' ($quantity)' : ''})' : 'InputUnit($name: unknown)';
}

/// One unit of a [UnitQuantity]: `base = value * scale + offset`.
class CatalogUnit {
  /// Creates a [CatalogUnit].
  const CatalogUnit({required this.id, required this.label, this.scale = 1, this.offset = 0, this.aliases = const []});

  /// Parses a unit of the catalog.
  factory CatalogUnit.fromJson(Map<String, dynamic> json) => CatalogUnit(
    id: json['id'] as String,
    label: json['label'] as String? ?? json['id'] as String,
    scale: (json['scale'] as num? ?? 1).toDouble(),
    offset: (json['offset'] as num? ?? 0).toDouble(),
    aliases: ((json['aliases'] as List?) ?? const []).cast<String>(),
  );

  /// Unit id, e.g. `m/s^2`.
  final String id;

  /// Display label, e.g. `m/s²`.
  final String label;

  /// Scale to the quantity's base unit.
  final double scale;

  /// Offset to the quantity's base unit.
  final double offset;

  /// Other spellings, e.g. `m/s2`.
  final List<String> aliases;

  /// Whether [unit] is this unit's id, label or one of its aliases.
  bool matches(String unit) => unit == id || unit == label || aliases.contains(unit);
}

/// A physical quantity of the catalog with its units.
class UnitQuantity {
  /// Creates a [UnitQuantity].
  const UnitQuantity({required this.id, required this.label, required this.defaultUnit, required this.units});

  /// Parses a quantity of the catalog.
  factory UnitQuantity.fromJson(Map<String, dynamic> json) => UnitQuantity(
    id: json['id'] as String,
    label: json['label'] as String? ?? json['id'] as String,
    defaultUnit: json['defaultUnit'] as String,
    units: [for (final u in (json['units'] as List).cast<Map<String, dynamic>>()) CatalogUnit.fromJson(u)],
  );

  /// Quantity id, e.g. `acceleration`.
  final String id;

  /// Display label, e.g. "Acceleration".
  final String label;

  /// The unit training converts to and models expect, e.g. `m/s^2`.
  final String defaultUnit;

  /// The units of this quantity.
  final List<CatalogUnit> units;

  /// The unit with this id, label or alias, if any.
  CatalogUnit? unit(String unit) {
    for (final u in units) {
      if (u.matches(unit)) return u;
    }
    return null;
  }
}

/// The edge-ml server's catalog of quantities and units, from
/// [EdgeML.unitCatalog].
class UnitCatalog {
  /// Creates a [UnitCatalog].
  const UnitCatalog({required this.version, required this.quantities});

  /// Parses the response of `GET /ml/units/`.
  factory UnitCatalog.fromJson(Map<String, dynamic> json) => UnitCatalog(
    version: (json['version'] as num? ?? 1).toInt(),
    quantities: [
      for (final q in ((json['quantities'] as List?) ?? const []).cast<Map<String, dynamic>>())
        UnitQuantity.fromJson(q),
    ],
  );

  /// Catalog format version.
  final int version;

  /// All quantities.
  final List<UnitQuantity> quantities;

  /// The quantity with this id, if any.
  UnitQuantity? quantity(String id) {
    for (final q in quantities) {
      if (q.id == id) return q;
    }
    return null;
  }
}

/// Works out how to convert each of [inputs] from the unit an app delivers
/// ([sensorUnits], by time-series name) to the unit the model expects.
/// Returns one conversion per input, `null` where values pass through
/// unchanged: undeclared sensors, inputs of unknown unit, and declared units
/// equal to the expected one. Units of sensors the model does not use are
/// ignored.
///
/// Throws [UnitException] if a declared unit cannot be converted. Units are
/// matched by catalog id; with a [catalog], labels and aliases (e.g. `°F`)
/// are accepted too.
List<UnitConversion?> resolveUnitConversions(
  List<InputUnit> inputs,
  Map<String, String> sensorUnits, {
  UnitCatalog? catalog,
}) => [for (final input in inputs) _resolve(input, sensorUnits[input.name], catalog)];

UnitConversion? _resolve(InputUnit input, String? unit, UnitCatalog? catalog) {
  // not declared, or the model was trained on data of unknown unit: as today
  if (unit == null || !input.isKnown) return null;

  var conversion = input.conversions[unit];
  if (conversion == null && unit != input.unit && input.quantity != null && catalog != null) {
    final id = catalog.quantity(input.quantity!)?.unit(unit)?.id;
    if (id != null) conversion = input.conversions[id] ?? (id == input.unit ? const UnitConversion(1) : null);
  }
  if (conversion == null && unit == input.unit) conversion = const UnitConversion(1);
  if (conversion == null) {
    final expected =
        '${input.unit.isEmpty ? 'no unit' : input.unit}${input.quantity != null ? ' (${input.quantity})' : ''}';
    final accepted = input.conversions.keys.toList();
    throw UnitException(
      "'${input.name}' is declared in '$unit', but the model expects $expected and cannot convert from '$unit'. "
      '${accepted.length > 1 ? 'Accepted units: ${accepted.join(', ')}.' : 'Deliver it in ${input.unit.isEmpty ? 'the unit it was trained on' : input.unit}.'}',
    );
  }
  return conversion.isIdentity ? null : conversion;
}

String? _nonEmpty(String? s) => s == null || s.isEmpty ? null : s;
