/*
 * Copyright (C) 2005-present, 58.com.  All rights reserved.
 * Use of this source code is governed by a BSD type license that can be
 * found in the LICENSE file.
 */

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:build/build.dart';
import 'package:crypto/crypto.dart' show md5;
import 'package:fair_compiler/src/state_transfer.dart';
import 'package:path/path.dart' as path;
import 'package:dartToJs/index.dart' as dart2js;
import 'helper.dart' show FlatCompiler, ModuleNameHelper;

class ArchiveBuilder extends PostProcessBuilder with FlatCompiler {
  @override
  FutureOr<void> build(PostProcessBuildStep buildStep) async {
    final dir = path.join('build','fair');
    Directory(dir).createSync(recursive: true);

    var moduleNameKey = buildStep.inputId.path.replaceAll('.bundle.json', '');
    var moduleNameValue = ModuleNameHelper().modules[moduleNameKey];

    final bundleName = path.join(
            dir,
            buildStep.inputId.path
                .replaceAll(inputExtensions.first, '.fair.json')
                .replaceAll('lib', moduleNameValue)
                .replaceAll('/', '_')
                .replaceAll('\\', '_'));
    final jsName = bundleName.replaceFirst('.json', '.js');

    await dart2JS(buildStep.inputId.path, jsName);
    await compileBundle(buildStep, bundleName);

    // 压缩下发产物
    var zipSrcPath = path.join(Directory.current.path, 'build', 'fair');
    var zipDesPath = path.join(Directory.current.path, 'build', 'fair', 'fair_patch.zip');
    _zip(Directory(zipSrcPath), File(zipDesPath));

   await stateTransfer();
  }

  @override
  Iterable<String> get inputExtensions => ['.bundle.json'];

  Future dart2JS(String input, String jsName) async {
    var partPath = path.join(Directory.current.path, input.replaceFirst('.bundle.json', '.dart'));
    print('\u001b[33m [Fair Dart2JS] partPath => ${partPath} \u001b[0m');
    if (File(partPath).existsSync()) {
      try {
        var result = await dart2js.convertFile(partPath, true);
        File(jsName)..writeAsStringSync(result);
      } catch (e) {
        print('[Fair Dart2JS] e => ${e}');
      }
    }
  }

  Future compileBundle(PostProcessBuildStep buildStep, String bundleName) async {
    final bytes = await buildStep.readInputAsBytes();
    final file = File(bundleName)..writeAsBytesSync(bytes);
    if (file.lengthSync() > 0) {
      buildStep.deletePrimaryInput();
    }
    var bin = await compile(file.absolute.path);
    if (bin.success) {
      print('[Fair] FlatBuffer format generated for ${file.path}');
    } else {
      print('error: [Fair] FlatBuffer format fail ${bin.message}');
    }
    final buffer = StringBuffer();
    buffer.writeln('# Generated by Fair on ${DateTime.now()}.\n');
    final source = buildStep.inputId.path.replaceAll(inputExtensions.first, '.dart');
    buffer.writeln('source: ${buildStep.inputId.package}|$source');
    final digest = md5.convert(bytes).toString();
    buffer.writeln('md5: $digest');
    buffer.writeln('json: ${buildStep.inputId.package}|${file.path}');
    if (bin.success) {
      buffer.writeln('bin: ${buildStep.inputId.package}|${bin.data}');
    }
    buffer.writeln('date: ${DateTime.now()}');
    File('${bundleName.replaceAll('.json', '.metadata')}').writeAsStringSync(buffer.toString());

    print('[Fair] New bundle generated => ${file.path}');
  }

  void _zip(Directory data, File zipFile) {
    final archive = Archive();
    for (var entity in data.listSync(recursive: false)) {
      if (entity is! File) {
        continue;
      }
      if (entity.path.endsWith('.js') || entity.path.endsWith('.json')) {
        final file = entity;
        var filename = file.path.split(Platform.pathSeparator).last;
        final List<int> bytes = file.readAsBytesSync();
        archive.addFile(ArchiveFile(filename, bytes.length, bytes));
      }
    }
    var encode = ZipEncoder().encode(archive);
    if (encode == null) return;
    zipFile.writeAsBytesSync(encode, flush: false);
  }
}
