import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'hosting_access_policy.dart';

/// App-private storage. Use one policy instance; this is not a cross-process
/// database. Flush before rename so a crash cannot leave a partial ledger.
class FileHostingQuotaStore implements HostingQuotaStore {
  FileHostingQuotaStore(this.file);
  final File file;

  static Future<FileHostingQuotaStore> inApplicationSupport() async {
    final directory = await getApplicationSupportDirectory();
    return FileHostingQuotaStore(
      File(path.join(directory.path, 'hosting_allowance_v1.json')),
    );
  }

  @override
  Future<String?> read() async {
    try {
      return await file.readAsString();
    } on PathNotFoundException {
      return null;
    }
  }

  @override
  Future<void> write(String value) async {
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.pending');
    await pending.writeAsString(value, flush: true);
    await pending.rename(file.path);
  }
}
