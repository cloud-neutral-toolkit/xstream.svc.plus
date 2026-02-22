import '../widgets/log_console.dart';

class LogStore {
  static final List<LogEntry> _logs = [];

  /// 原始添加方式（内部用）
  static void add(LogEntry entry) {
    _logs.add(entry);
  }

  /// ✅ 新增封装方法：统一外部调用日志
  static void addLog(LogLevel level, String message) {
    _logs.add(LogEntry(level, message));
  }

  static void clear() {
    _logs.clear();
  }

  static List<LogEntry> getAll() => List.unmodifiable(_logs);
}
