
import 'dart:math';
import 'dart:typed_data';
import 'package:collection/collection.dart';

class MessageMetaInfo {
  final bool isValid;
  final int mLength;
  final int payloadStart;
  final int payloadLength;
  final int messageType;
  final bool isFrameEnd;

  MessageMetaInfo({this.isValid, this.mLength, this.payloadStart, this.payloadLength, this.messageType, this.isFrameEnd});
  
}

class TrackerDataStamp {
  final String bib;
  final DateTime time;
  final bool valid;
  final int status;
  final int order;
  final double distance;
  final double speed;
  final int gap;
  final int tendency;
  final String result;
  final double lat;
  final double lng;
  double elevation;

  TrackerDataStamp(
      {this.valid, this.status, this.order, this.distance, this.speed, this.gap, this.tendency, this.result, this.lat, this.lng, this.bib, this.time});
}

class CourseElement {
  double lat;
  double lng;
  double elevation;

  CourseElement(double lat_, double lng_, double elevation_) {
    lat = lat_;
    lng = lng_;
    elevation = elevation_;
  }
}

class Parser {
  Reader _reader;

  List<TrackerDataStamp> trackerData  = [];
  String _currentRsc;
  int _currentTimeStamp;
  List<TrackerDataStamp> _currentSplits = [];
  List<CourseElement> course = [];
  double courseMinElevation = 1000;
  double courseMaxElevation = -1000;



  double distance(DateTime time, String bib) {
    final sp = bibSplits[bib];
    final closeStamp = sp.lastWhere((e) => time.isAfter(e.time)|| e.time.isAtSameMomentAs(time), orElse: ()=> sp.first);
    if (closeStamp.result != '') {
      return -10;
    }
    final dt = time.difference(closeStamp.time).inMilliseconds/ 1000;
    return closeStamp.distance + dt *closeStamp.speed; //(meters per millisecond)
  }

  DateTime time(double distance, String bib) {
    final sp = bibSplits[bib];
    final closeStamp = sp.lastWhere((e) => e.distance <= distance, orElse: ()=> sp.first);
    if (closeStamp.result != '') {
      return DateTime(199,1,1);
    }
    final dd = distance - closeStamp.distance;
    final dt = closeStamp.speed > 0 ? (dd/closeStamp.speed)*1000 : 0;
    return closeStamp.time.add(Duration(milliseconds: dt.round()));


  }

  int _version;
  Parser(data) {
    _reader = Reader(data);
    for (var n = 0; n < _reader._dataLength;) {
      final header = getMessageMetaInformation(n, _reader);
      if (header.messageType == 0) {
        parseReferenceTS(header.payloadStart, header);
      } else if (header.messageType == 1) {
        parseProtocolVersion(header.payloadStart, header);
      } else if (header.messageType == 10) {
        parseRsc(header.payloadStart, header);
      } else if (header.messageType == 20) {
        parseFrameData(header.payloadStart, header);
      } else if (header.messageType == 40) {
        parseTrackerData(header.payloadStart, header);
      }
      n += header.mLength + 5;
    }

    calculateHeights();

  }


  void calculateHeights() {
    var elevation = 0.0;
  bibSplits.forEach( (bib, splits)  {
    elevation = 0.0;
      var lastE = splits[0];
      splits.forEach((e)
  {
    if (e != splits[0]) {
      var horizontalDistance = metersBetween(
          e.lat, e.lng, lastE.lat, lastE.lng);
      var courseDistance = e.distance - lastE.distance;
      if ((horizontalDistance < courseDistance)) {
        var delta = sqrt(courseDistance * courseDistance -
            horizontalDistance * horizontalDistance);
        var sign = (lastE.speed > e.speed) ? 1.0 : -1.0;
        elevation += sign * delta * .15;

        course.add( CourseElement(e.lat, e.lng, elevation));
        if (elevation < courseMinElevation) {
          courseMinElevation = elevation;
        }

        if (elevation > courseMaxElevation) {
          courseMaxElevation = elevation;
        }

        lastE = e;
      }
    }
  });
  });

  }



  void parseReferenceTS(int payloadStart, MessageMetaInfo meta) {
    _currentTimeStamp = _reader.getBigLongAt(payloadStart);
    _currentSplits = <TrackerDataStamp>[];
    splits[DateTime.fromMillisecondsSinceEpoch(_currentTimeStamp)] = _currentSplits;
  }

  void parseFrameData(int payloadStart, MessageMetaInfo meta) {}

  void  bbox(double lat, double lng) {
      if (_bbox[0] > lat) {
        _bbox[0] = lat;
      }
      if (_bbox[1] > lng) {
        _bbox[1] = lng;
      }
      if (_bbox[2] < lat) {
        _bbox[2] = lat;
      }
      if (_bbox[3] < lng) {
        _bbox[3] = lng;
      }
  }
 List<double> get boundingBox => _bbox;

