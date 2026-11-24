import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kBase = 'https://nazriya.flirt.web.id/api';
const kKey = 'DARK_RANDD'; // TODO: baad me apne backend me shift karo

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

  factory Song.fromJson(Map<String, dynamic> j) {
    String pick(List<String> ks) {
      for (final k in ks) {
        final v = j[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return '';
    }

    final title = _clean(pick(['title', 'name', 'song']));
    final artist = pick(['uploader', 'artist', 'channel', 'author']);
    var id = pick(['id', 'videoId', 'video_id']);
    if (id.isEmpty) id = '${title}_$artist'.hashCode.toString();
    var thumb = pick(['thumbnail', 'thumb', 'image', 'cover']);
    if (thumb.isEmpty && RegExp(r'^[\w-]{11}$').hasMatch(id)) {
      thumb = 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
    }
    return Song(
        id: id, title: title, artist: artist, thumb: thumb, duration: _dur(j['duration']));
  }

  // 225, "225" ya "3:45" teeno chalenge
  static int _dur(dynamic d) {
    if (d is num) return d.toInt();
    if (d is String) {
      final t = d.trim();
      if (t.contains(':')) {
        var sec = 0;
        for (final x in t.split(':')) {
          sec = sec * 60 + (int.tryParse(x) ?? 0);
        }
        return sec;
      }
      return int.tryParse(t) ?? 0;
    }
    return 0;
  }

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
  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 13) UniversalMusic',
    'Accept': 'application/json',
  };

  static Uri _u(String ep, Map<String, String> p) =>
      Uri.parse('$kBase/$ep').replace(queryParameters: {...p, 'key': kKey});

  // network atak jaye to 2 baar try + timeout, taaki app hang na ho
  static Future<http.Response> _get(Uri u, {int tries = 2}) async {
    Object? err;
    for (var i = 0; i < tries; i++) {
      try {
        final r = await http.get(u, headers: _headers).timeout(const Duration(seconds: 15));
        if (r.statusCode == 200) return r;
        err = Exception('HTTP ${r.statusCode}');
      } catch (e) {
        err = e;
      }
      await Future.delayed(Duration(milliseconds: 400 * (i + 1)));
    }
    throw err ?? Exception('network error');
  }

  // response kisi bhi shape me ho (list / {results} / {data:{...}}) list nikal lo
  static List _list(dynamic d) {
    if (d is List) return d;
    if (d is Map) {
      for (final k in ['results', 'data', 'items', 'result', 'videos', 'songs']) {
        final v = d[k];
        if (v is List) return v;
        if (v is Map) {
          final x = _list(v);
          if (x.isNotEmpty) return x;
        }
      }
    }
    return [];
  }

  static Future<List<Song>> _songs(String ep, Map<String, String> p,
      {int maxSec = 720}) async {
    final r = await _get(_u(ep, p));
    final list = _list(jsonDecode(utf8.decode(r.bodyBytes)));
    return list
        .whereType<Map>()
        .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
        .where((s) => s.title.isNotEmpty)
        // shorts/reviews hatao (duration pata na ho to rakho)
        .where((s) => s.duration == 0 || (s.duration >= 45 && s.duration <= maxSec))
        .toList();
  }

  // API ek baar me kam gaane deti hai, isliye kai variants parallel me mila ke dikhate hain
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
            .replace(queryParameters: {'q': q})).timeout(const Duration(seconds: 12));
        if (r.statusCode != 200) continue;
        for (final e in jsonDecode(r.body) as List) {
          final t = e['plainLyrics'];
          if (t is String && t.trim().isNotEmpty) return t.trim();
        }
      } catch (_) {}
    }
    return null;
  }

  // Naye API me trending endpoint nahi hai, isliye har baar random hit topic search hota hai
  static const _trendQs = [
    'top hindi songs', 'new hindi songs', 'latest bollywood songs', 'trending songs',
    'viral songs', 'bollywood hits', 'arijit singh songs', 'hindi love songs',
    'top punjabi songs', 'new songs this week',
  ];
  static Future<List<Song>> trending() =>
      _songs('search', {'q': _trendQs[Random().nextInt(_trendQs.length)], 'limit': '25'});

  // Naye API me suggest endpoint nahi, isliye search ke titles se suggestions
  static Future<List<String>> suggest(String q) async {
    try {
      final l = await _songs('search', {'q': q, 'limit': '10'}, maxSec: 7200);
      final seen = <String>{};
      return [for (final s in l) if (seen.add(s.title.toLowerCase())) s.title].take(8).toList();
    } catch (_) {
      return [];
    }
  }

  static String audioUrl(Song s) =>
      _u('audio', {'q': '${s.title} ${s.artist}'}).toString();

  static String videoUrl(Song s) =>
      _u('video', {'q': '${s.title} ${s.artist}'}).toString();
}

