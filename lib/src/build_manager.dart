import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:isolate_executor_2/isolate_executor_2.dart';

import 'analyzer.dart';
import 'build.dart';
import 'build_context.dart';

class BuildExecutable extends Executable<Null> {
  BuildExecutable(Map<String, dynamic> message) : super(message) {
    context = BuildContext.fromMap(message);
  }

  BuildContext context;

  @override
  Future<Null> execute() async {
    final build = Build(context);
    await build.execute();
  }
}

class BuildManager {
  /// Creates a new build manager to compile a non-mirrored build.
  BuildManager(this.context);

  final BuildContext context;

  Uri get sourceDirectoryUri => context.sourceApplicationDirectory.uri;

  Future build() async {
    if (!context.buildDirectory.existsSync()) {
      context.buildDirectory.createSync();
    }

    // Here is where we need to provide a temporary copy of the script file with the main function stripped;
    // this is because when the RuntimeGenerator loads, it needs Mirror access to any declarations in this file
    var scriptSource = context.source;
    final strippedScriptFile = File.fromUri(context.targetScriptFileUri)..writeAsStringSync(scriptSource);

    final analyzer = CodeAnalyzer(strippedScriptFile.absolute.uri);
    final analyzerContext = analyzer.contexts.contextFor(analyzer.path);
    final mainFunctions = analyzerContext.currentSession
        .getParsedUnit(analyzer.path)
        .unit
        .declarations
        .whereType<FunctionDeclaration>()
        .where((f) => f.name.name == "main")
        .toList();

    mainFunctions.reversed.forEach((f) {
      scriptSource = scriptSource.replaceRange(f.offset, f.end, "");
    });

    strippedScriptFile.writeAsStringSync(scriptSource);

    return IsolateExecutor.run(
      BuildExecutable(context.safeMap),
      packageConfigURI: sourceDirectoryUri.resolve(".packages"),
      imports: ["package:runtime_2/runtime_2.dart", context.targetScriptFileUri.toString()],
      logHandler: (s) => print(s),
    );
  }

  Future clean() async {
    if (context.buildDirectory.existsSync()) {
      context.buildDirectory.deleteSync(recursive: true);
    }
  }
}