  final List<double> _bbox = [double.infinity, double.infinity,
                              double.negativeInfinity, double.negativeInfinity];

  final Map<String, List<TrackerDataStamp>> bibSplits = {};
  final Map<DateTime, List<TrackerDataStamp>> splits = {};

  void parseTrackerData(int payloadStart, MessageMetaInfo meta) {
    var cnt = _reader.getSShortAt(payloadStart, true);

    var  i = payloadStart + 2;
    for (var o = 0; o < cnt; o++) {
      var r = _reader.getByteAt(i);
      i += 1;
      var bib = _reader.getStringAt(i, r);
      i += r;
      var order = _reader.getByteAt(i);
      i += 1;
      var status = _reader.getByteAt(i);
      i += 1;
      var c = _reader.getByteAt(i);
      i += 1;
      var speed = _reader.getFloatAt(i);
      i += 4;
      var distance = _reader.getFloatAt(i);
      if (distance < 0) {
        distance = 0;
      }
      i += 4;
      final lat = _reader.getFloatAt(i);
      i += 4;
      final lng = _reader.getFloatAt(i);
      i += 4;
      var gap = _reader.getSLongAt(i, true);
      if (gap < 0) {
        gap = 0;
      }
      i += 4;
      var tendency = _reader.getByteAt(i);
      i += 1;
      var f = _reader.getByteAt(i);
      i += 1;
      var result = _reader.getStringAt(i, f);
      i += f;

      final n = TrackerDataStamp(valid: c > 0,
          bib: bib,
          time: DateTime.fromMillisecondsSinceEpoch(_currentTimeStamp),
          status: status,
          order: order,
          distance: distance,
          speed: speed * 1000/60,
          gap: gap,
          tendency: tendency,
          result: result,
          lat: lat,
          lng :lng
      );


      if( !(lat == 0 && lng == 0) ) {
        bbox(lat, lng);

        if (!bibSplits.containsKey(bib)){
          bibSplits[bib] = <TrackerDataStamp>[];
        }
        bibSplits[bib].add(n);
        trackerData.add(n);
      }

      //_activeRace.addTrackerDataStamp(a, this._currentTimeStamp, n);

      //this._activeRace.addTimeStamp(this._currentTimeStamp)
    }
  }

  MessageMetaInfo getMessageMetaInformation(t, Reader r) {
    var i = r.getByteAt(t);
    var mLength = r.getShortAt(t + 2, true);
    var  o = r.getByteAt(t + 4 + mLength);
    return MessageMetaInfo(
        isValid: (2 == i || 3 == o || 4 == o),
        isFrameEnd: o == 4,
        messageType: r.getByteAt(t + 1),
        mLength: mLength,
        payloadStart: t + 4,
        payloadLength: mLength,
    );
    
  }

  void parseProtocolVersion(int payloadStart, MessageMetaInfo meta) {
    _version = _reader.getByteAt(payloadStart);
  }

  void parseRsc(int payloadStart, MessageMetaInfo header) {
    _currentRsc = _reader.getStringAt(payloadStart, header.payloadLength);
  }
}



class Reader {
  final ByteData _data;
  int get _dataLength => _data.lengthInBytes;

  Reader(String data_,) : _data = ByteData.view(Uint8List.fromList(data_.codeUnits).buffer);

  Uint8List getRawData() {
    return _data.buffer.asUint8List();
  }

  int getByteAt(t) {
    return 255 & _data.getUint8(t);
  }

  int getSByte(t) {
    return  _data.getInt8(t);
  }


  double getFloatAt(t) {
    return _data.getFloat32(t);
  }

  String getStringAt(f, l) => String.fromCharCodes(_data.buffer.asUint8List(f, l));

  int getLength() => _dataLength;

  int getShortAt(t, e) {
    return _data.getUint16(t);
  }

  int getSShortAt(t, e) {
    return _data.getInt16(t);
  }

  int getBigLongAt(int t) {
    return  _data.getUint64(t);
  }

  int getLongAt(t, e) {
    return  _data.getUint32(t);
  }

  int getSLongAt(t, e) {
    return  _data.getInt32(t);
  }

}

double metersBetween(double lat0, double lon0, double lat1, double lon1) {
  var R = 6371000;  // radius of Earth in meters
  var phi_1 = lat0 /57.2958;
  var phi_2 = lat1 /57.2958;
  var delta_phi = (lat1 - lat0) /57.2958;
  var delta_lambda = (lon1 - lon0)/57.2958;
  // haversine
  var a = pow(sin(delta_phi / 2.0), 2 )+ cos(phi_1) * cos(phi_2) * pow(sin(delta_lambda / 2.0), 2);
  var c = 2 * atan2(sqrt(a), sqrt(1-a));
  return c * R;

}

