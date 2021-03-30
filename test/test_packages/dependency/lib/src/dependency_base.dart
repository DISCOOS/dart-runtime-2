import 'package:runtime_2/runtime_2.dart';

class Consumer {
  String get message => (RuntimeContext.current[runtimeType] as ConsumerRuntime).message;
}

abstract class ConsumerRuntime {
  String get message;
}