// ---------- Infinite feed ----------
// API ek baar me ~5 gaane deti hai, isliye ek topic ke kai variants search karke
// naye gaane jodte jate hain (duplicates hata ke).
class Feed {
  final int maxSec;
  final bool shuffle;
  final List<String> variants;
  final Set<String> seen = {};
  int _i = 0;

  // shuffle=true: har baar variants alag order me -> refresh pe naye gaane
  Feed(String base, {List<String>? variants, this.maxSec = 720, this.shuffle = false})
      : variants = List.of(variants ?? _defaults(base)) {
    if (shuffle) this.variants.shuffle();
  }

  bool get done => _i >= variants.length;

  static List<String> _defaults(String q) {
    final y = DateTime.now().year;
    return [
      q, '$q song', '$q new song', '$q official audio', '$q lyrics', '$q latest',
      '$q hit songs', '$q top songs', '$q $y', '$q ${y - 1}', '$q ${y - 2}',
      '$q romantic', '$q sad songs', '$q party', '$q remix', '$q full song',
      '$q jukebox', '$q best of', '$q old songs', '$q mashup', '$q lofi',
      '$q live', '$q video song', '$q unplugged', '$q slowed reverb', '$q dj',
      '$q status', '$q viral', '$q trending', '$q superhit', '$q love songs',
      '$q ${y - 3}', '$q ${y - 4}', '$q audio', '$q music video', '$q acoustic',
    ];
  }

  Future<List<Song>> next({int batch = 4}) async {
    if (done) return [];
    final qs = variants.skip(_i).take(batch).toList();
    _i += qs.length;
    final lists = await Future.wait(qs.map((x) =>
        Api._songs('search', {'q': x, 'limit': '25'}, maxSec: maxSec)
            .catchError((_) => <Song>[])));
    final out = <Song>[];
    for (final l in lists) {
      for (final s in l) {
        if (seen.add(s.id)) out.add(s);
      }
    }
    if (shuffle) out.shuffle();
    return out;
  }
}

class FeedController extends ChangeNotifier {
  FeedController(this.title, this.base,
      {this.first, this.variants, this.maxSec = 720, this.shuffle = false})
      : feed = Feed(base, variants: variants, maxSec: maxSec, shuffle: shuffle);

  final String title, base;
  final List<String>? variants;
  final int maxSec;
  final bool shuffle;
  Feed feed;
  final Future<List<Song>> Function()? first;
  final List<Song> songs = [];
  bool loading = false, loaded = false;
  bool get done => feed.done;

  String get _ck => 'cache_$title';

