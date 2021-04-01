library runtime_2;

import 'dart:io';

import 'src/compiler.dart';
import 'src/mirror_context.dart';

export 'src/analyzer.dart';
export 'src/context.dart';
export 'src/build.dart';
export 'src/compiler.dart';
export 'src/file_system.dart';
export 'src/generator.dart';
export 'src/build_context.dart';
export 'src/build_manager.dart';
export 'src/mirror_context.dart';
export 'src/exceptions.dart';
export 'src/mirror_coerce.dart';
export 'src/project_agent.dart';

/// Compiler for the runtime package itself.
///
/// Removes dart:mirror from a replica of this package, and adds
/// a generated runtime to the replica's pubspec.
class RuntimePackageCompiler extends Compiler {
  @override
  Map<String, dynamic> compile(MirrorContext context) => {};

  @override
  void deflectPackage(Directory destinationDirectory) {
    final libraryFile = File.fromUri(destinationDirectory.uri.resolve("lib/").resolve("runtime_2.dart"));
    libraryFile.writeAsStringSync("""

library runtime_2;

export 'src/analyzer.dart';
export 'src/context.dart';
export 'src/exceptions.dart';
export 'src/project_agent.dart';

""");

    final contextFile = File.fromUri(destinationDirectory.uri.resolve("lib/").resolve("src/").resolve("context.dart"));
    final contextFileContents = contextFile.readAsStringSync().replaceFirst(
        "import 'package:runtime_2/src/mirror_context.dart' as context;",
        "import 'package:generated_runtime/generated_runtime.dart' as context;");
    contextFile.writeAsStringSync(contextFileContents);

    final pubspecFile = File.fromUri(destinationDirectory.uri.resolve("pubspec.yaml"));
    final pubspecContents = pubspecFile
        .readAsStringSync()
        .replaceFirst("\ndependencies:", "\ndependencies:\n  generated_runtime:\n    path: ../../generated_runtime/");
    pubspecFile.writeAsStringSync(pubspecContents);
  }
}
