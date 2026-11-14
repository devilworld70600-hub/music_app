import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kBase = 'https://nazriya.musicmine.in/api';
const kKey = 'DARK_CHOOMU'; // TODO: baad me apne backend me shift karo

// ---------- Model ----------
class Song {
  final String id, title, artist, thumb;
  final int duration;
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumb,
    required this.duration,
  });

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        id: (j['id'] ?? '').toString(),
        title: _clean((j['title'] ?? '').toString()),
        artist: (j['uploader'] ?? '').toString().trim(),
        thumb: (j['thumbnail'] ?? '').toString(),
        duration: (j['duration'] ?? 0) is num ? (j['duration'] as num).toInt() : 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'uploader': artist,
        'thumbnail': thumb,
        'duration': duration,
      };

  // "Maruti (Official Video) Dhanda..." -> "Maruti"
  static String _clean(String t) {
    final c = t.split(RegExp(r'[(|\[]')).first.trim();
    return c.isEmpty ? t : c;
  }
}

// ---------- API ----------
class Api {
  static Uri _u(String ep, Map<String, String> p) =>
      Uri.parse('$kBase/$ep').replace(queryParameters: {...p, 'key': kKey});

  static Future<List<Song>> _songs(String ep, Map<String, String> p,
      {int maxSec = 720}) async {
    final r = await http.get(_u(ep, p));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final d = jsonDecode(r.body);
    final list = d is List ? d : (d['results'] ?? d['data'] ?? []) as List;
    return list
        .whereType<Map<String, dynamic>>()
        .map(Song.fromJson)
        .where((s) => s.duration >= 45 && s.duration <= maxSec) // shorts/reviews hatao
        .toList();
  }

  // API ek baar me ~5 hi deti hai, isliye kai variants parallel me mila ke dikhate hain
  static Future<List<Song>> search(String q, {int extra = 4, int maxSec = 720}) async {
    final qs = [q, '$q song', '$q official audio', '$q lyrics', '$q new song']
        .take(extra + 1)
        .toList();
    final lists = await Future.wait(qs.map((x) =>
        _songs('search', {'q': x, 'limit': '25'}, maxSec: maxSec).catchError((_) => <Song>[])));
    final seen = <String>{};
    return [
      for (final l in lists)
        for (final s in l)
          if (seen.add(s.id)) s
    ];
  }

  static Future<String?> lyrics(String title, String artist) async {
    for (final q in ['$title $artist', title]) {
      try {
        final r = await http.get(Uri.parse('https://lrclib.net/api/search')
            .replace(queryParameters: {'q': q}));
        if (r.statusCode != 200) continue;
        for (final e in jsonDecode(r.body) as List) {
          final t = e['plainLyrics'];
          if (t is String && t.trim().isNotEmpty) return t.trim();
        }
      } catch (_) {}
    }
    return null;
  }
  static Future<List<Song>> trending() => _songs('trending', {});

