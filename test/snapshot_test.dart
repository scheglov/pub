// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

main() {
  group("creates a snapshot", () {
    test("for an immediate dependency", () async {
      await servePackages((builder) {
        builder.serve("foo", "1.2.3", contents: [
          d.dir("bin", [
            d.file("hello.dart", "void main() => print('hello!');"),
            d.file("goodbye.dart", "void main() => print('goodbye!');"),
            d.file("shell.sh", "echo shell"),
            d.dir(
                "subdir", [d.file("sub.dart", "void main() => print('sub!');")])
          ])
        ]);
      });

      await d.appDir({"foo": "1.2.3"}).create();

      await pubGet(
          output: allOf([
        contains("Precompiled foo:hello."),
        contains("Precompiled foo:goodbye.")
      ]));

      await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
        d.file('sdk-version', '0.1.2+3\n'),
        d.dir('foo', [
          d.file('hello.dart.snapshot', contains('hello!')),
          d.file('goodbye.dart.snapshot', contains('goodbye!')),
          d.nothing('shell.sh.snapshot'),
          d.nothing('subdir')
        ])
      ]).validate();

      var process = await pubRun(args: ['foo:hello']);
      expect(process.stdout, emits("hello!"));
      await process.shouldExit();

      process = await pubRun(args: ['foo:goodbye']);
      expect(process.stdout, emits("goodbye!"));
      await process.shouldExit();
    });

    test("for an immediate dependency that's also transitive", () async {
      await servePackages((builder) {
        builder.serve("foo", "1.2.3", contents: [
          d.dir("bin", [
            d.file("hello.dart", "void main() => print('hello!');"),
            d.file("goodbye.dart", "void main() => print('goodbye!');"),
            d.file("shell.sh", "echo shell"),
            d.dir(
                "subdir", [d.file("sub.dart", "void main() => print('sub!');")])
          ])
        ]);
        builder.serve("bar", "1.2.3", deps: {"foo": "1.2.3"});
      });

      await d.appDir({"foo": "1.2.3"}).create();

      await pubGet(
          output: allOf([
        contains("Precompiled foo:hello."),
        contains("Precompiled foo:goodbye.")
      ]));

      await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
        d.file('sdk-version', '0.1.2+3\n'),
        d.dir('foo', [
          d.file('hello.dart.snapshot', contains('hello!')),
          d.file('goodbye.dart.snapshot', contains('goodbye!')),
          d.nothing('shell.sh.snapshot'),
          d.nothing('subdir')
        ])
      ]).validate();

      var process = await pubRun(args: ['foo:hello']);
      expect(process.stdout, emits("hello!"));
      await process.shouldExit();

      process = await pubRun(args: ['foo:goodbye']);
      expect(process.stdout, emits("goodbye!"));
      await process.shouldExit();
    });

    test("only for Dart 1 in Dart 1 mode", () async {
      await servePackages((builder) {
        builder.serve("foo", "1.2.3", contents: [
          d.dir(
              "bin", [d.file("hello.dart", "void main() => print('hello!');")])
        ]);
      });

      await d.appDir({"foo": "1.2.3"}).create();

      await pubGet(output: allOf([contains("Precompiled foo:hello.")]));

      await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'),
          [d.nothing('hello.dart.snapshot.dart2')]).validate();
    });

    test("for Dart 1 and 2 in Dart 2 mode", () async {
      await servePackages((builder) {
        builder.serve("foo", "1.2.3", contents: [
          d.dir(
              "bin", [d.file("hello.dart", "void main() => print('hello!');")])
        ]);
      });

      await d.appDir({"foo": "1.2.3"}).create();

      await pubGet(
          output: allOf([contains("Precompiled foo:hello.")]), dart2: true);

      await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'), [
        d.file('hello.dart.snapshot', contains('hello!')),
        d.file('hello.dart.snapshot.dart2', contains('hello!'))
      ]).validate();

      var process = await pubRun(args: ['foo:hello']);
      expect(process.stdout, emits("hello!"));
      await process.shouldExit();

      process = await pubRun(args: ['foo:hello'], dart2: true);
      expect(process.stdout, emits("hello!"));
      await process.shouldExit();
    });

    group("again if", () {
      test("its package is updated", () async {
        await servePackages((builder) {
          builder.serve("foo", "1.2.3", contents: [
            d.dir("bin",
                [d.file("hello.dart", "void main() => print('hello!');")])
          ]);
        });

        await d.appDir({"foo": "any"}).create();

        await pubGet(output: contains("Precompiled foo:hello."));

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'),
            [d.file('hello.dart.snapshot', contains('hello!'))]).validate();

        await globalPackageServer.add((builder) {
          builder.serve("foo", "1.2.4", contents: [
            d.dir("bin",
                [d.file("hello.dart", "void main() => print('hello 2!');")])
          ]);
        });

        await pubUpgrade(output: contains("Precompiled foo:hello."));

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'),
            [d.file('hello.dart.snapshot', contains('hello 2!'))]).validate();

        var process = await pubRun(args: ['foo:hello']);
        expect(process.stdout, emits("hello 2!"));
        await process.shouldExit();
      });

      test("a dependency of its package is updated", () async {
        await servePackages((builder) {
          builder.serve("foo", "1.2.3", pubspec: {
            "dependencies": {"bar": "any"}
          }, contents: [
            d.dir("bin", [
              d.file("hello.dart", """
            import 'package:bar/bar.dart';

            void main() => print(message);
          """)
            ])
          ]);
          builder.serve("bar", "1.2.3", contents: [
            d.dir("lib", [d.file("bar.dart", "final message = 'hello!';")])
          ]);
        });

        await d.appDir({"foo": "any"}).create();

        await pubGet(output: contains("Precompiled foo:hello."));

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'),
            [d.file('hello.dart.snapshot', contains('hello!'))]).validate();

        await globalPackageServer.add((builder) {
          builder.serve("bar", "1.2.4", contents: [
            d.dir("lib", [d.file("bar.dart", "final message = 'hello 2!';")]),
          ]);
        });

        await pubUpgrade(output: contains("Precompiled foo:hello."));

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'),
            [d.file('hello.dart.snapshot', contains('hello 2!'))]).validate();

        var process = await pubRun(args: ['foo:hello']);
        expect(process.stdout, emits("hello 2!"));
        await process.shouldExit();
      });

      test("a git dependency of its package is updated", () async {
        await ensureGit();

        await d.git('foo.git', [
          d.pubspec({"name": "foo", "version": "0.0.1"}),
          d.dir(
              "bin", [d.file("hello.dart", "void main() => print('Hello!');")])
        ]).create();

        await d.appDir({
          "foo": {"git": "../foo.git"}
        }).create();

        await pubGet(output: contains("Precompiled foo:hello."));

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'),
            [d.file('hello.dart.snapshot', contains('Hello!'))]).validate();

        await d.git('foo.git', [
          d.dir("bin",
              [d.file("hello.dart", "void main() => print('Goodbye!');")])
        ]).commit();

        await pubUpgrade(output: contains("Precompiled foo:hello."));

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'),
            [d.file('hello.dart.snapshot', contains('Goodbye!'))]).validate();

        var process = await pubRun(args: ['foo:hello']);
        expect(process.stdout, emits("Goodbye!"));
        await process.shouldExit();
      });

      test("the SDK is out of date", () async {
        await servePackages((builder) {
          builder.serve("foo", "5.6.7", contents: [
            d.dir("bin",
                [d.file("hello.dart", "void main() => print('hello!');")])
          ]);
        });

        await d.appDir({"foo": "5.6.7"}).create();

        await pubGet(output: contains("Precompiled foo:hello."));

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
          d.dir('foo', [d.outOfDateSnapshot('hello.dart.snapshot')])
        ]).create();

        var process = await pubRun(args: ['foo:hello']);

        // In the real world this would just print "hello!", but since we collect
        // all output we see the precompilation messages as well.
        expect(process.stdout, emits("Precompiling executables..."));
        expect(process.stdout, emitsThrough("hello!"));
        await process.shouldExit();

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
          d.file('sdk-version', '0.1.2+3\n'),
          d.dir('foo', [d.file('hello.dart.snapshot', contains('hello!'))])
        ]).validate();
      });

      test("the SDK is out of date", () async {
        await servePackages((builder) {
          builder.serve("foo", "5.6.7", contents: [
            d.dir("bin",
                [d.file("hello.dart", "void main() => print('hello!');")])
          ]);
        });

        await d.appDir({"foo": "5.6.7"}).create();

        await pubGet(output: contains("Precompiled foo:hello."));

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
          d.dir('foo', [d.outOfDateSnapshot('hello.dart.snapshot')])
        ]).create();

        var process = await pubRun(args: ['foo:hello']);

        // In the real world this would just print "hello!", but since we
        // collect all output we see the precompilation messages as well.
        expect(process.stdout, emits("Precompiling executables..."));
        expect(process.stdout, emitsThrough("hello!"));
        await process.shouldExit();

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
          d.file('sdk-version', '0.1.2+3\n'),
          d.dir('foo', [d.file('hello.dart.snapshot', contains('hello!'))])
        ]).validate();
      });

      group("Dart 2 is newly in use for", () {
        test("pub get", () async {
          await servePackages((builder) {
            builder.serve("foo", "5.6.7", contents: [
              d.dir("bin",
                  [d.file("hello.dart", "void main() => print('hello!');")])
            ]);
          });

          await d.appDir({"foo": "5.6.7"}).create();

          await pubGet(output: contains("Precompiled foo:hello."));
          await pubGet(output: contains("Precompiled foo:hello."), dart2: true);

          await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'), [
            d.file('hello.dart.snapshot', contains('hello!')),
            d.file('hello.dart.snapshot.dart2', contains('hello!'))
          ]).validate();
        });

        test("pub run", () async {
          await servePackages((builder) {
            builder.serve("foo", "5.6.7", contents: [
              d.dir("bin",
                  [d.file("hello.dart", "void main() => print('hello!');")])
            ]);
          });

          await d.appDir({"foo": "5.6.7"}).create();

          await pubGet(output: contains("Precompiled foo:hello."));

          var process = await pubRun(args: ['foo:hello'], dart2: true);

          // In the real world this would just print "hello!", but since we
          // collect all output we see the precompilation messages as well.
          expect(process.stdout, emits("Precompiling executables..."));
          expect(process.stdout, emitsThrough("hello!"));
          await process.shouldExit();

          await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'), [
            d.file('hello.dart.snapshot', contains('hello!')),
            d.file('hello.dart.snapshot.dart2', contains('hello!'))
          ]).validate();
        });
      });
    });
  });
}
