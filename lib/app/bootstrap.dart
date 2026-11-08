import 'tool_registry.dart';

/// Registers every tool with the registry. Each feature adds its entry here
/// so the home grid is driven by one list.
void bootstrap() {
  ToolRegistry.registerAll(const <ToolEntry>[]);
}
