import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';

LatLng? dest;
List<busLine> busLines = [];
List<busStop> busStops = [];
List<Polyline> polylines = [];
List<Marker> _stopMarkers = [];
List<Marker> _otherMarkers = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print(Geolocator.getCurrentPosition());
  await loadData();
  runApp(const MyApp());
}

Future<void> loadData() async {
  print("Loading Data");

  String response = await rootBundle.loadString('assets/merged_stops.json');
  var data = json.decode(response);

  for (Map<String, dynamic> stop in data) {
    busStops.add(busStop(
        stop['id'] as String,
        stop['name'] as String,
        LatLng(stop['latitude'] as double, stop['longitude'] as double),
        List<String>.from(stop['Lines'])));
  }

  response = await rootBundle.loadString('assets/lines_with_stops.json');
  data = json.decode(response);
  for (Map<String, dynamic> line in data) {
    Color color = Color(int.parse(line['color'] as String, radix: 16));
    color = color.withAlpha(500);
    busLines.add(busLine(line['id'] as String, line['name'] as String,
        List<String>.from(line['stops']), color));
  }
  print(busStops);
  print(busLines);
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    void findPath(LatLng start, LatLng end) async {
      print("finding path");
      busStop startStop = findNearestStop(start);
      busStop endStop = findNearestStop(end);

      print("start: ${startStop.name} ===> end: ${endStop.name}");
      List<String> startLines = startStop.lines;
      for (var line in startLines) {
        if (endStop.lines.contains(line)) {
          LoadLineIndexed(
              line,
              busLines
                  .firstWhere((busLine) => busLine.id == line)
                  .stops
                  .indexOf(startStop.id),
              busLines
                      .firstWhere((busLine) => busLine.id == line)
                      .stops
                      .indexOf(endStop.id) +
                  1);
          return;
        }
      }
      print("no direct line found");
      for (var line in startLines) {
        for (var stopId
            in busLines.firstWhere((busLine) => busLine.id == line).stops) {
          busStop transferStop =
              busStops.firstWhere((busStop) => busStop.id == stopId);
          for (var transferLine in transferStop.lines) {
            if (endStop.lines.contains(transferLine)) {
              LoadLineIndexed(
                  line,
                  busLines
                      .firstWhere((busLine) => busLine.id == line)
                      .stops
                      .indexOf(startStop.id),
                  busLines
                          .firstWhere((busLine) => busLine.id == line)
                          .stops
                          .indexOf(stopId) +
                      1,
                  clear: true);
              LoadLineIndexed(
                  transferLine,
                  busLines
                      .firstWhere((busLine) => busLine.id == transferLine)
                      .stops
                      .indexOf(stopId),
                  busLines
                          .firstWhere((busLine) => busLine.id == transferLine)
                          .stops
                          .indexOf(endStop.id) +
                      1,
                  clear: false);
              return;
            }
          }
        }
      }
      print("no line found");
    }

    Timer timer = Timer.periodic(Duration(seconds: 2), (timer) {
      //Load new bus data here
      setState(() {});
    });
    return MaterialApp(
      title: 'My Bus',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: Text('My Bus'),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            for (var line in busLines) {
              LoadLine(line.id, clear: false);
            }
          },
          child: Icon(Icons.remove_red_eye),
        ),
        body: FlutterMap(
          options: MapOptions(
            onTap: (tapPosition, point) {
              print("Tapped on $point");
              dest = point;
              LatLng start = LatLng(35.6607, -0.6316);
              findPath(start, point);
            },
            initialCenter: LatLng(35.6971, -0.6308), // Center on Oran
            initialZoom: 12.0,
            maxZoom: 16.0,
            minZoom: 13.0,
            interactionOptions: InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: "https://a.tile.openstreetmap.org/{z}/{x}/{y}.png",
            ),
            MarkerLayer(
              markers: _stopMarkers + _otherMarkers,
            ),
            PolylineLayer(polylines: polylines),
          ],
        ),
        endDrawer: Drawer(
          child: ListView.builder(
            itemCount: busLines.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  title: Text("Clear Lines"),
                  onTap: () {
                    polylines = [];
                    _stopMarkers = [];
                    Navigator.pop(context);
                  },
                );
              }
              return ListTile(
                title: Text(busLines[index - 1].name,
                    style: TextStyle(shadows: [
                      Shadow(
                        offset: Offset(2, 2), // Slight shadow offset
                        blurRadius: 3.0, // Blur radius
                        color: Colors.black.withOpacity(0.5), // Shadow color
                      ),
                    ], color: busLines[index - 1].color)),
                onTap: () {
                  LoadLine(busLines[index - 1].id);
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

void LoadStops({String? id = null, bool clear = true}) {
  if (clear) {
    _stopMarkers = [];
  }
  for (var stop in busStops) {
    if (id != null && !stop.lines.contains(id)) {
      continue;
    }
    _stopMarkers.add(
      Marker(
        width: 30.0,
        height: 30.0,
        point: stop.position,
        child: Icon(
          Icons.circle,
          color: Colors.red,
          size: 15.0,
        ),
      ),
    );
  }
}

void LoadLineIndexed(String id, int startIndex, int endIndex,
    {bool clear = true}) {
  if (startIndex > endIndex) {
    int temp = startIndex;
    startIndex = endIndex;
    endIndex = temp;
    endIndex++;
    startIndex--;
  }
  if (clear) {
    polylines = [];
    _stopMarkers = [];
  }
  for (var line in busLines) {
    if (line.id == id) {
      List<LatLng> points = [];
      for (var stop in line.stops) {
        for (var busStop in busStops) {
          if (busStop.id == stop) {
            points.add(busStop.position);
          }
        }
      }
      polylines.add(Polyline(
        points: points.sublist(startIndex, endIndex),
        strokeWidth: 3.0,
        color: line.color,
      ));
      for (var point in points.sublist(startIndex, endIndex)) {
        _stopMarkers.add(Marker(
          width: 30.0,
          height: 30.0,
          point: point,
          child: Icon(
            Icons.circle,
            color: Colors.red,
            size: 15.0,
          ),
        ));
      }
    }
  }
}

void LoadLine(String id, {bool clear = true}) {
  if (clear) {
    polylines = [];
  }
  for (var line in busLines) {
    if (line.id == id) {
      List<LatLng> points = [];
      for (var stop in line.stops) {
        for (var busStop in busStops) {
          if (busStop.id == stop) {
            points.add(busStop.position);
          }
        }
      }
      polylines.add(Polyline(
        points: points,
        strokeWidth: 3.0,
        color: line.color,
      ));
    }
  }
  LoadStops(id: id, clear: clear);
}

class busLine {
  final String id;
  final String name;
  final List<String> stops;
  final Color color;
  busLine(this.id, this.name, this.stops, this.color);
}

class busStop {
  final String id;
  final String name;
  final LatLng position;
  final List<String> lines;
  busStop(this.id, this.name, this.position, this.lines);
}

busStop findNearestStop(LatLng position) {
  busStop nearest = busStops[0];
  double min = calculateDistance(position, nearest.position);
  for (var stop in busStops) {
    LatLng bPosition = stop.position;
    double distance = calculateDistance(position, bPosition);
    if (distance < min) {
      min = distance;
      nearest = stop;
    }
  }
  return nearest;
}

double calculateDistance(LatLng start, LatLng dest) {
  // Convert degrees to radians
  double lat1 = start.latitude * pi / 180;
  double lon1 = start.longitude * pi / 180;
  double lat2 = dest.latitude * pi / 180;
  double lon2 = dest.longitude * pi / 180;

  // Calculate difference
  double dlat = lat2 - lat1;
  double dlon = lon2 - lon1;

  return sqrt(dlat * dlat + dlon * dlon) * 111.0;
}

