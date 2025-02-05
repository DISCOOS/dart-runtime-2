import 'dart:io';
import 'dart:mirrors';

import 'package:path/path.dart' as path;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:runtime_2/src/analyzer.dart';
import 'package:runtime_2/src/context.dart';
import 'package:runtime_2/src/file_system.dart';
import 'package:runtime_2/src/mirror_context.dart';
import 'package:yaml/yaml.dart';

/// Configuration and context values used during [Build.execute].
class BuildContext {
  BuildContext(
    this.rootLibraryFileUri,
    this.buildDirectoryUri,
    this.executableUri,
    this.source, {
    bool offline,
    bool forTests,
  })  : this.offline = offline ?? true,
        this.forTests = forTests ?? false {
    analyzer = CodeAnalyzer(sourceApplicationDirectory.uri);
  }

  factory BuildContext.fromMap(Map map) {
    return BuildContext(
      Uri.parse(map['rootLibraryFileUri']),
      Uri.parse(map['buildDirectoryUri']),
      Uri.parse(map['executableUri']),
      map['source'],
      offline: map['offline'],
      forTests: map['forTests'],
    );
  }

  Map<String, dynamic> get safeMap => {
        'rootLibraryFileUri': sourceLibraryFile.uri.toString(),
        'buildDirectoryUri': buildDirectoryUri.toString(),
        'source': source,
        'executableUri': executableUri.toString(),
        'offline': offline,
        'forTests': forTests
      };

  CodeAnalyzer analyzer;

  /// A [Uri] to the library file of the application to be compiled.
  final Uri rootLibraryFileUri;

  /// A [Uri] to the executable build product file.
  final Uri executableUri;

  /// A [Uri] to directory where build artifacts are stored during the build process.
  final Uri buildDirectoryUri;

  /// The source script for the executable.
  final String source;

  /// Whether use cached packages rather than downloading from the network.
  final bool offline;

  /// Whether dev dependencies of the application package are included in the dependencies of the compiled executable.
  final bool forTests;

  /// The [RuntimeContext] available during the build process.
  MirrorContext get context => RuntimeContext.current as MirrorContext;

  Uri get targetScriptFileUri => forTests
      ? getDirectory(buildDirectoryUri.resolve("test/")).uri.resolve("main_test.dart")
      : buildDirectoryUri.resolve("main.dart");

  Pubspec get sourceApplicationPubspec =>
      Pubspec.parse(File.fromUri(sourceApplicationDirectory.uri.resolve("pubspec.yaml")).readAsStringSync());

  Map<dynamic, dynamic> get sourceApplicationPubspecMap =>
      loadYaml(File.fromUri(sourceApplicationDirectory.uri.resolve("pubspec.yaml")).readAsStringSync());

  /// The directory of the application being compiled.
  Directory get sourceApplicationDirectory => getDirectory(rootLibraryFileUri.resolve("../"));

  /// The library file of the application being compiled.
  File get sourceLibraryFile => getFile(rootLibraryFileUri);

  /// The directory where build artifacts are stored.
  Directory get buildDirectory => getDirectory(buildDirectoryUri);

  /// The generated runtime directory
  Directory get buildRuntimeDirectory => getDirectory(buildDirectoryUri.resolve("generated_runtime/"));

  /// Directory for compiled packages
  Directory get buildPackagesDirectory => getDirectory(buildDirectoryUri.resolve("packages/"));

  /// Directory for compiled application
  Directory get buildApplicationDirectory =>
      getDirectory(buildPackagesDirectory.uri.resolve("${sourceApplicationPubspec.name}/"));

  /// Gets dependency package location relative to [sourceApplicationDirectory].
  Map<String, Uri> get resolvedPackages {
    return getResolvedPackageUris(sourceApplicationDirectory.uri.resolve(".packages"),
        relativeTo: sourceApplicationDirectory.uri);
  }

  /// Returns a [Directory] at [uri], creates it recursively if it doesn't exist.
  Directory getDirectory(Uri uri) {
    final dir = Directory.fromUri(uri);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Returns a [File] at [uri], creates all parent directories recursively if necessary.
  File getFile(Uri uri) {
    final file = File.fromUri(uri);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    return file;
  }

  Uri resolveUri(Uri uri) {
    var outputUri = uri;
    if (outputUri?.scheme == "package") {
      final segments = outputUri.pathSegments;
      outputUri = resolvedPackages[segments.first].resolve("lib/");
      for (var i = 1; i < segments.length; i++) {
        if (i < segments.length - 1) {
          outputUri = outputUri.resolve("${segments[i]}/");
        } else {
          outputUri = outputUri.resolve(segments[i]);
        }
      }
    } else if (outputUri != null && !outputUri.isAbsolute) {
      throw ArgumentError("'uri' must be absolute or a package URI");
    }

    return outputUri;
  }

  List<String> getImportDirectives({
    Uri uri,
    String source,
    Directory sourceDir,
    bool alsoImportOriginalFile = false,
  }) {
    if (uri != null && source != null) {
      throw ArgumentError("either uri or source must be non-null, but not both");
    }

    if (uri == null && source == null) {
      throw ArgumentError("either uri or source must be non-null, but not both");
    }

    if (alsoImportOriginalFile == true && uri == null) {
      throw ArgumentError("flag 'alsoImportOriginalFile' may only be set if 'uri' is also set");
    }

    var fileUri = resolveUri(uri);
    final text = source ?? File.fromUri(fileUri).readAsStringSync();
    final importRegex = RegExp("import [\\'\\\"]([^\\'\\\"]*)[\\'\\\"];");

    final imports = importRegex.allMatches(text).map((m) {
      final import = m.group(1);
      final importedUri = Uri.parse(import);
      if (importedUri.scheme != "package" && !importedUri.isAbsolute) {
        final file = File(
          path.normalize(path.join(sourceDir == null ? import : '${sourceDir.absolute.path}$import')),
        ).absolute;
        if (!file.existsSync()) {
          throw ArgumentError(
            "Cannot resolve relative URI $importedUri in file $uri: "
            "Replace imported URIs with package or absolute URIs",
          );
        }
        return "import 'file:${file.path}';";
      }
      return text.substring(m.start, m.end);
    }).toList();

    if (alsoImportOriginalFile) {
      imports.add("import '${uri}';");
    }

    return imports;
  }

  ClassDeclaration getClassDeclarationFromType(Type type) {
    final classMirror = reflectType(type);
    return analyzer.getClassFromFile(
        MirrorSystem.getName(classMirror.simpleName), resolveUri(classMirror.location.sourceUri));
  }

  List<Annotation> getAnnotationsFromField(Type _type, String propertyName) {
    var type = reflectClass(_type);
    var field = getClassDeclarationFromType(type.reflectedType).getField(propertyName);
    while (field == null) {
      type = type.superclass;
      if (type.reflectedType == Object) {
        break;
      }
      field = getClassDeclarationFromType(type.reflectedType).getField(propertyName);
    }

    return (field.parent.parent as FieldDeclaration).metadata.toList();
  }
}
