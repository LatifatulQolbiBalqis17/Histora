import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../state/app_state.dart';
import 'country_detail.dart';

class WorldScreen extends StatefulWidget {
  const WorldScreen({super.key});

  @override
  State<WorldScreen> createState() => _WorldScreenState();
}

class _WorldScreenState extends State<WorldScreen>
    with SingleTickerProviderStateMixin {
  List<_WorldCountry> countries = const [];
  late final AnimationController ticker;
  double rotation = 0;
  double tilt = -.16;
  bool dragging = false;
  int lastTick = 0;

  @override
  void initState() {
    super.initState();
    ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )
      ..addListener(() {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (!dragging && lastTick != 0 && mounted) {
          final dt = math.min((now - lastTick) / 1000, .05);
          setState(() => rotation = (rotation + dt * .08) % (math.pi * 2));
        }
        lastTick = now;
      })
      ..repeat(min: 0, max: 1, period: const Duration(seconds: 1));
    _loadCountries();
  }

  Future<void> _loadCountries() async {
    try {
      final raw = await rootBundle.loadString('assets/data/world_countries.json');
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final loaded = decoded
          .whereType<Map<String, dynamic>>()
          .map(_WorldCountry.fromJson)
          .toList(growable: false);
      if (mounted) setState(() => countries = loaded);
    } catch (_) {
      if (mounted) setState(() => countries = const []);
    }
  }

  @override
  void dispose() {
    ticker.dispose();
    super.dispose();
  }

  void _openCountry(_WorldCountry picked) {
    final matches = context
        .read<AppState>()
        .countries
        .where((country) => country.id == picked.id);
    if (matches.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CountryDetail(country: matches.first)),
    );
  }

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 104),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'JELAJAHI\nDUNIA',
              style: TextStyle(
                color: HistoraColors.pearl,
                fontSize: 34,
                height: 1.05,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                shadows: const [
                  Shadow(color: Color(0xAA02101E), blurRadius: 12, offset: Offset(0, 3)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Putar globe dan ketuk titik emas\nuntuk membuka negara pilihanmu.',
              style: TextStyle(
                color: HistoraColors.cyan,
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
                shadows: const [
                  Shadow(color: Color(0xAA02101E), blurRadius: 8, offset: Offset(0, 2)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final diameter =
                      math.min(constraints.maxWidth, constraints.maxHeight);
                  return Center(
                    child: SizedBox.square(
                      dimension: diameter,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) => setState(() => dragging = true),
                        onPanUpdate: (details) => setState(() {
                          rotation =
                              (rotation + details.delta.dx * .011) % (math.pi * 2);
                          tilt = (tilt - details.delta.dy * .006)
                              .clamp(-.65, .65)
                              .toDouble();
                        }),
                        onPanEnd: (_) => setState(() => dragging = false),
                        onPanCancel: () => setState(() => dragging = false),
                        onTapUp: (details) {
                          final picked = _nearestCountry(
                            details.localPosition,
                            Size.square(diameter),
                          );
                          if (picked != null) _openCountry(picked);
                        },
                        child: CustomPaint(
                          painter: _GlobePainter(
                            countries: countries,
                            rotation: rotation,
                            tilt: tilt,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.threesixty, size: 18, color: HistoraColors.gold),
                  const SizedBox(width: 8),
                  Text(
                    'Globe interaktif • ketuk titik untuk membuka',
                    style: TextStyle(
                      color: HistoraColors.gold,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .3,
                      shadows: const [
                        Shadow(color: Color(0xAA02101E), blurRadius: 8, offset: Offset(0, 2)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  _WorldCountry? _nearestCountry(Offset tap, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .42;
    _WorldCountry? nearest;
    double best = 26;
    for (final country in countries) {
      final projected =
          _project(country.lat, country.lng, center, radius, rotation, tilt);
      if (projected == null) continue;
      final distance = (projected.point - tap).distance;
      if (distance < best) {
        best = distance;
        nearest = country;
      }
    }
    return nearest;
  }
}

class _Projection {
  const _Projection(this.point, this.depth);
  final Offset point;
  final double depth;
}

_Projection? _project(
  double latitude,
  double longitude,
  Offset center,
  double radius,
  double rotation,
  double tilt,
) {
  final lat = latitude * math.pi / 180;
  final lon = longitude * math.pi / 180 + rotation;
  final x = math.cos(lat) * math.sin(lon);
  final y0 = math.sin(lat);
  final z0 = math.cos(lat) * math.cos(lon);
  final y = y0 * math.cos(tilt) - z0 * math.sin(tilt);
  final z = y0 * math.sin(tilt) + z0 * math.cos(tilt);
  if (z < -.03) return null;
  return _Projection(Offset(center.dx + x * radius, center.dy - y * radius), z);
}

class _GlobePainter extends CustomPainter {
  const _GlobePainter({
    required this.countries,
    required this.rotation,
    required this.tilt,
  });

  final List<_WorldCountry> countries;
  final double rotation;
  final double tilt;

  // Benua disederhanakan sebagai poligon kasar (lng, lat).
  static const landShapes = <List<Offset>>[
    // Amerika Utara
    [Offset(-168, 66), Offset(-140, 70), Offset(-120, 72), Offset(-95, 72), Offset(-80, 68), Offset(-60, 52), Offset(-70, 42), Offset(-82, 26), Offset(-97, 20), Offset(-105, 22), Offset(-118, 33), Offset(-130, 48), Offset(-150, 60)],
    // Amerika Selatan
    [Offset(-78, 8), Offset(-62, 10), Offset(-50, 0), Offset(-38, -8), Offset(-48, -25), Offset(-58, -38), Offset(-68, -52), Offset(-74, -42), Offset(-72, -22), Offset(-80, -4)],
    // Eropa
    [Offset(-10, 36), Offset(-9, 44), Offset(-2, 50), Offset(8, 58), Offset(18, 70), Offset(32, 70), Offset(45, 60), Offset(38, 48), Offset(28, 42), Offset(18, 40), Offset(8, 38)],
    // Afrika
    [Offset(-16, 20), Offset(-8, 33), Offset(10, 37), Offset(32, 30), Offset(43, 12), Offset(50, 2), Offset(40, -12), Offset(34, -28), Offset(20, -35), Offset(12, -20), Offset(8, -2), Offset(-8, 5)],
    // Asia
    [Offset(30, 40), Offset(45, 42), Offset(55, 55), Offset(68, 70), Offset(100, 76), Offset(140, 72), Offset(170, 66), Offset(178, 62), Offset(160, 55), Offset(142, 45), Offset(128, 35), Offset(120, 22), Offset(105, 8), Offset(98, 12), Offset(90, 22), Offset(78, 8), Offset(72, 20), Offset(58, 26), Offset(48, 30)],
    // Asia Tenggara & kepulauan
    [Offset(95, 5), Offset(105, -5), Offset(118, -2), Offset(130, -3), Offset(140, -6), Offset(125, -10), Offset(108, -8)],
    // Australia
    [Offset(112, -14), Offset(130, -12), Offset(142, -10), Offset(152, -22), Offset(150, -36), Offset(138, -38), Offset(122, -34), Offset(112, -24)],
    // Antartika
    [Offset(-180, -72), Offset(-90, -78), Offset(0, -74), Offset(90, -78), Offset(180, -72), Offset(180, -86), Offset(-180, -86)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .42;
    final sphere = Rect.fromCircle(center: center, radius: radius);

    // Cahaya atmosfer di sekeliling bola.
    canvas.drawCircle(
      center,
      radius * 1.13,
      Paint()
        ..shader = RadialGradient(
          colors: [
            HistoraColors.cyan.withValues(alpha: .30),
            HistoraColors.cyan.withValues(alpha: .08),
            HistoraColors.cyan.withValues(alpha: 0),
          ],
          stops: const [.72, .88, 1],
        ).createShader(
          Rect.fromCircle(center: center, radius: radius * 1.13),
        ),
    );

    // Bayangan jatuh di bawah globe.
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0, radius * 1.06),
        width: radius * 1.5,
        height: radius * .28,
      ),
      Paint()
        ..color = const Color(0xFF010A14).withValues(alpha: .55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );

    canvas.save();
    canvas.clipPath(Path()..addOval(sphere));

    // Lautan: gradien bola dengan terang dari kiri atas.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.45, -.5),
          radius: 1.15,
          colors: [
            Color(0xFF7FE7F2),
            Color(0xFF1FA8C4),
            Color(0xFF0B5E86),
            Color(0xFF052A44),
            Color(0xFF020F1D),
          ],
          stops: [0, .3, .58, .82, 1],
        ).createShader(sphere),
    );

    // Daratan di sisi belakang (sambar) lalu sisi depan.
    final backLand = Paint()
      ..color = const Color(0xFF0E4A63).withValues(alpha: .5)
      ..style = PaintingStyle.fill;
    final frontLand = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF2DD7A), Color(0xFFC9A24B), Color(0xFF7C6A2E)],
      ).createShader(sphere)
      ..style = PaintingStyle.fill;
    for (final shape in landShapes) {
      _drawLand(canvas, shape, center, radius, backLand, frontLand);
    }

    // Garis lintang & bujur tipis.
    final grid = Paint()
      ..color = HistoraColors.pearl.withValues(alpha: .12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7;
    for (final latitude in [-60.0, -30.0, 0.0, 30.0, 60.0]) {
      _drawGeoLine(canvas, center, radius, grid, true, latitude);
    }
    for (double longitude = -150; longitude <= 180; longitude += 30) {
      _drawGeoLine(canvas, center, radius, grid, false, longitude);
    }

    // Titik negara, makin ke depan makin terang dan besar.
    final visible = <(_WorldCountry, _Projection)>[];
    for (final country in countries) {
      final point =
          _project(country.lat, country.lng, center, radius, rotation, tilt);
      if (point != null) visible.add((country, point));
    }
    visible.sort((a, b) => a.$2.depth.compareTo(b.$2.depth));
    for (final item in visible) {
     final depth = item.$2.depth.clamp(0.0, 1.0).toDouble();
final dotRadius = 1.6 + depth * 2.4;
      canvas.drawCircle(
        item.$2.point,
        dotRadius + 2.2,
        Paint()
          ..color = HistoraColors.gold.withValues(alpha: .12 + depth * .2)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        item.$2.point,
        dotRadius,
        Paint()
          ..color = Color.lerp(
            const Color(0xFF8A6D1F),
            const Color(0xFFFFE066),
            depth,
          )!
          ..style = PaintingStyle.fill,
      );
    }

    // Kilau cahaya di kiri atas bola.
    final highlight = center.translate(-radius * .36, -radius * .4);
    canvas.drawCircle(
      highlight,
      radius * .4,
      Paint()
        ..shader = RadialGradient(
          colors: [
            HistoraColors.pearl.withValues(alpha: .30),
            HistoraColors.pearl.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: highlight, radius: radius * .4)),
    );

    // Terminator: sisi kanan bawah lebih gelap agar terasa 3D.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x00000000), Color(0x55010A14)],
          stops: [.55, 1],
        ).createShader(sphere),
    );
    canvas.restore();

    // Tepi bola.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = HistoraColors.cyan.withValues(alpha: .55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
  }

  void _drawLand(
    Canvas canvas,
    List<Offset> coordinates,
    Offset center,
    double radius,
    Paint back,
    Paint front,
  ) {
    Path? path;
    double depthTotal = 0;
    int visibleCount = 0;
    for (final coordinate in coordinates) {
      final point =
          _project(coordinate.dy, coordinate.dx, center, radius, rotation, tilt);
      if (point == null) {
        path = null;
        continue;
      }
      depthTotal += point.depth;
      visibleCount++;
      path ??= Path()..moveTo(point.point.dx, point.point.dy);
      path.lineTo(point.point.dx, point.point.dy);
    }
    if (path == null || visibleCount < 3) return;
    path.close();
    canvas.drawPath(path, depthTotal / visibleCount > .18 ? front : back);
  }

  void _drawGeoLine(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
    bool latitudeLine,
    double fixed,
  ) {
    Path? path;
    for (int value = -180; value <= 180; value += 4) {
      final latitude = latitudeLine ? fixed : value / 2;
      final longitude = latitudeLine ? value.toDouble() : fixed;
      final point =
          _project(latitude, longitude, center, radius, rotation, tilt);
      if (point == null) {
        path = null;
      } else if (path == null) {
        path = Path()..moveTo(point.point.dx, point.point.dy);
      } else {
        path.lineTo(point.point.dx, point.point.dy);
      }
    }
    if (path != null) canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GlobePainter oldDelegate) =>
      oldDelegate.rotation != rotation ||
      oldDelegate.tilt != tilt ||
      oldDelegate.countries.length != countries.length;
}

class _WorldCountry {
  const _WorldCountry({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String name;
  final double lat;
  final double lng;

  factory _WorldCountry.fromJson(Map<String, dynamic> json) => _WorldCountry(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? 'Tanpa nama',
    lat: (json['lat'] as num?)?.toDouble() ?? 0,
    lng: (json['lng'] as num?)?.toDouble() ?? 0,
  );
}