  // Response format pata nahi, isliye flexible parsing
  static Future<List<String>> suggest(String q) async {
    try {
      final r = await http.get(_u('suggest', {'q': q}));
      final d = jsonDecode(r.body);
      final list =
          d is List ? d : (d['suggestions'] ?? d['results'] ?? []) as List;
      return list
          .map((e) => e is String ? e : (e['text'] ?? e['title'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .take(8)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String audioUrl(Song s) =>
      _u('audio', {'q': '${s.title} ${s.artist}'}).toString();

  static String videoUrl(Song s) =>
      _u('video', {'q': '${s.title} ${s.artist}'}).toString();
}

// ---------- Player ----------
class PlayerService extends ChangeNotifier {
  PlayerService._() {
    // queue/next/prev player ke andar hi chalte hain, taaki notification aur
    // lock screen ke buttons bhi kaam karein
    player.currentIndexStream.listen((i) {
      if (i == null || i >= queue.length) return;
      index = i;
      Library.i.addRecent(queue[i]);
      notifyListeners();
    });
    player.playerStateStream.listen((_) => notifyListeners());
  }
  static final i = PlayerService._();

  final player = AudioPlayer();
  List<Song> queue = [];
  int index = -1;
  bool shuffle = false;
  LoopMode loop = LoopMode.off;
  Timer? _sleep;
  String source = '';
  ConcatenatingAudioSource? _cs;

  Song? get current => (index >= 0 && index < queue.length) ? queue[index] : null;

  AudioSource _src(Song s) => AudioSource.uri(
        Uri.parse(Api.audioUrl(s)),
        tag: MediaItem(
          id: s.id,
          title: s.title,
          artist: s.artist,
          artUri: Uri.tryParse(s.thumb),
          duration: Duration(seconds: s.duration),
        ),
      );

  Future<void> playQueue(List<Song> songs, int start, {String source = ''}) async {
    queue = List.of(songs);
    index = start;
    this.source = source;
    notifyListeners();
    try {
      _cs = ConcatenatingAudioSource(children: queue.map(_src).toList());
      await player.setAudioSource(_cs!, initialIndex: start);
      player.play();
    } catch (_) {
      // play nahi hua; UI me spinner band ho jayega
    }
  }

  Future<void> addToQueue(Song s) async {
    if (_cs == null || queue.isEmpty) {
      await playQueue([s], 0, source: 'Queue');
      return;
    }
    queue.add(s);
    await _cs!.add(_src(s));
    notifyListeners();
  }

  Future<void> next() => player.seekToNext();

  Future<void> prev() async {
    if (player.position.inSeconds > 3) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  void toggle() => player.playing ? player.pause() : player.play();

  void toggleShuffle() {
    shuffle = !shuffle;
    player.setShuffleModeEnabled(shuffle);
    notifyListeners();
  }

  void cycleLoop() {
    loop = loop == LoopMode.off
        ? LoopMode.all
        : loop == LoopMode.all
            ? LoopMode.one
            : LoopMode.off;
    player.setLoopMode(loop);
    notifyListeners();
  }

  void setSleep(int? minutes) {
    _sleep?.cancel();
    if (minutes != null) {
      _sleep = Timer(Duration(minutes: minutes), () => player.pause());
    }
  }
}

// ---------- Liked songs, recents, recent searches ----------
class Library extends ChangeNotifier {
  Library._();
  static final i = Library._();
  List<Song> liked = [];
  List<Song> recent = [];
  List<String> searches = [];

  List<Song> _songs(SharedPreferences p, String k) => (p.getStringList(k) ?? [])
      .map((e) => Song.fromJson(jsonDecode(e) as Map<String, dynamic>))
      .toList();

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    liked = _songs(p, 'liked');
    recent = _songs(p, 'recent');
    searches = p.getStringList('searches') ?? [];
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    List<String> enc(List<Song> l) => l.map((e) => jsonEncode(e.toJson())).toList();
    await p.setStringList('liked', enc(liked));
    await p.setStringList('recent', enc(recent));
    await p.setStringList('searches', searches);
  }

  bool isLiked(Song s) => liked.any((x) => x.id == s.id);

  Future<void> toggle(Song s) async {
    if (isLiked(s)) {
      liked.removeWhere((x) => x.id == s.id);
    } else {
      liked.insert(0, s);
    }
    notifyListeners();
    await _save();
  }

  void addRecent(Song s) {
    recent.removeWhere((x) => x.id == s.id);
    recent.insert(0, s);
    if (recent.length > 20) recent = recent.sublist(0, 20);
    notifyListeners();
    _save();
  }

  void addSearch(String q) {
    searches.removeWhere((x) => x.toLowerCase() == q.toLowerCase());
    searches.insert(0, q);
    if (searches.length > 10) searches = searches.sublist(0, 10);
    notifyListeners();
    _save();
  }

  void removeSearch(String q) {
    searches.remove(q);
    notifyListeners();
    _save();
  }

  void clearSearches() {
    searches = [];
    notifyListeners();
    _save();
  }
}
