

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:fisparse/web_mercator/web_mercator.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart';
import 'package:vector_math/vector_math_64.dart';

import 'parse_gps.dart';

List<double> getValueBetweenTwoFixedColors(double value)
{
  double aR = 1;   double aG = 0; double aB=.01;  // RGB for our 1st color (blue in this case).
  double bR = 000; double bG = 1; double bB=.01;    // RGB for our 2nd color (red in this case).

  return [
    ((bR - aR) * value + aR),      // Evaluated as -255*value + 255.
    ((bG - aG) * value + aG),      // Evaluates as 0.
    ((bB - aB) * value + aB) ];      // Evaluates as 255*value + 0.
}

Future<void> fetchGPSTracking() async {
  //final url = 'https://livecache.sportresult.com/node/binaryData/NSWC2021_CCS_PROD/WC_2021_WSC/CCSW30KMMS------------FNL-000100--_GPSREPLAY.gps?h=HZUnMCwsvozfQbr0sqnWfueO/Zk=';
  //final url = 'https://livecache.sportresult.com/node/binaryData/NSWC2021_CCS_PROD/WC_2021_WSC/CCSWSPRINT------------FNL-000100--_GPSREPLAY.gps?h=MMKGb9mqYos/FuiFf9O9KZGxPvw=';
  //final url  = 'https://livecache.sportresult.com/node/binaryData/NSWC2021_CCS_PROD/WC_2021_WSC/CCSWSPRINT------------QUAL000100--_GPSREPLAY.gps?h=NCW7c2/LR/GgNKAVx1Z1jsyuK14=';
  //final url = 'https://livecache.sportresult.com/node/binaryData/NSWC2021_CCS_PROD/WC_2021_WSC/CCSMSPRINT------------FNL-000100--_GPSREPLAY.gps?h=WitdCDu0e78h6vo15kgooeppTEs=';
  //final url = 'https://livecache.sportresult.com/node/binaryData/NSWC2021_CCS_PROD/WC_2021_WSC/CCSWSKIATHLN----------FNL-000100--_GPSREPLAY.gps?h=g5UPuz7Kn+Rr8OIGvrs6MS/FiGY=';
  final url = 'https://livecache.sportresult.com/node/binaryData/NSWC2021_CCS_PROD/WC_2021_WSC/CCSMSKIATHLN----------FNL-000100--_GPSREPLAY.gps?h=vEl5o5xlqp6p98jp+DfcwY/06Go=';
  final rp = await http.get(Uri.parse(url));
    switch(rp.statusCode) {
      case 200:
        var p = Parser(rp.body);
        var i = Image(1200,1200);


        var vp= MercatorViewport.fitBounds(width: 1000, height: 1000, bounds: p.boundingBox);
        var min = 0;
        var max = p.courseMaxElevation - p.courseMinElevation;
        var range = (max - min);
        p.course.forEach((e) {
          var pp = vp.project(Vector2(e.lat, e.lng)) as Vector2;
          var elev = 0.1 *(e.elevation - p.courseMinElevation) /max;
          drawPixel(i, pp.y.truncate(), pp.x.truncate(), Color.fromHsl(0,0, elev));

        });

        File('heightmap.png').writeAsBytesSync(encodePng(i));
        break;
      case 2001:
        var p = Parser(rp.body);
        var i = Image(1200,1200);
        i.fill(getColor(0,0,0));
        var slice = <int, List<List>>{};
        var minTime = DateTime(1900,1,2);

        for(var bib in p.bibSplits.keys) {
          var time =  DateTime(1900,1,2);
          var d = 0;
          while (d < 50000 && time  != DateTime(1900,1,1)) {
            time  = p.time(d.toDouble(), bib);
            if(time != DateTime(1900,1,1)) {
              if (!slice.containsKey(d)) {
                slice[d] = [];
              }

              slice[d].add([int.parse(bib), time]);
              minTime = time.isBefore(minTime) ? minTime : time;
            }

            d += 1;
          }
        }

        final lines = <int, List<List<double>>>{};
        slice.forEach((d, results) {
          final x = (d/30000 );
          final leader = results.firstWhere((e) => e[0] == 7, orElse: ()=>null);
          if(leader != null) {
            final DateTime l1 = leader[1];
            results.forEach((e) {
              if (!lines.containsKey(e[0])) {
                lines[e[0]] = [];
              }
              final DateTime e1 = e[1];
              final y = ((1.5 - e1.difference(minTime).inMilliseconds/l1.difference(minTime).inMilliseconds) );
              lines[e[0]].add([x, y]);
            });
          }
        });

        final u23 = [5,7,25,40,47,46,44];
        var x0 = -1, y0 = -1;
        lines.forEach((b, points) {
          final v = 1 - min((b/50), 1.0);
          points.forEach((pt) {
            final x = (pt[0] * i.width ).round();
            final y = (pt[1] * i.height *.8).round() ;
            if (x0 != -1) {
              if(x0 > 0 && x0 <i.width && y0 > 0 && y0 < i.height &&
                  x > 0 && x <i.width && y > 0 && y < i.height ) {
                drawLine(i, 5+x0, 5+y0, 5+x, 5+y, [25,36,45].contains(b) ?  getColor(200,0,0): u23.contains(b) ? getColor(0,111,0, 200) : getColor(111,111,111, 5), antialias: false);
              }
            }
            x0 = x;
            y0 = y;
          });
        });

        File('pct-race-skiathalon-m.png').writeAsBytesSync(encodePng(i));
        break;


      case 20015:
        var p = Parser(rp.body);
        var i = Image(1200,1200);
        i.fill(getColor(0,0,0));
        var t0 = p.bibSplits.values.first.first.time;
        var timeSlice = <int, List<List<num>>>{};
        var maxTime = 0;

        for(var bib in p.bibSplits.keys) {
          var time = t0,
              d = 0.0;
          while (d < 30000 && d != -10) {
            d = p.distance(time, bib);
            final dt = time
                .difference(t0)
                .inSeconds;
            maxTime = max(maxTime, dt);
              if (!timeSlice.containsKey(dt)) {
                timeSlice[dt] = [];
              }

               timeSlice[dt].add([int.parse(bib), d]);

          time = time.add(Duration(milliseconds: 2000));
          }
        }

        final lines = <int, List<List<double>>>{};
        timeSlice.forEach((time, results) {
          final x = (time/(80*60) );
          final leader = results.firstWhere((e) => e[0] == 28, orElse: ()=>null);
            if(leader != null) {
              results.forEach((e) {
                if (!lines.containsKey(e[0])) {
                  lines[e[0]] = [];
                }
                final y = ((1.5 - e[1] / leader[1]) );
                lines[e[0]].add([x, y]);
              });
            }
        });

        final u23 = [10,8,16];
        var x0 = -1, y0 = -1;
        lines.forEach((b, points) {
          final v = 1 - min((b/50), 1.0);
            points.forEach((pt) {
              final x = (pt[0] * i.width ).round();
              final y = (pt[1] * i.height *.8).round() ;
              if (x0 != -1) {
                if(x0 > 0 && x0 <i.width && y0 > 0 && y0 < i.height &&
                x > 0 && x <i.width && y > 0 && y < i.height ) {
                  drawLine(i, 5+x0, 5+y0, 5+x, 5+y, [25,38,54].contains(b) ?  getColor(200,0,0): u23.contains(b) ? getColor(0,111,0, 200) : getColor(111,111,111, 20));
                }
              }
              x0 = x;
              y0 = y;
            });
        });

        File('pct-race-30k.png').writeAsBytesSync(encodePng(i));
        break;

      case 3200:
        var p = Parser(rp.body);
        var i = Image(1200,1200);
        i.fill(getColor(0,0,0));
        var t0 = p.bibSplits.values.first.first.time;
        var l  = p.bibSplits.values.first.last;
        for(var bib in p.bibSplits.keys) {
          var time = t0, d = 0.0, x0 = 0, y0 = 0;
          while (d < 30000 && d != -10 ) {
            d = p.distance(time, bib);
            time = time.add(Duration(milliseconds: 2000));
            final y = (time.difference(t0).inSeconds * 6.5).round() ;
            final x = (d).round();
            final v = min((int.parse(bib)/50), 1.0) * 0.5;
              drawLine(i, x, y, x0, y0, Color.fromHsl(v, 1, .5));
            x0 = x;
            y0 = y;
          }
        }
        File('race.png').writeAsBytesSync(encodePng(i));
        break;
      case 1200:
          var p = Parser(rp.body);
          
          
          
          
          var vp= MercatorViewport.fitBounds(width: 1000, height: 1000, bounds: p.boundingBox);
          var i = Image(1000,1000);
          var maxSpeed = p.trackerData.map((it)=>it.speed).reduce(max);
          p.trackerData.forEach((e) {
            var pp = vp.project(Vector2(e.lat, e.lng)) as Vector2;
            var v = min((e.speed / maxSpeed), 1.0) * 0.5;
            drawPixel(i, pp.y.truncate(), pp.x.truncate(), Color.fromHsl(v, 1,.5));

         });

          int n= 0;

          var oo = GifEncoder();
          var frame = i.clone();
          p.trackerData.forEach((e) {
            var pp = vp.project(Vector2(e.lat, e.lng)) as Vector2;
            drawPixel(frame, pp.y.truncate(), pp.x.truncate(), getColor(155,155,155));

            if (n++ % 100 == 0) {
              oo.addFrame(frame);
              frame = i.clone();
            }

          });



          File('anim.gif').writeAsBytesSync(oo.finish());
          //File('course201930K.png').writeAsBytesSync(encodePng(i));
          print(p.trackerData.length);
        break;
      default:
        print('error');
    }
}


int main() {
  fetchGPSTracking();
  return 0;
}