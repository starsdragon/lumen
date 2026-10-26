import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openPlatformDatabase() async {
  final dir = await getApplicationSupportDirectory();
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  final path = p.join(dir.path, 'lumen.db');
  return databaseFactoryIo.openDatabase(path);
}
