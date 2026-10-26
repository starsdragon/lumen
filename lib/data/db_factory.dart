import 'package:sembast/sembast.dart';

import 'db_factory_io.dart' if (dart.library.html) 'db_factory_web.dart';

Future<Database> openDatabaseForPlatform() => openPlatformDatabase();
