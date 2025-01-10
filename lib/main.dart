import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';

LatLng? dest;
List<BBusLine> busLines = [];
List<BBusStop> busStops = [];
List<Polyline> polylines = [];
List<Marker> _stopMarkers = [];
List<Marker> _otherMarkers = [];
late bool UseRealLoc = false;
List<String> _linesResult = [];
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
    busStops.add(BBusStop(
        stop['id'] as String,
        stop['name'] as String,
        LatLng(stop['latitude'] as double, stop['longitude'] as double),
        Set()));
  }

  response = await rootBundle.loadString('assets/lines_with_stops.json');
  data = json.decode(response);
  for (Map<String, dynamic> line in data) {
    Color color = Color(int.parse(line['color'] as String, radix: 16));
    color = color.withAlpha(500);
    BBusLine current =
        BBusLine(line['id'] as String, line['name'] as String, [], color);
    busLines.add(current);
    for (String stop in line['stops'] as List<dynamic>) {
      busStops.firstWhere((element) => element.id == stop).lines.add(current);
      current.stops.add(busStops.firstWhere((element) => element.id == stop));
    }
  }
  print("Data Loaded");
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
      BBusStop startStop = findNearestStop(start);
      BBusStop endStop = findNearestStop(end);
      print("finding path from ${startStop.name} to ${endStop.name}");
      List<PathLine> path = aStarAlgorithm(startStop, endStop);
      if (path.isEmpty) {
        print("no path found");
        return;
      }
      polylines = [];
      _stopMarkers = [];
      _linesResult = [];
      BBusLine currentLine = path[0].line;
      int startIndex = path[0].startIndex;
      for (var stop in path) {
        if (stop.line.id != currentLine.id) {
          _linesResult.add(
              "Take ${currentLine.name} from ${currentLine.stops[startIndex].name} to ${stop.line.stops[stop.startIndex].name} \n then Change to  ");
          currentLine = stop.line;
          startIndex = stop.startIndex;
        }
        LoadLineIndexed(stop.line, stop.startIndex, stop.endIndex,
            clear: false);
      }

      _linesResult.add(
          " ${path.last.line.name} from ${currentLine.stops[startIndex].name} to ${currentLine.stops[path.last.endIndex].name}");
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
              LoadLine(line, clear: false);
            }
            setState(() {});
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
            DraggableScrollableSheet(
                initialChildSize: 0.1,
                minChildSize: 0.1,
                maxChildSize: 1,
                builder: (context, scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20.0),
                        topRight: Radius.circular(20.0),
                      ),
                    ),
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: _linesResult.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          title: Text(_linesResult[index]),
                        );
                      },
                    ),
                  );
                }),
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
                    _linesResult = [];
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
                  LoadLine(busLines[index - 1]);
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

void LoadStops({BBusLine? Line = null, bool clear = true}) {
  if (clear) {
    _stopMarkers = [];
  }
  if (Line != null) {
    for (var stop in Line.stops) {
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
  } else {
    for (BBusStop stop in busStops) {
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
}

void LoadLineIndexed(BBusLine Line, int startIndex, int endIndex,
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
  List<LatLng> points = [];
  for (var stop in Line.stops) {
    points.add(stop.position);
  }
  polylines.add(Polyline(
    points: points.sublist(startIndex, endIndex),
    strokeWidth: 3.0,
    color: Line.color,
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

void LoadLine(BBusLine Line, {bool clear = true}) {
  if (clear) {
    polylines = [];
  }
  List<LatLng> points = [];
  for (BBusStop stop in Line.stops) {
    points.add(stop.position);
  }
  polylines.add(Polyline(
    points: points,
    strokeWidth: 3.0,
    color: Line.color,
  ));
  LoadStops(Line: Line, clear: clear);
}

class BBusLine {
  final String id;
  final String name;
  final List<BBusStop> stops;
  final Color color;
  BBusLine(this.id, this.name, this.stops, this.color);
}

class BBusStop {
  final String id;
  final String name;
  final LatLng position;
  final Set<BBusLine> lines;
  BBusStop(this.id, this.name, this.position, this.lines);
}

BBusStop findNearestStop(LatLng position) {
  BBusStop nearest = busStops[0];
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

List<BBusStop> GetWalkableStops(
    LatLng
        pos) //This is here for future use 'test multiple starts and endpoints'
{
  List<BBusStop> stops = [];
  for (var stop in busStops) {
    if (calculateDistance(pos, stop.position) < 0.5) {
      stops.add(stop);
    }
  }
  return stops;
}

double calculateDistance(LatLng start, LatLng dest) {
  return Geolocator.distanceBetween(
      start.latitude, start.longitude, dest.latitude, dest.longitude);
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
  final BBusLine line;
  final int startIndex;
  final int endIndex;

  PathLine(this.line, this.startIndex, this.endIndex);
}

List<PathLine> aStarAlgorithm(BBusStop start, BBusStop goal) {
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
    for (BBusLine line in currentNode.stop.lines) {
      List<BBusStop> stopsOnLine = line.stops;

      for (int i = 0; i < stopsOnLine.length; i++) {
        //Here I can get rud of them Line Changing => Somehow  :'(
        if (stopsOnLine[i].id == currentNode.stop.id) {
          // Add neighbors
          List<int> neighborIndices = [i - 1, i + 1];
          for (int neighborIndex in neighborIndices) {
            if (neighborIndex < 0 || neighborIndex >= stopsOnLine.length) {
              continue;
            }

            BBusStop neighbor = stopsOnLine[neighborIndex];

            if (closedList.any((node) => node.stop.id == neighbor.id)) {
              continue;
            }

            double tentativeGCost = currentNode.gCost +
                calculateDistance(currentNode.stop.position, neighbor.position);
            //as a test im gonna add a penalty for changing lines ==========>>>> it worked  :D
            if (currentNode.usedLine != null) {
              if (currentNode.usedLine!.line.id != line.id) {
                tentativeGCost += 1000;
              }
            }

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
              neighborNode.usedLine = PathLine(line, i, neighborIndex);

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
  final BBusStop stop;
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
