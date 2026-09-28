import 'package:cockpit_test/catalog_io.dart';
import 'package:cockpit_test/cockpit_test.dart';
import 'package:test/test.dart';

String _format(
  String template,
  Map<String, Object?> params,
  String localeTag,
) => CockpitIcuMessage.parse(
  template,
).format(params, locale: CockpitLocaleProfile(localeTag));

void main() {
  group('ICU message parsing and formatting', () {
    test('plain text round-trips', () {
      expect(_format('Saved', {}, 'en-US'), 'Saved');
      expect(_format('  spaces  stay  ', {}, 'en-US'), '  spaces  stay  ');
    });

    test('placeholders substitute named parameters', () {
      expect(
        _format('Hello {name}, bye {name}', {'name': 'Alice'}, 'en-US'),
        'Hello Alice, bye Alice',
      );
      expect(_format('{n} items', {'n': 2.0}, 'en-US'), '2 items');
      expect(_format('{n} items', {'n': 2.5}, 'en-US'), '2.5 items');
      expect(_format('{flag}', {'flag': true}, 'en-US'), 'true');
    });

    test('missing and null parameters fail loudly', () {
      expect(() => _format('Hello {name}', {}, 'en-US'), throwsFormatException);
      expect(
        () => _format('Hello {name}', {'other': 'x'}, 'en-US'),
        throwsFormatException,
      );
    });

    test('English plurals pick one and other', () {
      const template =
          '{count, plural, =0{no items} one{one item} other{# items}}';
      expect(_format(template, {'count': 0}, 'en-US'), 'no items');
      expect(_format(template, {'count': 1}, 'en-US'), 'one item');
      expect(_format(template, {'count': 2}, 'en-US'), '2 items');
      expect(_format(template, {'count': 42}, 'en-US'), '42 items');
    });

    test('exact selectors win over categories', () {
      const template =
          '{count, plural, =1{exactly one} one{category one} other{#}}';
      expect(_format(template, {'count': 1}, 'en-US'), 'exactly one');
      expect(_format(template, {'count': 21}, 'en-US'), '21');
    });

    test('bare categories follow CLDR rules, not exact numbers', () {
      // English CLDR never selects zero, so 0 falls to other here.
      const template = '{count, plural, zero{zero} other{# things}}';
      expect(_format(template, {'count': 0}, 'en-US'), '0 things');
    });

    test('Chinese plurals collapse into other', () {
      const template = '{count, plural, =0{没有} other{# 项}}';
      expect(_format(template, {'count': 0}, 'zh-Hans-CN'), '没有');
      expect(_format(template, {'count': 1}, 'zh-Hans-CN'), '1 项');
      expect(_format(template, {'count': 100}, 'zh-Hans-CN'), '100 项');
    });

    test('Arabic plurals exercise every CLDR category', () {
      const template =
          '{count, plural, zero{zero} one{one} two{two} few{few} '
          'many{many} other{#}}';
      expect(_format(template, {'count': 0}, 'ar-SA'), 'zero');
      expect(_format(template, {'count': 1}, 'ar-SA'), 'one');
      expect(_format(template, {'count': 2}, 'ar-SA'), 'two');
      expect(_format(template, {'count': 3}, 'ar-SA'), 'few');
      expect(_format(template, {'count': 10}, 'ar-SA'), 'few');
      expect(_format(template, {'count': 11}, 'ar-SA'), 'many');
      expect(_format(template, {'count': 99}, 'ar-SA'), 'many');
      expect(_format(template, {'count': 100}, 'ar-SA'), '100');
    });

    test('Russian plurals follow the few and many boundaries', () {
      const template = '{count, plural, one{one} few{few} many{many} other{#}}';
      expect(_format(template, {'count': 1}, 'ru-RU'), 'one');
      expect(_format(template, {'count': 2}, 'ru-RU'), 'few');
      expect(_format(template, {'count': 5}, 'ru-RU'), 'many');
      // CLDR Russian: 11-14 select many, only fractions reach other.
      expect(_format(template, {'count': 11}, 'ru-RU'), 'many');
      expect(_format(template, {'count': 21}, 'ru-RU'), 'one');
      expect(_format(template, {'count': 1.5}, 'ru-RU'), '1.5');
    });

    test('missing category branches fall back to other', () {
      const template = '{count, plural, one{one} other{# cats}}';
      expect(_format(template, {'count': 3}, 'en-US'), '3 cats');
      expect(_format(template, {'count': 3}, 'pl-PL'), '3 cats');
    });

    test('decimal plural values format through the number', () {
      const template = '{count, plural, one{# mile} other{# miles}}';
      expect(_format(template, {'count': 1.5}, 'en-US'), '1.5 miles');
    });

    test('non-number plural arguments are rejected', () {
      expect(
        () => _format('{n, plural, other{#}}', {'n': 'many'}, 'en-US'),
        throwsFormatException,
      );
      expect(
        () => _format('{n, plural, other{#}}', {}, 'en-US'),
        throwsFormatException,
      );
    });

    test('select and gender choose keyword branches', () {
      const template = '{who, select, male{he} female{she} other{they}}';
      expect(_format(template, {'who': 'male'}, 'en-US'), 'he');
      expect(_format(template, {'who': 'female'}, 'en-US'), 'she');
      expect(_format(template, {'who': 'unknown'}, 'en-US'), 'they');
      expect(_format(template, {}, 'en-US'), 'they');

      const gender = '{who, gender, male{his} female{her} other{their}}';
      expect(_format(gender, {'who': 'female'}, 'en-US'), 'her');
    });

    test('constructs nest and the innermost plural owns the hash', () {
      const template =
          '{count, plural, =0{none} other{'
          '{who, select, adult{# adults} child{# children} other{# people}}'
          '}}';
      expect(
        _format(template, {'count': 4, 'who': 'child'}, 'en-US'),
        '4 children',
      );
      expect(_format(template, {'count': 0}, 'en-US'), 'none');

      const nestedPlural =
          '{outer, plural, other{({inner, plural, one{one of #} other{#}})}}';
      // '#' binds to the innermost plural, so it renders the inner value.
      expect(
        _format(nestedPlural, {'outer': 9, 'inner': 1}, 'en-US'),
        '(one of 1)',
      );
      expect(_format(nestedPlural, {'outer': 9, 'inner': 5}, 'en-US'), '(5)');
    });

    test('hash is a literal outside plural branches', () {
      expect(_format('rank #1', {}, 'en-US'), 'rank #1');
      expect(
        _format('{w, select, a{value #1} other{o}}', {'w': 'a'}, 'en-US'),
        'value #1',
      );
    });

    test('ICU apostrophes quote literal spans', () {
      expect(_format("it''s", {}, 'en-US'), "it's");
      expect(_format("brace '{' open", {}, 'en-US'), 'brace { open');
      expect(_format("brace '}' close", {}, 'en-US'), 'brace } close');
      expect(_format("a '#' b", {}, 'en-US'), 'a # b');
      expect(_format("don''t '{x'} stop", {}, 'en-US'), "don't {x} stop");
      // An unterminated quoted span runs to the end of the message.
      expect(_format("plain 'quote", {}, 'en-US'), 'plain quote');
    });

    test('placeholder names are collected for validation', () {
      final message = CockpitIcuMessage.parse(
        '{name} and {count, plural, other{# of {total}}}',
      );
      expect(message.placeholders, {'name', 'count', 'total'});
    });

    test('malformed messages fail with paths', () {
      String? problemOf(Object error) =>
          error is FormatException ? error.message : null;

      expect(
        () => CockpitIcuMessage.parse('{count, plural, one{#}}'),
        throwsA(
          isA<FormatException>().having(
            problemOf,
            'message',
            contains('must define an "other" branch'),
          ),
        ),
      );
      expect(
        () => CockpitIcuMessage.parse('{who, select, a{b}}'),
        throwsA(
          isA<FormatException>().having(
            problemOf,
            'message',
            contains('must define an "other" branch'),
          ),
        ),
      );
      expect(
        () => CockpitIcuMessage.parse('{a'),
        throwsA(
          isA<FormatException>().having(
            problemOf,
            'message',
            anyOf(contains('Expected'), contains('Unterminated')),
          ),
        ),
      );
      expect(
        () => CockpitIcuMessage.parse('{a, bogus, other{x}}'),
        throwsA(
          isA<FormatException>().having(
            problemOf,
            'message',
            contains('Unknown construct "bogus"'),
          ),
        ),
      );
      expect(
        () => CockpitIcuMessage.parse('{a, selectordinal, other{x}}'),
        throwsA(
          isA<FormatException>().having(
            problemOf,
            'message',
            contains('selectordinal'),
          ),
        ),
      );
      expect(
        () => CockpitIcuMessage.parse('{a, plural, =x{y} other{z}}'),
        throwsA(
          isA<FormatException>().having(
            problemOf,
            'message',
            contains('not an exact-number selector'),
          ),
        ),
      );
      expect(
        () => CockpitIcuMessage.parse('{a, plural, other{z} other{z}}'),
        throwsA(
          isA<FormatException>().having(
            problemOf,
            'message',
            contains('Duplicate branch "other"'),
          ),
        ),
      );
      expect(
        () => CockpitIcuMessage.parse('{a, plural, =1{x} =1{y} other{z}}'),
        throwsA(
          isA<FormatException>().having(
            problemOf,
            'message',
            contains('Duplicate exact selector'),
          ),
        ),
      );
      expect(
        () => CockpitIcuMessage.parse('{a, plural, stuff{x} other{y}}'),
        throwsA(
          isA<FormatException>().having(
            problemOf,
            'message',
            contains('not a plural category'),
          ),
        ),
      );
    });
  });

  group('localized text with parameters', () {
    const messages = <String, String>{
      'en-US': 'Hello {name}, {count, plural, =1{one item} other{# items}}',
      'zh-CN': '{name} 你好，{count, plural, other{# 项}}',
    };

    test('formats the template for the active locale', () {
      final text = CockpitLocalizedText(
        'greeting',
        values: messages,
        params: const {'name': 'Alice', 'count': 3},
      );
      expect(
        text.resolve(CockpitLocaleProfile('en-US')),
        'Hello Alice, 3 items',
      );
      expect(text.resolve(CockpitLocaleProfile('zh-CN')), 'Alice 你好，3 项');
    });

    test('without parameters the raw translation is returned verbatim', () {
      final literal = CockpitLocalizedText(
        'payload',
        values: const {'en-US': '{"a": 1}'},
      );
      expect(literal.resolve(CockpitLocaleProfile('en-US')), '{"a": 1}');
    });

    test('malformed ICU messages surface as localization failures', () {
      final broken = CockpitLocalizedText(
        'broken',
        values: const {'en-US': '{count, plural, one{#}}'},
        params: const {'count': 1},
      );
      expect(
        () => broken.resolve(CockpitLocaleProfile('en-US')),
        throwsA(
          isA<CockpitTestLocalizationException>().having(
            (error) => error.message,
            'message',
            allOf(contains('broken'), contains('other')),
          ),
        ),
      );
    });

    test('params are frozen against later mutation', () {
      final params = <String, Object?>{'name': 'Alice'};
      final text = CockpitLocalizedText(
        'k',
        values: const {'en-US': 'Hello {name}'},
        params: params,
      );
      params['name'] = 'Bob';
      expect(text.resolve(CockpitLocaleProfile('en-US')), contains('Alice'));
      expect(() => text.params['name'] = 'Bob', throwsUnsupportedError);
    });
  });

  group('ARB catalog', () {
    test('loads messages, skips metadata, and resolves per locale', () {
      final catalog = CockpitArbCatalog.fromArb({
        'en': {
          '@@locale': 'en',
          'settings.saved': 'Saved',
          'settings.items': '{count, plural, =1{1 item} other{# items}}',
          '@settings.items': {
            'placeholders': {
              'count': {'type': 'num'},
            },
          },
        },
        'zh': {
          '@@locale': 'zh',
          'settings.saved': '已保存',
          'settings.items': '{count, plural, other{# 项}}',
        },
      });
      expect(catalog.locales, ['en', 'zh']);
      expect(
        catalog.keys,
        containsAll(<String>['settings.saved', 'settings.items']),
      );
      expect(
        catalog.text('settings.saved').resolve(CockpitLocaleProfile('en')),
        'Saved',
      );
      expect(
        catalog
            .text('settings.items', params: {'count': 3})
            .resolve(CockpitLocaleProfile('zh')),
        '3 项',
      );
    });

    test('@@locale must match the declared mapping', () {
      expect(
        () => CockpitArbCatalog.fromArb({
          'en': {'@@locale': 'fr', 'k': 'v'},
        }),
        throwsArgumentError,
      );
      // Underscore ids from gen_l10n normalize to the same tag.
      expect(
        () => CockpitArbCatalog.fromArb({
          'en-US': {'@@locale': 'en_US', 'k': 'v'},
        }),
        returnsNormally,
      );
    });

    test('undeclared placeholders are rejected with the full list', () {
      expect(
        () => CockpitArbCatalog.fromArb({
          'en': {
            'a': '{name}',
            '@a': {
              'placeholders': {
                'wrong': {'type': 'String'},
              },
            },
          },
        }),
        throwsA(
          isA<ArgumentError>().having(
            (error) => '$error',
            'message',
            contains('placeholder "name"'),
          ),
        ),
      );
    });

    test('malformed ICU messages fail at construction', () {
      expect(
        () => CockpitArbCatalog.fromArb({
          'en': {'bad': '{n, plural, one{#}}'},
        }),
        throwsA(
          isA<ArgumentError>().having(
            (error) => '$error',
            'message',
            contains('en.bad'),
          ),
        ),
      );
    });

    test('duplicate locales, duplicate keys, and non-strings are rejected', () {
      expect(
        () => CockpitArbCatalog.fromArb({
          'en': {'k': 'v'},
          'EN': {'k': 'v'},
        }),
        throwsArgumentError,
      );
      expect(
        () => CockpitArbCatalog.fromArb({
          'en-US': {'k': 'v'},
          'en_US': {'k': 'v'},
        }),
        throwsArgumentError,
      );
      expect(
        () => CockpitArbCatalog.fromArb({
          'en': {'k': 3},
        }),
        throwsArgumentError,
      );
    });

    test('validateMatrix reports gaps and honors fallback chains', () {
      final catalog = CockpitArbCatalog.fromArb({
        'en': {'a': 'A', 'only-en': 'EN'},
        'zh': {'a': '甲'},
      });
      final complete = catalog.validateMatrix([CockpitLocaleProfile('en')]);
      expect(complete.isComplete, isTrue);

      final gapped = catalog.validateMatrix([
        CockpitLocaleProfile('en'),
        CockpitLocaleProfile('zh-Hans-CN'),
      ]);
      expect(gapped.isComplete, isFalse);
      expect(gapped.gaps.single.key, 'only-en');
      expect(gapped.gaps.single.localeTag, 'zh-Hans-CN');
      // 'zh' templates cover 'zh-Hans-CN' through the fallback chain, so 'a'
      // is not a gap.
      expect('$gapped', contains('only-en'));
    });
  });

  group('JSON catalog', () {
    test('resolves nested dotted keys across locales', () {
      final catalog = CockpitJsonCatalog.fromJson({
        'en': {
          'settings': {'saved': 'Saved', 'title': 'Settings'},
        },
        'zh': {
          'settings': {'saved': '已保存'},
        },
      });
      expect(
        catalog.keys,
        containsAll(<String>['settings.saved', 'settings.title']),
      );
      expect(
        catalog.text('settings.saved').resolve(CockpitLocaleProfile('en')),
        'Saved',
      );
      expect(
        catalog.text('settings.title').resolve(CockpitLocaleProfile('en-GB')),
        'Settings',
      );
    });

    test('non-string leaves fail at construction', () {
      expect(
        () => CockpitJsonCatalog.fromJson({
          'en': {
            'a': {'b': 3},
          },
        }),
        throwsA(
          isA<ArgumentError>().having(
            (error) => '$error',
            'message',
            contains('"a.b"'),
          ),
        ),
      );
    });

    test('validateMatrix reports missing dotted keys', () {
      final catalog = CockpitJsonCatalog.fromJson({
        'en': {
          'settings': {'saved': 'Saved'},
        },
        'zh': {},
      });
      final coverage = catalog.validateMatrix([
        CockpitLocaleProfile('en'),
        CockpitLocaleProfile('zh'),
      ]);
      expect(coverage.gaps.single.key, 'settings.saved');
      expect(coverage.gaps.single.localeTag, 'zh');
    });
  });

  group('VM catalog loaders', () {
    test('loads ARB and JSON files from disk', () {
      final arb = loadCockpitArbCatalog({
        'en': 'test/fixtures/l10n/app_en.arb',
        'zh': 'test/fixtures/l10n/app_zh.arb',
      });
      expect(
        arb.text('app.title').resolve(CockpitLocaleProfile('zh-CN')),
        '设置',
      );
      expect(
        arb
            .text('app.itemCount', params: {'count': 5})
            .resolve(CockpitLocaleProfile('en-US')),
        '5 items',
      );

      final json = loadCockpitJsonCatalog({
        'en': 'test/fixtures/l10n/strings_en.json',
        'zh': 'test/fixtures/l10n/strings_zh.json',
      });
      expect(
        json.text('home.greeting').resolve(CockpitLocaleProfile('en-US')),
        'Hello',
      );
    });

    test('missing and invalid files fail with the path', () {
      expect(
        () => loadCockpitArbCatalog({'en': 'test/fixtures/l10n/missing.arb'}),
        throwsA(
          isA<ArgumentError>().having(
            (error) => '$error',
            'message',
            contains('missing.arb'),
          ),
        ),
      );
    });
  });
}
