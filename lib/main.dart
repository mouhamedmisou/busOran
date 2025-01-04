import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';

LatLng? dest;
List<BusLine> busLines = [];
List<BusStop> busStops = [];
List<Polyline> polylines = [];
List<Marker> _stopMarkers = [];
List<Marker> _otherMarkers = [];
late bool UseRealLoc = false;
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
    busStops.add(BusStop(
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
    busLines.add(BusLine(line['id'] as String, line['name'] as String,
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
    void calculateRoute(LatLng start, LatLng end) async {
      print("finding path");
      BusStop startStop = findNearestStop(start);
      BusStop endStop = findNearestStop(end);
      print("finding path from ${startStop.name} to ${endStop.name}");
      List<PathLine> path =
          aStarAlgorithm(busStops, busLines, startStop, endStop);
      if (path.isEmpty) {
        print("no path found");
        return;
      }
      polylines = [];
      _stopMarkers = [];
      for (var stop in path) {
        print(
            "take line ${stop.lineID} from ${stop.startIndex} to ${stop.endIndex} then ");
        LoadLineIndexed(stop.lineID, stop.startIndex, stop.endIndex,
            clear: false);
      }
    }

    Timer timer = Timer.periodic(Duration(seconds: 2), (timer) {
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
              if (UseRealLoc) {
                Geolocator.getCurrentPosition().then((value) {
                  calculateRoute(
                      LatLng(value.latitude, value.longitude), point);
                });
              } else {
                LatLng start = LatLng(35.6607, -0.6316);
                calculateRoute(start, point);
              }
              ;
            },
            initialCenter: LatLng(35.6971, -0.6308),
            initialZoom: 12.0,
            maxZoom: 16.0,
            minZoom: 12.0,
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
                  title: Column(
                    children: [
                      Text("Clear Lines"),
                      IconButton(
                          onPressed: () {
                            UseRealLoc = !UseRealLoc;
                          },
                          icon: Icon(
                            UseRealLoc ? Icons.location_on : Icons.location_off,
                          ))
                    ],
                  ),
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
                        offset: Offset(2, 2),
                        blurRadius: 3.0,
                        color: Colors.black.withOpacity(0.5),
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
  }
  endIndex++;
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

class BusLine {
  final String id;
  final String name;
  final List<String> stops;
  final Color color;
  BusLine(this.id, this.name, this.stops, this.color);
}

class BusStop {
  final String id;
  final String name;
  final LatLng position;
  final List<String> lines;
  BusStop(this.id, this.name, this.position, this.lines);
}

BusStop findNearestStop(LatLng position) {
  BusStop nearest = busStops[0];
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

List<BusStop> GetWalkableStops(
    LatLng
        pos) //This is here for future use 'test multiple starts and endpoints'
{
  List<BusStop> stops = [];
  for (var stop in busStops) {
    if (calculateDistance(pos, stop.position) < 0.5) {
      stops.add(stop);
    }
  }
  return stops;
}

double calculateDistance(LatLng start, LatLng dest) {
  double lat1 = start.latitude * pi / 180;
  double lon1 = start.longitude * pi / 180;
  double lat2 = dest.latitude * pi / 180;
  double lon2 = dest.longitude * pi / 180;

  double dlat = lat2 - lat1;
  double dlon = lon2 - lon1;

  return sqrt(dlat * dlat + dlon * dlon) * 111.0;
}

class BusPath {
  List<BusPathLine> lines = [];
  BusPath(this.lines);
}

class BusPathLine {
  final String lineId;
  final int startIndex;
  final int endIndex;
  BusPathLine(this.lineId, this.startIndex, this.endIndex);
}

class PathLine {
  final String lineID;
  final int startIndex;
  final int endIndex;

  PathLine(this.lineID, this.startIndex, this.endIndex);
}

List<PathLine> aStarAlgorithm(List<BusStop> allStops, List<BusLine> allLines,
    BusStop start, BusStop goal) {
  List<AStarNode> openList = [];
  List<AStarNode> closedList = [];

  AStarNode startNode = AStarNode(
    start,
    gCost: 0,
    hCost: calculateDistance(start.position, goal.position),
  );
  openList.add(startNode);

  while (openList.isNotEmpty) {
    // Get node with the lowest fCost
    AStarNode currentNode =
        openList.reduce((a, b) => a.fCost < b.fCost ? a : b);
    openList.remove(currentNode);

    // Goal reached
    if (currentNode.stop.id == goal.id) {
      List<PathLine> path = [];
      while (currentNode.parent != null) {
        path.add(currentNode.usedLine!);
        currentNode = currentNode.parent!;
      }
      return path.reversed.toList();
    }

    closedList.add(currentNode);

    // Process neighbors
    for (String lineId in currentNode.stop.lines) {
      BusLine line = allLines.firstWhere((line) => line.id == lineId);
      List<String> stopsOnLine = line.stops;

      for (int i = 0; i < stopsOnLine.length; i++) {
        if (stopsOnLine[i] == currentNode.stop.id) {
          // Add neighbors
          List<int> neighborIndices = [i - 1, i + 1];
          for (int neighborIndex in neighborIndices) {
            if (neighborIndex < 0 || neighborIndex >= stopsOnLine.length) {
              continue;
            }

            String neighborStopId = stopsOnLine[neighborIndex];
            BusStop neighbor =
                allStops.firstWhere((stop) => stop.id == neighborStopId);

            if (closedList.any((node) => node.stop.id == neighbor.id)) {
              continue;
            }

            double tentativeGCost = currentNode.gCost +
                calculateDistance(currentNode.stop.position, neighbor.position);

            var existingNode;
            for (var node in openList) {
              if (node.stop.id == neighbor.id) {
                existingNode = node;
              }
            }

            if (existingNode == null || tentativeGCost < existingNode.gCost) {
              AStarNode neighborNode = existingNode ??
                  AStarNode(
                    neighbor,
                    gCost: double.infinity,
                    hCost: calculateDistance(neighbor.position, goal.position),
                  );

              neighborNode.gCost = tentativeGCost;
              neighborNode.hCost =
                  calculateDistance(neighbor.position, goal.position);
              neighborNode.parent = currentNode;
              neighborNode.usedLine = PathLine(lineId, i, neighborIndex);

              if (existingNode == null) {
                openList.add(neighborNode);
              }
            }
          }
        }
      }
    }
  }

  return []; // No path found
}

class AStarNode {
  final BusStop stop;
  double gCost;
  double hCost;
  AStarNode? parent;
  PathLine? usedLine; // Tracks the line used to reach this node

  AStarNode(this.stop,
      {this.gCost = double.infinity,
      this.hCost = double.infinity,
      this.parent,
      this.usedLine});

  double get fCost => gCost + hCost;
}
