import 'dart:async';
import 'dart:math';
import 'package:exer7/provider/recording_entries.dart';
import 'package:exer7/model/recording.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:audioplayers/audioplayers.dart';

class Coordinates {
  double latitude;
  double longitude;

  Coordinates(this.latitude, this.longitude);
}

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => RecordingEntries(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MyHomePage(title: 'Ambience Tracker'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final String title;
  const MyHomePage({super.key, required this.title});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlayingPath;

  bool audioPermissionGranted = false;
  final record = AudioRecorder();
  int recordCount = 0;
  bool isRecording = false;

  bool locationPermissionGranted = false;
  Coordinates? location;

  final double center = 200;
  final double maxRad = 100;

  double x = 200;
  double y = 200;
  double rad = 50;

  //Read the official package documentation to see what each sensor does
  List<double>? _userAccelerometerValues;

  final _streamSubscriptions = <StreamSubscription<dynamic>>[];
  Duration sensorInterval = SensorInterval.normalInterval;
  final List<double> _motionList = [];

  Timer? _motionTimer;
  double? _latestMagnitude;

  @override
  void initState() {
    _checkPermissions();
    super.initState();
    _streamSubscriptions.add(
      userAccelerometerEventStream(samplingPeriod: sensorInterval).listen((
        UserAccelerometerEvent event,
      ) {
        setState(() {
          _userAccelerometerValues = <double>[event.x, event.y, event.z];

          if (isRecording) {
            double magnitude = sqrt(
              event.x * event.x + event.y * event.y + event.z * event.z,
            );

            _latestMagnitude = magnitude;
          }
        });
      }),
    );
    _audioPlayer.onPlayerComplete.listen((event) {
      setState(() {
        _currentlyPlayingPath = null;
      });
    });
  }

  @override
  void dispose() {
    record.dispose();
    super.dispose();
  }

  // recording start
  Future<void> _startRecording() async {
    if (audioPermissionGranted) {
      await _audioPlayer.stop();
      setState(() => _currentlyPlayingPath = null);
      var dir = await getApplicationDocumentsDirectory();

      int timestamp = DateTime.now().millisecondsSinceEpoch;

      var filePath = '${dir.path}/recording_$timestamp.m4a';

      await record.start(RecordConfig(), path: filePath);

      setState(() {
        isRecording = true;
        _motionList.clear();
      });

      _motionTimer = Timer.periodic(Duration(milliseconds: 250), (i) {
        if (_latestMagnitude != null) {
          _motionList.add(_latestMagnitude!);
        }
      });
    }
  }

  // get current location
  Future<void> getLocation() async {
    if (locationPermissionGranted) {
      Position pos = await Geolocator.getCurrentPosition();
      var loc = Coordinates(pos.latitude, pos.longitude);

      setState(() {
        location = loc;
      });
    }
  }

  // recording stop
  Future<void> _stopRecording() async {
    final path = await record.stop();

    setState(() {
      isRecording = false;
    });

    Position pos = await Geolocator.getCurrentPosition();
    String locString =
        "${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}";

    // average motion inensity
    double avgIntensity = 0;
    if (_motionList.isNotEmpty) {
      double totalSum = 0;
      for (double val in _motionList) {
        totalSum += val;
      }
      avgIntensity = totalSum / _motionList.length;
    }

    if (path != null) {
      context.read<RecordingEntries>().addEntry(
        Recording(path: path, location: locString, intensity: avgIntensity),
      );
      recordCount++;
    }

    _motionList.clear();
    _motionTimer?.cancel();
    _motionTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final entries = context.watch<RecordingEntries>().entries;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.purple,
      ),
      body: Column(
        children: [
          SizedBox(height: 16.0),
          Center(
            child: OutlinedButton(
              onPressed: isRecording ? _stopRecording : _startRecording,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isRecording ? 'Stop Recording' : 'Play Recording',
                    style: isRecording
                        ? TextStyle(color: Colors.red)
                        : TextStyle(color: Colors.purple),
                  ),
                  SizedBox(width: 8),
                  isRecording
                      ? Icon(Icons.square, color: Colors.red, size: 16.0)
                      : Icon(
                          Icons.play_arrow,
                          color: Colors.purple,
                          size: 16.0,
                        ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16.0),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      "No recordings yet. Try adding some!",
                      style: TextStyle(fontSize: 16.0),
                    ),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      bool isHigh = entry.intensity >= 15;

                      String fileName = entry.path.split('/').last;

                      return Container(
                        color: isHigh ? Colors.red : Colors.white,
                        child: ListTile(
                          leading: Icon(
                            Icons.mic,
                            color: isHigh ? Colors.white : Colors.purple,
                          ),
                          title: Text(
                            fileName,
                            style: TextStyle(
                              color: isHigh ? Colors.white : Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            "(${entry.location})\nMotion Intensity: ${entry.intensity.toStringAsFixed(5)}",
                            style: TextStyle(
                              color: isHigh ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              _currentlyPlayingPath == entry.path
                                  ? Icons.stop_circle
                                  : Icons.play_circle_fill,
                              color: isHigh ? Colors.white : Colors.purple,
                            ),
                            onPressed: () => _handlePlayback(entry.path),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // when play button is clicked
  Future<void> _handlePlayback(String path) async {
    //  do not play if currently recording a new recording
    if (isRecording) {
      return;
    }

    // if the same file is playing, stop it
    if (_currentlyPlayingPath == path) {
      await _audioPlayer.stop();
      setState(() => _currentlyPlayingPath = null);
    } else {
      // if a different file is playing, stop first
      await _audioPlayer.stop();

      await _audioPlayer.play(DeviceFileSource(path));
      setState(() => _currentlyPlayingPath = path);
    }
  }

  Future<void> _checkPermissions() async {
    LocationPermission permission;
    bool serviceEnabled;

    // check location services
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    // check location permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    locationPermissionGranted = true;

    // checks and requests for permission for audio record
    if (!await record.hasPermission()) return;

    audioPermissionGranted = true;
  }
}
