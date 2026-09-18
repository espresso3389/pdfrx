import 'package:integration_test/integration_test.dart';

import '../../../test/pdf_viewer_selection_drag_test.dart' as selection;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  selection.selectionDragTests(useFlutterInitialization: true);
}
