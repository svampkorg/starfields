import 'dart:math';
import 'dart:typed_data';

/// Starfield simulation in closed form, stored as struct-of-arrays.
///
/// The original simulation stepped every star once per tick (8 ms) with
/// `offset *= 1 + speed * 0.004`, i.e. exponential growth away from the screen
/// center. Here the same motion is evaluated directly from the star's age:
///
///     offset(age) = origin * e^(rate * age),  rate = ln(1 + speed * 0.004) / tick
///
/// so the result is frame-rate independent and no per-frame state is mutated,
/// except when a star leaves the screen and is respawned at the center.
///
/// Positions are offsets from the screen center in normalized units (the screen
/// spans -0.5..0.5 on both axes).
class Starfield {
  /// Speed factor per tick of the original stepped simulation.
  static const double _speedFactor = 0.004;

  /// Size growth per tick, indexed by `speed - 1`.
  static const List<double> _growthPerTick = [0.001, 0.003, 0.006, 0.016, 0.030, 0.050, 0.070, 0.090, 0.120, 0.150];

  /// Size of a newly spawned star.
  static const double initialSize = 0.1;

  /// Stars start growing once they are this far from the center on either axis.
  static const double _growThreshold = 0.015;

  /// Stars are respawned once they are this far from the center on either axis.
  static const double _exitDistance = 0.7;

  /// Max offset from the center on either axis when respawning.
  static const double _respawnJitter = 0.0001;

  /// How far behind a respawn may lag before it is moved to the current time.
  static const double _maxCatchUpSeconds = 1;

  /// Number of stars; change it with [resize].
  int get count => _count;
  int _count = 0;

  /// Duration of one step of the original simulation, in seconds. Also the
  /// interval at which stars are added at start-up.
  final double tickSeconds;

  /// When false, every star is spawned at once and never respawned.
  final bool respawn;

  final Random _random;

  // Per-star constants.
  Float64List _rate = Float64List(0);
  Float64List _growthPerSecond = Float64List(0);

  // Per-life values, replaced on respawn.
  Float64List _originX = Float64List(0);
  Float64List _originY = Float64List(0);
  Float64List _spawnTime = Float64List(0);
  Float64List _growStart = Float64List(0);
  Float64List _lifetime = Float64List(0);

  /// Output of [update]: the first [visibleCount] entries are the stars that
  /// are currently on screen.
  Float64List get x => _x;
  Float64List get y => _y;
  Float64List get size => _size;
  Float64List _x = Float64List(0);
  Float64List _y = Float64List(0);
  Float64List _size = Float64List(0);
  int visibleCount = 0;

  /// Creates [count] stars. With [respawn] they appear one per tick from
  /// [startTime], like the original start-up; otherwise all at once.
  Starfield({required int count, this.tickSeconds = 0.008, this.respawn = true, double startTime = 0, Random? random})
    : _random = random ?? Random() {
    _ensureCapacity(count);
    for (var i = 0; i < count; i++) {
      _initStar(i, startTime + (respawn ? i * tickSeconds : 0));
    }
    _count = count;
  }

  /// Changes the number of stars at [time] without disturbing the existing
  /// ones. Added stars appear at once, anywhere on screen; removed stars are
  /// the most recently added ones.
  void resize(int newCount, {required double time}) {
    _ensureCapacity(newCount);
    for (var i = _count; i < newCount; i++) {
      _initStar(i, time);
    }
    _count = newCount;
  }

  void _initStar(int i, double spawnTime) {
    final speed = _random.nextInt(10) + 1;
    _rate[i] = log(1 + speed * _speedFactor) / tickSeconds;
    _growthPerSecond[i] = _growthPerTick[speed - 1] / tickSeconds;
    // The first life starts anywhere on screen; later ones at the center.
    _startLife(i, time: spawnTime, originX: _random.nextDouble() - 0.5, originY: _random.nextDouble() - 0.5);
  }

  void _ensureCapacity(int capacity) {
    if (capacity <= _rate.length) return;
    // Grow geometrically so repeated small resizes stay cheap.
    final newCapacity = max(capacity, _rate.length * 2);
    Float64List grow(Float64List list) => Float64List(newCapacity)..setRange(0, list.length, list);
    _rate = grow(_rate);
    _growthPerSecond = grow(_growthPerSecond);
    _originX = grow(_originX);
    _originY = grow(_originY);
    _spawnTime = grow(_spawnTime);
    _growStart = grow(_growStart);
    _lifetime = grow(_lifetime);
    _x = grow(_x);
    _y = grow(_y);
    _size = grow(_size);
  }

  /// True when no star will ever be visible again.
  bool get isFinished => !respawn && visibleCount == 0;

  /// Evaluates every star at [time] seconds since the start.
  void update(double time) {
    var n = 0;
    for (var i = 0; i < _count; i++) {
      var age = time - _spawnTime[i];
      if (age < 0) continue;
      if (age >= _lifetime[i] && !respawn) continue;
      while (age >= _lifetime[i]) {
        // Respawn at the exact moment the star left the screen, so the result
        // does not depend on the frame rate. After a long pause (e.g. app in
        // background), skip ahead instead of replaying every lost life.
        final exitTime = _spawnTime[i] + _lifetime[i];
        _respawn(i, time - exitTime > _maxCatchUpSeconds ? time : exitTime);
        age = time - _spawnTime[i];
      }
      final scale = exp(_rate[i] * age);
      _x[n] = _originX[i] * scale;
      _y[n] = _originY[i] * scale;
      _size[n] = initialSize + _growthPerSecond[i] * max(0.0, age - _growStart[i]);
      n++;
    }
    visibleCount = n;
  }

  void _respawn(int i, double time) {
    double jitter() => (_random.nextBool() ? 1 : -1) * _random.nextDouble() * _respawnJitter;
    _startLife(i, time: time, originX: jitter(), originY: jitter());
  }

  void _startLife(int i, {required double time, required double originX, required double originY}) {
    _originX[i] = originX;
    _originY[i] = originY;
    _spawnTime[i] = time;
    // Distance on the dominant axis decides both when growth starts and when
    // the star leaves the screen. Guard against an origin of exactly zero.
    final distance = max(max(originX.abs(), originY.abs()), 1e-9);
    _growStart[i] = max(0.0, log(_growThreshold / distance) / _rate[i]);
    _lifetime[i] = log(_exitDistance / distance) / _rate[i];
  }
}
