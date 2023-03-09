import 'dart:io';

import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/protocol/protocol_generated.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

import 'cli_test.dart';
import 'create_project.dart';
import 'equals_ignoring_ansi.dart';
import 'matchers.dart';
import 'mock_fs.dart';
import 'run_plugin.dart';

final lintRuleWithFilesToAnalayze = createPluginSource([
  TestLintRule(
    code: 'hello_world',
    message: 'Hello world',
    ruleMembers: '''
@override
List<String> get filesToAnalyze => const ['test/*_test.dart'];
''',
  )
]);

void main() {
  test('List warnings for all files combined', () async {
    final plugin = createPlugin(
      name: 'test_lint',
      main: lintRuleWithFilesToAnalayze,
    );

    final app = createLintUsage(
      source: {
        'lib/main.dart': '''
void fn() {}
''',
        'test/another.dart': 'void fn() {}\n',
        'test/another_test.dart': 'void fn() {}\n',
      },
      plugins: {'test_lint': plugin.uri},
      name: 'test_app',
    );

    final rawLints = await runServerInCliModeForApp(app);
    final lints = rawLints.where((e) => e.errors.isNotEmpty).toList();

    expect(
      lints.map((e) => e.file),
      [join(app.path, 'test', 'another_test.dart')],
    );

    expect(
      lints.single.errors.single,
      isA<AnalysisError>()
          .having((e) => e.code, 'code', 'hello_world')
          .having(
            (e) => e.location,
            'location',
            Location(
              join(app.path, 'test', 'another_test.dart'),
              5,
              2,
              1,
              6,
              endLine: 1,
              endColumn: 8,
            ),
          )
          .having((e) => e.message, 'message', 'Hello world'),
    );
  });

  test('Handles files getting deleted', () async {
    // Regression test for https://github.com/invertase/dart_custom_lint/issues/105
    final plugin = createPlugin(name: 'test_lint', main: helloWordPluginSource);

    final app = createLintUsage(
      source: {
        'lib/main.dart': '''
void fn() {}

void fn2() {}
''',
        'lib/another.dart': 'void fn() {}\n',
      },
      plugins: {'test_lint': plugin.uri},
      name: 'test_app',
    );

    final runner = startRunnerForApp(app, includeBuiltInLints: false);
    final lints = await runner.getLints(reload: false);

    expect(
      lints.map((e) => e.file),
      [
        join(app.path, 'lib', 'another.dart'),
        join(app.path, 'lib', 'main.dart'),
      ],
    );
    expect(lints[0].errors, hasLength(1));
    expect(lints[1].errors, hasLength(2));

    final another = File(join(app.path, 'lib', 'another.dart'));
    another.deleteSync();
    await runner.channel.sendRequest(
      AnalysisUpdateContentParams({
        another.path: RemoveContentOverlay(),
      }),
    );

    final lints2 = await runner.getLints(reload: true);

    expect(
      lints2.map((e) => e.file),
      [join(app.path, 'lib', 'main.dart')],
    );
    expect(lints2[0].errors, hasLength(2));

    await runner.close();
  });

  test('List warnings for all files combined', () async {
    final plugin = createPlugin(name: 'test_lint', main: helloWordPluginSource);

    final app = createLintUsage(
      source: {
        'lib/main.dart': '''
void fn() {}

void fn2() {}
''',
        'lib/another.dart': 'void fn() {}\n',
      },
      plugins: {'test_lint': plugin.uri},
      name: 'test_app',
    );

    final lints = await runServerInCliModeForApp(app);

    expect(
      lints.map((e) => e.file),
      [
        join(app.path, 'lib', 'another.dart'),
        join(app.path, 'lib', 'main.dart'),
      ],
    );

    expect(
      lints.first.errors,
      [
        isA<AnalysisError>()
            .having((e) => e.code, 'code', 'hello_world')
            .having(
              (e) => e.location,
              'location',
              Location(
                join(app.path, 'lib', 'another.dart'),
                5,
                2,
                1,
                6,
                endLine: 1,
                endColumn: 8,
              ),
            )
            .having((e) => e.message, 'message', 'Hello world'),
      ],
    );
    expect(
      lints.last.errors,
      [
        isA<AnalysisError>()
            .having((e) => e.code, 'code', 'hello_world')
            .having(
              (e) => e.location,
              'location',
              Location(
                join(app.path, 'lib', 'main.dart'),
                5,
                2,
                1,
                6,
                endLine: 1,
                endColumn: 8,
              ),
            )
            .having((e) => e.message, 'message', 'Hello world'),
        isA<AnalysisError>()
            .having((e) => e.code, 'code', 'hello_world')
            .having(
              (e) => e.location,
              'location',
              Location(
                join(app.path, 'lib', 'main.dart'),
                19,
                3,
                3,
                6,
                endLine: 3,
                endColumn: 9,
              ),
            )
            .having((e) => e.message, 'message', 'Hello world'),
      ],
    );
  });

  test('supports running multiple plugins at once', () async {
    final plugin = createPlugin(name: 'test_lint', main: helloWordPluginSource);
    final plugin2 = createPlugin(name: 'test_lint2', main: oyPluginSource);

    final app = createLintUsage(
      source: {
        'lib/main.dart': '''


void fn() {}''',
        'lib/another.dart': '''


void fn2() {}''',
      },
      plugins: {'test_lint': plugin.uri, 'test_lint2': plugin2.uri},
      name: 'test_app',
    );

    final lints = await runServerInCliModeForApp(app);

    expect(
      lints.map((e) => e.file),
      [
        join(app.path, 'lib', 'another.dart'),
        join(app.path, 'lib', 'main.dart'),
      ],
    );

    expect(
      lints.first.errors.map((e) => e.code),
      unorderedEquals(<Object?>['hello_world', 'oy']),
    );
    expect(
      lints.last.errors.map((e) => e.code),
      unorderedEquals(<Object?>['hello_world', 'oy']),
    );
  });

  test('supports plugins without .package_config.json', () async {
    final plugin = createPlugin(
      name: 'test_lint',
      main: helloWordPluginSource,
      omitPackageConfig: true,
    );
    final plugin2 = createPlugin(
      name: 'test_lint2',
      main: oyPluginSource,
      omitPackageConfig: true,
    );

    final app = createLintUsage(
      source: {
        'lib/main.dart': '''


void fn() {}''',
        'lib/another.dart': '''


void fn2() {}''',
      },
      plugins: {'test_lint': plugin.uri, 'test_lint2': plugin2.uri},
      name: 'test_app',
    );

    final lints = await runServerInCliModeForApp(app);

    expect(
      lints.map((e) => e.file),
      [
        join(app.path, 'lib', 'another.dart'),
        join(app.path, 'lib', 'main.dart'),
      ],
    );

    expect(
      lints.first.errors.map((e) => e.code),
      unorderedEquals(<Object?>['hello_world', 'oy']),
    );
    expect(
      lints.last.errors.map((e) => e.code),
      unorderedEquals(<Object?>['hello_world', 'oy']),
    );
  });

  test('redirect prints and errors to log files', () async {
    final plugin = createPlugin(
      name: 'test_lint',
      main: createPluginSource([
        TestLintRule(
          code: 'hello_world',
          message: 'Hello world',
          onVariable: '''
if (node.name.lexeme == "fail") {
  print('Hello world');
  throw StateError('fail');
}''',
        ),
      ]),
    );
    final plugin2 = createPlugin(name: 'test_lint2', main: oyPluginSource);

    final app = createLintUsage(
      source: {
        'lib/main.dart': 'void fn() {}\n',
        'lib/another.dart': 'void fail() {}\n',
      },
      plugins: {'test_lint': plugin.uri, 'test_lint2': plugin2.uri},
      name: 'test_app',
    );

    await runWithIOOverride((out, err) async {
      final runner = startRunnerForApp(
        app,
        // Ignoring errors as we are handling them later
        ignoreErrors: true,
      );

      // Plugin errors will be emitted as notifications, not as part of the response
      expect(runner.channel.responseErrors, emitsDone);

      // The error in our plugin will be reported as PluginErrorParams
      expect(
        runner.channel.pluginErrors.toList(),
        completion([
          predicate<PluginErrorParams>((value) {
            expect(
              value.message,
              'Plugin hello_world threw while analyzing ${app.path}/lib/another.dart:\n'
              'Bad state: fail',
            );
            return true;
          }),
        ]),
      );

      final lints = await runner.getLints(reload: false);

      expect(
        lints.map((e) => e.file),
        [
          join(app.path, 'lib', 'another.dart'),
          join(app.path, 'lib', 'main.dart'),
        ],
      );

      expect(
        lints.first.errors.map((e) => e.code),
        unorderedEquals(<Object?>['custom_lint_get_lint_fail', 'oy']),
      );
      expect(
        lints.last.errors.map((e) => e.code),
        unorderedEquals(<Object?>['hello_world', 'oy']),
      );
      // uncomment when the golden needs update
      // saveLogGoldens(
      //   File('test/goldens/server_test/redirect_logs.golden'),
      //   app.log.readAsStringSync(),
      //   paths: {plugin.uri: 'plugin', app.uri: 'app'},
      // );
      // await runner.close();
      // return;

      expect(
        app.log,
        matchesLogGolden(
          'test/goldens/server_test/redirect_logs.golden',
          paths: {plugin.uri: 'plugin', app.uri: 'app'},
        ),
      );

      // Closing so that previous error matchers relying on stream
      // closing can complete
      await runner.close();
    });
  });

  group('hot-reload', skip: true, () {
    test('handles the source change of one plugin and restart it', () async {
      final plugin = createPlugin(
        name: 'test_lint',
        main: helloWordPluginSource,
      );
      final pluginMain = File(join(plugin.path, 'lib', 'test_lint'));

      final plugin2 = createPlugin(name: 'test_lint2', main: oyPluginSource);

      final app = createLintUsage(
        source: {'lib/main.dart': 'void fn() {}\n'},
        plugins: {'test_lint': plugin.uri, 'test_lint2': plugin2.uri},
        name: 'test_app',
      );

      final runner = startRunnerForApp(app);

      await expectLater(
        runner.channel.lints,
        // Using emitsThrough as depending on how fast lints are emitted,
        // the 2 lints can be received accross two events instead of one.
        emitsThrough(
          isA<AnalysisErrorsParams>()
              .having(
                (e) => e.file,
                'file',
                join(app.path, 'lib', 'main.dart'),
              )
              .having(
                (e) => e.errors.map((e) => e.code),
                'errors',
                unorderedEquals(<Object?>['hello_world', 'oy']),
              ),
        ),
      );

      pluginMain.writeAsStringSync(
        createPluginSource([
          TestLintRule(
            code: 'hello_reload',
            message: 'Hello reload',
          ),
        ]),
      );

      await expectLater(
        runner.channel.lints,
        emitsInOrder(<Object?>[
          predicate<AnalysisErrorsParams>((value) {
            expect(value.file, join(app.path, 'lib', 'main.dart'));
            // Clears lints previously emitted by the reloaded plugin
            expect(value.errors.single.code, 'oy');
            return true;
          }),
          predicate<AnalysisErrorsParams>((value) {
            expect(value.file, join(app.path, 'lib', 'main.dart'));
            expect(
              value.errors.map((e) => e.code),
              unorderedEquals(<Object?>['hello_reload', 'oy']),
            );
            return true;
          }),
        ]),
      );

      expect(runner.channel.lints, emitsDone);

      // Closing so that previous error matchers relying on stream
      // closing can complete
      await runner.close();

      expect(plugin.log.existsSync(), false);
      expect(plugin2.log.existsSync(), false);
    });

    test('supports reloading a working plugin into one that fails', () async {
      final plugin = createPlugin(
        name: 'test_lint',
        main: helloWordPluginSource,
      );
      final pluginMain = File(join(plugin.path, 'lib', 'test_lint'));
      final plugin2 = createPlugin(name: 'test_lint2', main: oyPluginSource);

      final app = createLintUsage(
        source: {'lib/main.dart': 'void fn() {}\n'},
        plugins: {'test_lint': plugin.uri, 'test_lint2': plugin2.uri},
        name: 'test_app',
      );

      await runWithIOOverride((out, err) async {
        final runner = startRunnerForApp(app, ignoreErrors: true);

        await expectLater(
          runner.channel.lints,
          // Using emitsThrough as depending on how fast lints are emitted,
          // the 2 lints can be received accross two events instead of one.
          emitsThrough(
            isA<AnalysisErrorsParams>()
                .having(
                  (e) => e.file,
                  'file',
                  join(app.path, 'lib', 'main.dart'),
                )
                .having(
                  (e) => e.errors.map((e) => e.code),
                  'errors',
                  unorderedEquals(<Object?>['hello_world', 'oy']),
                ),
          ),
        );

        expect(plugin.log.existsSync(), false);
        expect(plugin2.log.existsSync(), false);

        pluginMain.writeAsStringSync('''
invalid;
''');

        // Plugin errors will be emitted as notifications, not as part of the response
        expect(runner.channel.responseErrors, emitsDone);

        // The error in our plugin will be reported as PluginErrorParams
        // We don't immediately await it, as we could otherwise miss the lint update

        final awaitError = expectLater(
          runner.channel.pluginErrors,
          emits(
            isA<PluginErrorParams>().having(
              (e) => e.message,
              'message',
              equalsIgnoringAnsi('''
IsolateSpawnException: Unable to spawn isolate: ${plugin.path}/bin/custom_lint.dart:1:1: Error: Variables must be declared using the keywords 'const', 'final', 'var' or a type name.
Try adding the name of the type of the variable or the keyword 'var'.
invalid;
^^^^^^^'''),
            ),
          ),
        );
        await expectLater(
          runner.channel.lints,
          emits(
            predicate<AnalysisErrorsParams>((value) {
              expect(value.file, join(app.path, 'lib', 'main.dart'));
              // Clears lints previously emitted by the reloaded plugin
              expect(value.errors.single.code, 'oy');
              return true;
            }),
          ),
        );

        await awaitError;

        expect(runner.channel.pluginErrors, emitsDone);
        expect(runner.channel.lints, emitsDone);

        // Closing so that previous error matchers relying on stream
        // closing can complete
        await runner.close();

        expect(plugin.log.existsSync(), false);
        expect(plugin2.log.existsSync(), false);
      });
    });
  });
}
