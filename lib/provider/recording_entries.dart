import 'package:flutter/material.dart';
import '../model/recording.dart';

class RecordingEntries extends ChangeNotifier {
  final List<Recording> _entries = [];

  List<Recording> get entries => _entries;

  void addEntry(Recording entry) {
    _entries.add(entry);
    notifyListeners();
  }
}
