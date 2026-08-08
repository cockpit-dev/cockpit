import '../system_control/cockpit_system_control_profile.dart';
import 'cockpit_supervisor_operation_catalog.dart';

part 'cockpit_supervisor_operation_request_schemas.dart';
part 'cockpit_supervisor_operation_response_schemas.dart';

final class CockpitSupervisorOperationSchema {
  CockpitSupervisorOperationSchema._();

  static Map<String, Object?> document() {
    final definitions = <String, Object?>{};
    for (final descriptor in CockpitSupervisorOperationCatalog.allOperations) {
      final request = _requestSchemas[descriptor.kind];
      final response = _responseSchemas[descriptor.kind];
      if (request == null || response == null) {
        throw StateError(
          'Missing public operation contract: ${descriptor.kind}.',
        );
      }
      definitions['${descriptor.kind}.request'] = request;
      definitions['${descriptor.kind}.response'] = response;
    }
    return <String, Object?>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      r'$id': 'cockpit://operations/schema',
      'title': 'Cockpit live operation contracts',
      r'$defs': definitions,
    };
  }
}

Map<String, Object?> _object({
  Map<String, Object?> properties = const <String, Object?>{},
  List<String> required = const <String>[],
  String precision = 'exact',
  String? description,
  List<Map<String, Object?>> examples = const <Map<String, Object?>>[],
  List<Map<String, Object?>> oneOf = const <Map<String, Object?>>[],
  List<Map<String, Object?>> allOf = const <Map<String, Object?>>[],
  bool additionalProperties = false,
}) => <String, Object?>{
  'type': 'object',
  'properties': properties,
  if (required.isNotEmpty) 'required': required,
  'additionalProperties': additionalProperties,
  if (oneOf.isNotEmpty) 'oneOf': oneOf,
  if (allOf.isNotEmpty) 'allOf': allOf,
  if (examples.isNotEmpty) 'examples': examples,
  'x-cockpit-precision': precision,
  'description': ?description,
};

const Map<String, Object?> _id = <String, Object?>{
  'type': 'string',
  'pattern': r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$',
};
const Map<String, Object?> _networkRequestId = <String, Object?>{
  'type': 'string',
  'pattern': r'^[1-9][0-9]{0,18}$',
};
const Map<String, Object?> _positiveTimeout = <String, Object?>{
  'type': 'integer',
  'minimum': 1,
  'maximum': 1800000,
};
const Map<String, Object?> _boolean = <String, Object?>{'type': 'boolean'};
const Map<String, Object?> _integer = <String, Object?>{'type': 'integer'};
const Map<String, Object?> _string = <String, Object?>{
  'type': 'string',
  'minLength': 1,
};
const Map<String, Object?> _absoluteHttpUrl = <String, Object?>{
  'type': 'string',
  'minLength': 8,
  'maxLength': 2048,
  'format': 'uri',
  'pattern': r'^[Hh][Tt][Tt][Pp][Ss]?://[^/?#\s]+(?:[/?#].*)?$',
};
const Map<String, Object?> _sha256 = <String, Object?>{
  'type': 'string',
  'pattern': r'^[a-f0-9]{64}$',
};
const Map<String, Object?> _utcTimestamp = <String, Object?>{
  'type': 'string',
  'format': 'date-time',
};
const Map<String, Object?> _jsonObject = <String, Object?>{'type': 'object'};
const Map<String, Object?> _stringList = <String, Object?>{
  'type': 'array',
  'items': _string,
};
const Map<String, Object?> _profile = <String, Object?>{
  'type': 'string',
  'enum': <String>['minimal', 'locate', 'standard', 'inspect', 'evidence'],
};
const Map<String, Object?> _sessionId = <String, Object?>{
  ..._id,
  'description': 'Injected automatically by --session for Cockpit CLI calls.',
  'x-cockpit-injected-by': '--session',
};
const Map<String, Object?> _launchConfiguration = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'dartDefines': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{'type': 'string', 'minLength': 3},
      'maxItems': 1024,
    },
    'dartDefineFromFiles': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{'type': 'string', 'minLength': 1},
      'maxItems': 1024,
    },
    'flutterArgs': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{'type': 'string', 'minLength': 1},
      'maxItems': 1024,
    },
    'environment': <String, Object?>{
      'type': 'object',
      'additionalProperties': <String, Object?>{'type': 'string'},
      'maxProperties': 1024,
    },
  },
  'additionalProperties': false,
};

Map<String, Object?> _boundedInteger(int minimum, int maximum, {int? value}) =>
    <String, Object?>{
      'type': 'integer',
      'minimum': minimum,
      'maximum': maximum,
      'default': ?value,
    };

Map<String, Object?> _boundedString(int maximum) => <String, Object?>{
  'type': 'string',
  'minLength': 1,
  'maxLength': maximum,
};

Map<String, Object?> _nonBlankBoundedString(int maximum) => <String, Object?>{
  ..._boundedString(maximum),
  'pattern': r'\S',
};

Map<String, Object?> _enum(List<String> values, {String? defaultValue}) =>
    <String, Object?>{
      'type': 'string',
      'enum': values,
      'default': ?defaultValue,
    };

Map<String, Object?> _array(
  Map<String, Object?> items, {
  int? minimum,
  int? maximum,
  bool unique = false,
}) => <String, Object?>{
  'type': 'array',
  'items': items,
  'minItems': ?minimum,
  'maxItems': ?maximum,
  if (unique) 'uniqueItems': true,
};

Map<String, Object?> _sessionRequest({
  Map<String, Object?> properties = const <String, Object?>{},
  List<String> required = const <String>[],
  String precision = 'exact',
}) => _object(
  properties: <String, Object?>{'sessionId': _sessionId, ...properties},
  required: <String>['sessionId', ...required],
  precision: precision,
);

Map<String, Object?> _structuralResponse(
  String description, {
  Map<String, Object?> properties = const <String, Object?>{},
  List<String> required = const <String>[],
}) => _object(
  properties: properties,
  required: required,
  precision: 'structural',
  description: description,
  additionalProperties: true,
);
