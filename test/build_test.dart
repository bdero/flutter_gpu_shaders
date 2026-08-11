import 'dart:convert' as convert;
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:data_assets/data_assets.dart';
import 'package:flutter_gpu_shaders/build.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';

void main() {
  group('collectShaderBundleDependencies', () {
    final packageRoot = Uri.parse('file:///pkg/');

    test('resolves manifest file paths against the package root', () {
      final manifestUri = Uri.parse(
        'file:///pkg/shaders/bundle.shaderbundle.json',
      );
      final manifest = convert.json.decode('''
        {
          "UnskinnedVertex": {
            "type": "vertex",
            "file": "shaders/flutter_scene_unskinned.vert"
          },
          "StandardFragment": {
            "type": "fragment",
            "file": "shaders/flutter_scene_standard.frag"
          }
        }
      ''');
      final deps = collectShaderBundleDependencies(
        manifestUri,
        manifest,
        packageRoot: packageRoot,
      );
      expect(deps, [
        manifestUri,
        Uri.parse('file:///pkg/shaders/flutter_scene_unskinned.vert'),
        Uri.parse('file:///pkg/shaders/flutter_scene_standard.frag'),
      ]);
    });

    test('does not double the directory for a manifest in a subdirectory', () {
      // Regression: `file` paths are package-root-relative (as impellerc
      // resolves them), so a manifest under shaders/ referencing
      // shaders/x.frag must not become shaders/shaders/x.frag.
      final manifestUri = Uri.parse(
        'file:///pkg/shaders/bundle.shaderbundle.json',
      );
      final manifest = convert.json.decode('''
        {
          "Frag": { "type": "fragment", "file": "shaders/example.frag" }
        }
      ''');
      final deps = collectShaderBundleDependencies(
        manifestUri,
        manifest,
        packageRoot: packageRoot,
      );
      expect(deps, [
        manifestUri,
        Uri.parse('file:///pkg/shaders/example.frag'),
      ]);
    });

    test('skips entries without a string file field', () {
      final manifestUri = Uri.parse('file:///pkg/bundle.shaderbundle.json');
      // Malformed entries should not blow up; the user will see a real
      // error from impellerc when it tries to compile.
      final manifest = convert.json.decode('''
        {
          "Good":   { "type": "vertex",   "file": "good.vert" },
          "Bad":    { "type": "fragment" },
          "Ugly":   "not even a map",
          "Worse":  { "type": "vertex", "file": 42 }
        }
      ''');
      final deps = collectShaderBundleDependencies(
        manifestUri,
        manifest,
        packageRoot: packageRoot,
      );
      expect(deps, [manifestUri, Uri.parse('file:///pkg/good.vert')]);
    });

    test('returns only the manifest when the decoded value is not a map', () {
      final manifestUri = Uri.parse('file:///pkg/bundle.shaderbundle.json');
      final deps = collectShaderBundleDependencies(
        manifestUri,
        '[]',
        packageRoot: packageRoot,
      );
      expect(deps, [manifestUri]);
    });
  });

  group('shaderBundleImpellercArguments', () {
    final out = Uri.parse(
      'file:///pkg/build/shaderbundles/bundle.shaderbundle',
    );
    final manifestDir = Uri.parse('file:///pkg/shaders/');
    final shaderLib = Uri.parse('file:///sdk/shader_lib/');

    test('emits sl, shader-bundle, and the two default includes', () {
      final args = shaderBundleImpellercArguments(
        outputBundleFilePath: out,
        manifestJson: '{}',
        manifestDirectory: manifestDir,
        shaderLibDirectory: shaderLib,
      );
      expect(args, [
        '--sl=${out.toFilePath()}',
        '--shader-bundle={}',
        '--include=${manifestDir.toFilePath()}',
        '--include=${shaderLib.toFilePath()}',
      ]);
    });

    test('emits depfile argument when a depfile path is provided', () {
      final depfile = Uri.parse(
        'file:///pkg/build/shaderbundles/bundle.shaderbundle.d',
      );
      final args = shaderBundleImpellercArguments(
        outputBundleFilePath: out,
        manifestJson: '{}',
        manifestDirectory: manifestDir,
        shaderLibDirectory: shaderLib,
        depfilePath: depfile,
      );
      expect(args, contains('--depfile=${depfile.toFilePath()}'));
    });

    test('appends an --include for each extra directory, in order', () {
      final depA = Uri.parse('file:///dep_a/shaders/');
      final depB = Uri.parse('file:///dep_b/glsl/');
      final args = shaderBundleImpellercArguments(
        outputBundleFilePath: out,
        manifestJson: '{}',
        manifestDirectory: manifestDir,
        shaderLibDirectory: shaderLib,
        includeDirectories: [depA, depB],
      );
      final includes = args.where((a) => a.startsWith('--include=')).toList();
      expect(includes, [
        '--include=${manifestDir.toFilePath()}',
        '--include=${shaderLib.toFilePath()}',
        '--include=${depA.toFilePath()}',
        '--include=${depB.toFilePath()}',
      ]);
    });

    test('an empty include list matches the default behaviour', () {
      List<String> build({List<Uri>? includeDirectories}) =>
          shaderBundleImpellercArguments(
            outputBundleFilePath: out,
            manifestJson: '{}',
            manifestDirectory: manifestDir,
            shaderLibDirectory: shaderLib,
            includeDirectories: includeDirectories ?? const [],
          );
      expect(build(includeDirectories: const []), build());
    });
  });

  group('impellerCHelpSupportsDepfile', () {
    test('returns true when help advertises the depfile flag', () {
      expect(
        impellerCHelpSupportsDepfile(
          '[optional]          --depfile=<depfile_path>',
        ),
        isTrue,
      );
    });

    test('returns false when help omits the depfile flag', () {
      expect(
        impellerCHelpSupportsDepfile(
          '[optional,multiple] --include=<include_directory>',
        ),
        isFalse,
      );
    });
  });

  group('parseImpellerCDepfileDependencies', () {
    test('parses dependency paths from a single-line depfile', () {
      final deps = parseImpellerCDepfileDependencies(
        '/pkg/build/shaderbundles/bundle.shaderbundle: '
        '/pkg/shaders/main.frag /pkg/shaders/include/common.glsl\n',
      );
      expect(deps, [
        Uri.parse('file:///pkg/shaders/main.frag'),
        Uri.parse('file:///pkg/shaders/include/common.glsl'),
      ]);
    });

    test('resolves relative dependency paths against a base URI', () {
      final deps = parseImpellerCDepfileDependencies(
        'build/shaderbundles/bundle.shaderbundle: '
        'shaders/main.frag shaders/include/common.glsl',
        relativeTo: Uri.parse('file:///pkg/'),
      );
      expect(deps, [
        Uri.parse('file:///pkg/shaders/main.frag'),
        Uri.parse('file:///pkg/shaders/include/common.glsl'),
      ]);
    });

    test('handles a drive-letter colon in the target path', () {
      final deps = parseImpellerCDepfileDependencies(
        r'C:\pkg\build\shaderbundles\bundle.shaderbundle: '
        'shaders/main.frag',
        relativeTo: Uri.parse('file:///pkg/'),
      );
      expect(deps, [Uri.parse('file:///pkg/shaders/main.frag')]);
    });

    test('returns no dependencies when the depfile is missing deps', () {
      expect(parseImpellerCDepfileDependencies('target:'), isEmpty);
      expect(parseImpellerCDepfileDependencies(''), isEmpty);
    });

    test('rejoins unescaped spaces when the combined path exists', () {
      final onDisk = {
        '/Users/u/Library/Application Support/sdk/shader_lib/types.glsl',
        '/pkg/shaders/main.frag',
      };
      final deps = parseImpellerCDepfileDependencies(
        'bundle.shaderbundle: '
        '/Users/u/Library/Application Support/sdk/shader_lib/types.glsl '
        '/pkg/shaders/main.frag',
        fileExists: onDisk.contains,
      );
      expect(deps, [
        Uri.parse(
          'file:///Users/u/Library/Application%20Support/sdk/shader_lib/types.glsl',
        ),
        Uri.parse('file:///pkg/shaders/main.frag'),
      ]);
    });

    test('rejoins a path containing several spaces', () {
      final onDisk = {'/a/one two three/dep.glsl'};
      final deps = parseImpellerCDepfileDependencies(
        'target: /a/one two three/dep.glsl',
        fileExists: onDisk.contains,
      );
      expect(deps, [Uri.parse('file:///a/one%20two%20three/dep.glsl')]);
    });

    test('honors escaped spaces without an existence probe', () {
      final deps = parseImpellerCDepfileDependencies(
        r'target: /a/one\ two/dep.glsl /pkg/main.frag',
        fileExists: (_) => false,
      );
      expect(deps, [
        Uri.parse('file:///a/one%20two/dep.glsl'),
        Uri.parse('file:///pkg/main.frag'),
      ]);
    });

    test('keeps genuinely missing paths split as written', () {
      final deps = parseImpellerCDepfileDependencies(
        'target: /gone/a.glsl /gone/b.glsl',
        fileExists: (_) => false,
      );
      expect(deps, [
        Uri.parse('file:///gone/a.glsl'),
        Uri.parse('file:///gone/b.glsl'),
      ]);
    });

    test('rejoins relative spaced paths against the base URI', () {
      final onDisk = {'/pkg/shader lib/common.glsl'};
      final deps = parseImpellerCDepfileDependencies(
        'target: shader lib/common.glsl',
        relativeTo: Uri.parse('file:///pkg/'),
        fileExists: onDisk.contains,
      );
      expect(deps, [Uri.parse('file:///pkg/shader%20lib/common.glsl')]);
    });
  });

  group('DataAsset registration', () {
    test('computes default DataAsset names and Flutter asset keys', () {
      expect(
        shaderBundleDataAssetName('materials.shaderbundle'),
        'flutter_gpu_shaders/shaderbundles/materials.shaderbundle',
      );
      expect(
        flutterDataAssetKey(
          package: 'example_app',
          name: 'flutter_gpu_shaders/shaderbundles/materials.shaderbundle',
        ),
        'packages/example_app/'
        'flutter_gpu_shaders/shaderbundles/materials.shaderbundle',
      );
    });

    test('falls back when DataAssets are unavailable', () {
      final input = _buildInput(buildDataAssets: false);
      final output = BuildOutputBuilder();
      final result = registerShaderBundleDataAsset(
        buildInput: input,
        buildOutput: output,
        outputBundleFile: Uri.parse(
          'file:///pkg/build/shaderbundles/materials.shaderbundle',
        ),
        legacyAssetKey: 'build/shaderbundles/materials.shaderbundle',
        assetMode: ShaderBundleAssetMode.dataAssetsIfAvailable,
      );

      expect(result, isNull);
      expect(output.build().assets.encodedAssets, isEmpty);
    });

    test('throws when DataAssets are required but unavailable', () {
      final input = _buildInput(buildDataAssets: false);
      final output = BuildOutputBuilder();

      expect(
        () => registerShaderBundleDataAsset(
          buildInput: input,
          buildOutput: output,
          outputBundleFile: Uri.parse(
            'file:///pkg/build/shaderbundles/materials.shaderbundle',
          ),
          legacyAssetKey: 'build/shaderbundles/materials.shaderbundle',
          assetMode: ShaderBundleAssetMode.dataAssetsRequired,
        ),
        throwsA(isA<UnsupportedError>()),
      );
      expect(output.build().assets.encodedAssets, isEmpty);
    });

    test('registers a DataAsset when enabled', () {
      final input = _buildInput(buildDataAssets: true);
      final output = BuildOutputBuilder();
      final outputFile = Uri.parse(
        'file:///pkg/build/shaderbundles/materials.shaderbundle',
      );

      final result = registerShaderBundleDataAsset(
        buildInput: input,
        buildOutput: output,
        outputBundleFile: outputFile,
        legacyAssetKey: 'build/shaderbundles/materials.shaderbundle',
        assetMode: ShaderBundleAssetMode.dataAssetsIfAvailable,
        dataAssetName: 'custom/materials.shaderbundle',
      );

      expect(result, isNotNull);
      expect(result!.outputFile, outputFile);
      expect(
        result.legacyAssetKey,
        'build/shaderbundles/materials.shaderbundle',
      );
      expect(result.dataAssetName, 'custom/materials.shaderbundle');
      expect(
        result.dataAssetId,
        'package:example_app/custom/materials.shaderbundle',
      );
      expect(
        result.flutterAssetKey,
        'packages/example_app/custom/materials.shaderbundle',
      );

      final assets = output.build().assets.encodedAssets;
      expect(assets, hasLength(1));
      final asset = assets.single.asDataAsset;
      expect(asset.file, outputFile);
      expect(asset.name, 'custom/materials.shaderbundle');
      expect(asset.package, 'example_app');
    });
  });

  group('engine stamp', () {
    late Directory temp;
    late Uri impellerc;
    late Uri stamp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('flutter_gpu_shaders_stamp');
      impellerc = temp.uri.resolve('impellerc');
      File.fromUri(impellerc).writeAsBytesSync([1, 2, 3, 4]);
      stamp = engineStampUriForBundle(temp.uri.resolve('base.shaderbundle'));
    });

    tearDown(() => temp.deleteSync(recursive: true));

    test('stamp content hashes the compiler binary', () async {
      final contents = await engineStampJson(
        impellercExec: impellerc,
        glesLanguageVersion: 300,
      );
      final decoded = convert.json.decode(contents) as Map<String, dynamic>;
      expect(
        decoded['impellerc_sha256'],
        crypto.sha256.convert([1, 2, 3, 4]).toString(),
      );
      expect(decoded['gles_language_version'], 300);
    });

    test('write is skipped when the content is unchanged', () async {
      await writeEngineStampIfChanged(
        stampUri: stamp,
        impellercExec: impellerc,
      );
      final file = File.fromUri(stamp);
      // The fresh write is backdated so hook runners never see the stamp as
      // modified during the build.
      expect(file.lastModifiedSync().toUtc(), DateTime.utc(2000));
      file.setLastModifiedSync(DateTime.utc(2010));

      await writeEngineStampIfChanged(
        stampUri: stamp,
        impellercExec: impellerc,
      );
      expect(file.lastModifiedSync().toUtc(), DateTime.utc(2010));
    });

    test('a changed compiler rewrites the stamp', () async {
      await writeEngineStampIfChanged(
        stampUri: stamp,
        impellercExec: impellerc,
      );
      final before = File.fromUri(stamp).readAsStringSync();

      File.fromUri(impellerc).writeAsBytesSync([5, 6, 7, 8]);
      await writeEngineStampIfChanged(
        stampUri: stamp,
        impellercExec: impellerc,
      );
      expect(File.fromUri(stamp).readAsStringSync(), isNot(before));
    });
  });
}

BuildInput _buildInput({required bool buildDataAssets}) {
  final temp = Directory.systemTemp.createTempSync(
    'flutter_gpu_shaders_build_input',
  );
  final builder = BuildInputBuilder()
    ..setupShared(
      packageRoot: temp.uri,
      packageName: 'example_app',
      outputDirectoryShared: temp.uri.resolve('.dart_tool/hook/'),
      outputFile: temp.uri.resolve('.dart_tool/hook/output.json'),
    )
    ..setupBuildInput();
  builder.config.setupBuild(linkingEnabled: false);
  if (buildDataAssets) {
    DataAssetsExtension().setupBuildInput(builder);
  }
  return builder.build();
}