  // net na ho to pichli baar ke gaane dikha do
  Future<void> _saveCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(
          _ck, songs.take(30).map((e) => jsonEncode(e.toJson())).toList());
    } catch (_) {}
  }

  Future<void> _loadCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final l = (p.getStringList(_ck) ?? [])
          .map((e) => Song.fromJson(jsonDecode(e) as Map<String, dynamic>));
      for (final s in l) {
        if (feed.seen.add(s.id)) songs.add(s);
      }
    } catch (_) {}
  }

  Future<void> loadMore({int target = 0}) async {
    if (loading) return;
    loading = true;
    try {
      var l = <Song>[];
      if (songs.isEmpty && !loaded && first != null) {
        try {
          l = await first!();
        } catch (_) {}
        for (final s in l) {
          feed.seen.add(s.id);
        }
      }
      if (l.isEmpty) l = await feed.next();
      songs.addAll(l);
      notifyListeners();
      while (songs.length < target && !feed.done) {
        songs.addAll(await feed.next());
        notifyListeners();
      }
      if (songs.isNotEmpty) _saveCache();
    } catch (_) {}
    if (songs.isEmpty) {
      await _loadCache();
    }
    loading = false;
    loaded = true;
    notifyListeners();
  }

  // Pull-to-refresh: naya feed (naye random variants) shuru karo
  Future<void> refresh({int target = 10}) async {
    if (loading) return;
    final old = List<Song>.of(songs);
    songs.clear();
    loaded = false;
    feed = Feed(base, variants: variants, maxSec: maxSec, shuffle: true);
    notifyListeners();
    await loadMore(target: target);
    if (songs.isEmpty && old.isNotEmpty) {
      songs.addAll(old);
      notifyListeners();
    }
  }

  Future<List<Song>> fetchNew() async {
    final before = songs.length;
    await loadMore();
    return songs.sublist(before);
  }
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
      if (Library.i.autoplay && i >= queue.length - 3) _extend();
    });
    player.playerStateStream.listen((_) => notifyListeners());
    // network atka to gaana wahin se dobara try karo (2 baar tak)
    player.playbackEventStream.listen((_) => _retries = 0, onError: (Object e, StackTrace st) async {
      if (_retries >= 2 || _cs == null || index < 0) return;
      _retries++;
      try {
        final pos = player.position;
        await Future.delayed(const Duration(seconds: 1));
        await player.setAudioSource(_cs!, initialIndex: index, initialPosition: pos);
        player.play();
      } catch (_) {}
    });
  }
  int _retries = 0;
  static final i = PlayerService._();

  final player = AudioPlayer();
  List<Song> queue = [];
  int index = -1;
  bool shuffle = false;
  LoopMode loop = LoopMode.off;
  Timer? _sleep;
  String source = '';
  ConcatenatingAudioSource? _cs;
  Future<List<Song>> Function()? _more;
  Feed? _related;
  bool _extending = false;

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

  Future<void> playQueue(List<Song> songs, int start,
      {String source = '', Future<List<Song>> Function()? more}) async {
    queue = List.of(songs);
    index = start;
    this.source = source;
    _more = more;
    _related = null;
    notifyListeners();
    try {
      _cs = ConcatenatingAudioSource(children: queue.map(_src).toList());
      await player.setAudioSource(_cs!, initialIndex: start);
      player.play();
    } catch (_) {
      // play nahi hua; UI me spinner band ho jayega
    }
  }

  // Autoplay: queue khatam hone se pehle milte-julte gaane jod do
  Future<void> _extend() async {
    if (_extending || _cs == null) return;
    _extending = true;
    try {
      var l = <Song>[];
      if (_more != null) l = await _more!();
      if (l.isEmpty) {
        final s = current;
        if (s != null) {
          _related ??= Feed(s.title);
          l = await _related!.next();
        }
      }
      final have = queue.map((x) => x.id).toSet();
      l = l.where((x) => have.add(x.id)).toList();
      if (l.isNotEmpty) {
        queue.addAll(l);
        await _cs!.addAll(l.map(_src).toList());
        notifyListeners();
      }
    } catch (_) {}
    _extending = false;
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
  bool autoplay = true;

  List<Song> _songs(SharedPreferences p, String k) => (p.getStringList(k) ?? [])
      .map((e) => Song.fromJson(jsonDecode(e) as Map<String, dynamic>))
      .toList();

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    liked = _songs(p, 'liked');
    recent = _songs(p, 'recent');
    searches = p.getStringList('searches') ?? [];
    autoplay = p.getBool('autoplay') ?? true;
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    List<String> enc(List<Song> l) => l.map((e) => jsonEncode(e.toJson())).toList();
    await p.setStringList('liked', enc(liked));
    await p.setStringList('recent', enc(recent));
    await p.setStringList('searches', searches);
  }

  Future<void> setAutoplay(bool v) async {
    autoplay = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('autoplay', v);
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
