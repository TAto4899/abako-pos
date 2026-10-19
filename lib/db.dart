import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

import 'connector.dart';
import 'schema.dart';

late PowerSyncDatabase db;
bool _dbOpened = false;

Future<void> openDatabase() async {
  if (_dbOpened) return;
  final dir = await getApplicationSupportDirectory();
  final path = join(dir.path, 'pos-stock-spike.db');
  db = PowerSyncDatabase(schema: schema, path: path);
  await db.initialize();
  await db.connect(connector: SupabaseConnector(db));
  _dbOpened = true;
}
