import 'package:sembast_web/sembast_web.dart';

Future<Database> openPlatformDatabase() async {
  return databaseFactoryWeb.openDatabase('lumen.db');
}
