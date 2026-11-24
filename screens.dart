import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:video_player/video_player.dart';
import 'core.dart';

const kAccent = Color(0xFFF43F5E);
const kMaroon = Color(0xFF6B0F1A);
const kCard = Color(0xFF242424);

String fmt(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

void copyLink(BuildContext c, Song s) {
  Clipboard.setData(ClipboardData(text: 'https://youtu.be/${s.id}'));
  ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Link copied')));
}

// YouTube thumbnail 4:3 hota hai (kaali patti ke saath), isliye zoom karke crop
Widget squareArt(String url) => Transform.scale(
      scale: 1.33,
      child: Image.network(url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Container(color: Colors.grey[850], child: const Icon(Icons.music_note))),
    );

class Thumb extends StatelessWidget {
  final String url;
  final double size, radius;
  const Thumb(this.url, this.size, {this.radius = 6, super.key});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(width: size, height: size, child: squareArt(url)),
      );
}

class Header extends StatelessWidget {
  final String text;
  const Header(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Text(text, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
      );
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/icon.png', width: 30, height: 30),
          ),
          const SizedBox(width: 10),
          const Text('Universal Music',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        ]),
      );
}

class SongTile extends StatelessWidget {
  final Song s;
  final VoidCallback onTap;
  const SongTile(this.s, this.onTap, {super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: PlayerService.i,
        builder: (ctx, _) {
          final active = PlayerService.i.current?.id == s.id;
          return ListTile(
            contentPadding: const EdgeInsets.only(left: 16, right: 4),
            leading: Thumb(s.thumb, 46),
            title: Row(children: [
              if (active)
                const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.signal_cellular_alt, color: kAccent, size: 16)),
              Expanded(
                child: Text(s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: active ? kAccent : null)),
              ),
            ]),
            subtitle: Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white60)),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                if (v == 'like') Library.i.toggle(s);
                if (v == 'queue') PlayerService.i.addToQueue(s);
                if (v == 'link') copyLink(ctx, s);
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'like', child: Text(Library.i.isLiked(s) ? 'Unlike' : 'Like')),
                const PopupMenuItem(value: 'queue', child: Text('Add to queue')),
                const PopupMenuItem(value: 'link', child: Text('Copy link')),
              ],
            ),
            onTap: onTap,
          );
        },
      );
}

class SongList extends StatelessWidget {
  final List<Song> songs;
  final String source;
  const SongList(this.songs, {this.source = '', super.key});

  @override
  Widget build(BuildContext context) => ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: songs.length,
        itemBuilder: (_, i) =>
            SongTile(songs[i], () => PlayerService.i.playQueue(songs, i, source: source)),
      );
}

// ---------- Home ----------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _feeds = <FeedController>[
    FeedController('Trending now', 'top hindi songs', first: Api.trending, shuffle: true),
    FeedController('Punjabi hits', 'punjabi songs', shuffle: true),
    FeedController('Haryanvi', 'haryanvi songs', shuffle: true),
    FeedController('Romantic', 'romantic hindi songs', shuffle: true),
    FeedController('Chill', 'lofi hindi songs', shuffle: true),
    FeedController('Bhojpuri', 'bhojpuri songs', shuffle: true),
    FeedController('Old is gold', 'old hindi songs', shuffle: true),
  ];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // 2-2 rows ek saath load hoti hain, jo ready ho wahi dikh jati hai
  Future<void> _loadAll() async {
    for (var i = 0; i < _feeds.length; i += 2) {
      await Future.wait(_feeds.skip(i).take(2).map((f) => f.loadMore(target: 10)));
    }
  }

  // Pull-to-refresh: sab rows naye gaano ke saath dobara load
  Future<void> _refresh() async {
    for (var i = 0; i < _feeds.length; i += 2) {
      await Future.wait(_feeds.skip(i).take(2).map((f) => f.refresh()));
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: RefreshIndicator(
          color: kAccent,
          backgroundColor: const Color(0xFF282828),
          onRefresh: _refresh,
          child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          const BrandHeader(),
          ListenableBuilder(
            listenable: Library.i,
            builder: (_, __) => Library.i.recent.isEmpty
                ? const SizedBox.shrink()
                : SongRow('Recently played', Library.i.recent),
          ),
          for (final f in _feeds)
            ListenableBuilder(
              listenable: f,
              builder: (_, __) => f.songs.isEmpty
                  ? const SizedBox.shrink()
                  : SongRow(f.title, f.songs, ctrl: f),
            ),
          const SizedBox(height: 16),
        ]),
        ),
      );
}

class SongRow extends StatefulWidget {
  final String title;
  final List<Song> songs;
  final FeedController? ctrl;
  const SongRow(this.title, this.songs, {this.ctrl, super.key});
  @override
  State<SongRow> createState() => _SongRowState();
}

class _SongRowState extends State<SongRow> {
  final _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    _sc.addListener(() {
      final c = widget.ctrl;
      if (c != null && _sc.hasClients && _sc.position.pixels > _sc.position.maxScrollExtent - 250) {
        c.loadMore();
      }
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songs = widget.songs;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
        child: Row(children: [
          Expanded(
            child: Text(widget.title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
          ),
          if (widget.ctrl != null)
            TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: Colors.white70, textStyle: const TextStyle(fontSize: 13)),
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => FeedScreen(widget.ctrl!))),
              child: const Text('See all'),
            ),
        ]),
      ),
      SizedBox(
        height: 168,
        child: ListView.builder(
          controller: _sc,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: songs.length,
          itemBuilder: (_, i) {
            final s = songs[i];
            return GestureDetector(
              onTap: () => PlayerService.i
                  .playQueue(songs, i, source: widget.title, more: widget.ctrl?.fetchNew),
              child: Container(
                width: 112,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Thumb(s.thumb, 112, radius: 8),
                  const SizedBox(height: 8),
                  Text(s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  Text(s.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey, fontSize: 11.5)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// "See all" screen: neeche scroll karte raho, gaane aate rahenge
class FeedScreen extends StatelessWidget {
  final FeedController ctrl;
  const FeedScreen(this.ctrl, {super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF121212),
          title: Text(ctrl.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        ),
        body: FeedList(ctrl, key: ObjectKey(ctrl)),
        bottomNavigationBar: const MiniPlayer(),
      );
}

class FeedList extends StatefulWidget {
  final FeedController ctrl;
  const FeedList(this.ctrl, {super.key});
  @override
  State<FeedList> createState() => _FeedListState();
}

class _FeedListState extends State<FeedList> {
  final _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    _sc.addListener(() {
      if (_sc.hasClients && _sc.position.pixels > _sc.position.maxScrollExtent - 400) {
        widget.ctrl.loadMore();
      }
    });
    if (widget.ctrl.songs.isEmpty) widget.ctrl.loadMore(target: 12);
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.ctrl,
        builder: (_, __) {
          final l = widget.ctrl.songs;
          if (l.isEmpty) {
            return Center(
              child: Text(widget.ctrl.loaded ? 'No results' : '',
                  style: const TextStyle(color: Colors.grey)),
            );
          }
          return ListView.builder(
            controller: _sc,
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: l.length,
            itemBuilder: (_, i) => SongTile(
              l[i],
              () => PlayerService.i
                  .playQueue(l, i, source: widget.ctrl.title, more: widget.ctrl.fetchNew),
            ),
          );
        },
      );
}

// ---------- Search ----------
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<String> _suggestions = [];
  FeedController? _main;
  final Map<int, FeedController> _extra = {}; // albums / playlists (current query)
  final Map<int, FeedController> _browse = {}; // search khali ho tab chips ka content
  String _q = '';
  int _filter = 0; // 0 All, 1 Songs, 2 Artists, 3 Albums, 4 Playlists

  static const _labels = ['All', 'Songs', 'Artists', 'Albums', 'Playlists'];
  static const _artists = [
    'Arijit Singh', 'Diljit Dosanjh', 'Sidhu Moose Wala', 'Badshah', 'Neha Kakkar',
    'Shreya Ghoshal', 'AP Dhillon', 'Karan Aujla', 'Yo Yo Honey Singh', 'Jubin Nautiyal',
    'Atif Aslam', 'Sonu Nigam', 'Kumar Sanu', 'Lata Mangeshkar', 'Kishore Kumar',
    'Jasleen Royal', 'Guru Randhawa', 'B Praak', 'Darshan Raval', 'Pritam',
  ];

  FeedController _extraCtrl(int i) => _extra.putIfAbsent(
        i,
        () => FeedController(
          i == 3 ? 'Albums: $_q' : 'Playlists: $_q',
          _q,
          variants: i == 3
              ? ['$_q full album', '$_q album songs', '$_q album jukebox', '$_q audio jukebox', '$_q album']
              : ['$_q playlist', '$_q hits playlist', '$_q top 10 songs', '$_q nonstop songs', '$_q best songs'],
          maxSec: 7200,
        ),
      );

  FeedController _browseCtrl(int i) => _browse.putIfAbsent(i, () {
        if (i == 1) return FeedController('Popular songs', 'top hindi songs');
        if (i == 3) {
          return FeedController('Popular albums', '', maxSec: 7200, variants: [
            'bollywood full album', 'punjabi full album', 'hindi album jukebox',
            'romantic hindi album', 'arijit singh album', 'new album songs', 'haryanvi album',
          ]);
        }
        return FeedController('Popular playlists', '', maxSec: 7200, variants: [
          'bollywood hits playlist', 'punjabi hits playlist', 'romantic songs playlist',
          'party songs playlist', 'sad songs playlist', 'lofi playlist', 'workout songs playlist',
        ]);
      });

  void _search(String q) {
    q = q.trim();
    if (q.isEmpty) return;
    Library.i.addSearch(q);
    FocusScope.of(context).unfocus();
    final c = FeedController('Search: $q', q);
    setState(() {
      _q = q;
      _main = c;
      _extra.clear();
    });
    c.loadMore(target: 12);
    Api.suggest(q).then((s) {
      if (mounted) setState(() => _suggestions = s);
    });
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    setState(() {});
    if (q.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final s = await Api.suggest(q.trim());
      if (mounted) setState(() => _suggestions = s);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Widget _pill(String t, bool sel, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? kAccent : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(t,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: sel ? Colors.black : Colors.white)),
        ),
      );

  Widget _top(Song s, VoidCallback play) => GestureDetector(
        onTap: play,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Thumb(s.thumb, 84, radius: 8),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
                  Text('Song • ${s.artist}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Colors.white70)),
                ]),
              ),
              const SizedBox(width: 12),
              CircleAvatar(
                radius: 24,
                backgroundColor: kAccent,
                child: IconButton(
                  iconSize: 26,
                  icon: const Icon(Icons.play_arrow, color: Colors.white),
                  onPressed: play,
                ),
              ),
            ]),
          ]),
        ),
      );

  Widget _artistList(List<String> names) => ListView(children: [
        for (final n in names)
          ListTile(
            leading: const CircleAvatar(
                radius: 22, backgroundColor: kCard, child: Icon(Icons.person, size: 22)),
            title: Text(n,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: const Text('Artist', style: TextStyle(fontSize: 12)),
            onTap: () {
              _ctrl.text = n;
              setState(() => _filter = 1);
              _search(n);
            },
          ),
      ]);

  Widget _recentSearches() => ListenableBuilder(
        listenable: Library.i,
        builder: (_, __) {
          final l = Library.i.searches;
          if (l.isEmpty) {
            return const Center(
              child: Text('Search for songs or artists', style: TextStyle(color: Colors.grey)),
            );
          }
          return ListView(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(children: [
                const Text('Recent searches',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const Spacer(),
                TextButton(onPressed: Library.i.clearSearches, child: const Text('Clear all')),
              ]),
            ),
            for (final q in l)
              ListTile(
                dense: true,
                leading: const Icon(Icons.history, size: 20),
                title: Text(q, style: const TextStyle(fontSize: 14)),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Library.i.removeSearch(q),
                ),
                onTap: () {
                  _ctrl.text = q;
                  _search(q);
                },
              ),
          ]);
        },
      );

  Widget _results() {
    final typed = _ctrl.text.trim().isNotEmpty;
    final c = _main;
    // search nahi hua: chips ka apna popular content
    if (c == null || !typed) {
      if (_filter == 0) return _recentSearches();
      if (_filter == 2) return _artistList(_artists);
      return FeedList(_browseCtrl(_filter), key: ValueKey('browse$_filter'));
    }
    if (_filter == 1) return FeedList(c, key: ObjectKey(c));
    if (_filter == 3 || _filter == 4) {
      final e = _extraCtrl(_filter);
      return FeedList(e, key: ObjectKey(e));
    }
    if (_filter == 2) {
      return ListenableBuilder(
        listenable: c,
        builder: (_, __) {
          final seen = <String>{};
          return _artistList([for (final s in c.songs) if (seen.add(s.artist)) s.artist]);
        },
      );
    }
    return ListenableBuilder(
      listenable: c,
      builder: (_, __) {
        final songs = c.songs;
        if (songs.isEmpty) {
          return Center(
            child: Text(c.loaded ? 'No results' : '', style: const TextStyle(color: Colors.grey)),
          );
        }
        void play(int i) =>
            PlayerService.i.playQueue(songs, i, source: c.title, more: c.fetchNew);
        return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
          _top(songs.first, () => play(0)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
            child: Row(children: [
              const Text('Songs', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: Colors.white70, textStyle: const TextStyle(fontSize: 13)),
                onPressed: () => setState(() => _filter = 1),
                child: const Text('See all'),
              ),
            ]),
          ),
          for (var i = 0; i < songs.length && i < 6; i++) SongTile(songs[i], () => play(i)),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Header('Search'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _ctrl,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              onChanged: _onChanged,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'What do you want to listen to?',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintStyle: const TextStyle(fontSize: 14),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _ctrl.clear();
                    setState(() {
                      _suggestions = [];
                      _main = null;
                      _extra.clear();
                    });
                  },
                ),
                filled: true,
                fillColor: kCard,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ),
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              children: [
                for (var i = 0; i < _labels.length; i++)
                  _pill(_labels[i], _filter == i, () => setState(() => _filter = i)),
              ],
            ),
          ),
          if (_suggestions.isNotEmpty)
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 16),
                children: [
                  for (final s in _suggestions)
                    _pill(s, false, () {
                      _ctrl.text = s;
                      _search(s);
                    }),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Expanded(child: _results()),
        ]),
      );
}

// ---------- Library ----------
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Header('Your Library'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Liked songs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListenableBuilder(
              listenable: Library.i,
              builder: (_, __) => Library.i.liked.isEmpty
                  ? const Center(child: Text('No liked songs yet'))
                  : SongList(Library.i.liked, source: 'Liked songs'),
            ),
          ),
        ]),
      );
}

// ---------- Mini player ----------
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([PlayerService.i, Library.i]),
        builder: (ctx, _) {
          final p = PlayerService.i;
          final s = p.current;
          if (s == null) return const SizedBox.shrink();
          final liked = Library.i.isLiked(s);
          return GestureDetector(
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute(fullscreenDialog: true, builder: (_) => const NowPlayingScreen()),
            ),
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              decoration: BoxDecoration(color: kMaroon, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                ListTile(
                  dense: true,
                  leading: Thumb(s.thumb, 40),
                  title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white60)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: Icon(liked ? Icons.favorite : Icons.favorite_border,
                          color: liked ? kAccent : null),
                      onPressed: () => Library.i.toggle(s),
                    ),
                    IconButton(
                      icon: Icon(p.player.playing ? Icons.pause : Icons.play_arrow, size: 30),
                      onPressed: p.toggle,
                    ),
                  ]),
                ),
                StreamBuilder<Duration>(
                  stream: p.player.positionStream,
                  builder: (_, snap) {
                    final pos = (snap.data ?? Duration.zero).inSeconds;
                    return LinearProgressIndicator(
                      value: s.duration > 0 ? (pos / s.duration).clamp(0.0, 1.0) : 0,
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      color: kAccent,
                    );
                  },
                ),
              ]),
            ),
          );
        },
      );
}

// ---------- Now playing ----------
class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});
  @override
  State<NowPlayingScreen> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<NowPlayingScreen> {
  Color bg = kMaroon;
  String? _colorFor, _lyricsFor, _lyrics;
  bool _lyricsDone = false, _expanded = false;

  Future<void> _color(Song s) async {
    if (_colorFor == s.id) return;
    _colorFor = s.id;
    try {
      final pg = await PaletteGenerator.fromImageProvider(NetworkImage(s.thumb),
          size: const Size(100, 100));
      final c = pg.darkMutedColor?.color ?? pg.dominantColor?.color;
      if (c != null && mounted) setState(() => bg = c);
    } catch (_) {}
  }

  void _loadLyrics(Song s) {
    if (_lyricsFor == s.id) return;
    _lyricsFor = s.id;
    _lyrics = null;
    _lyricsDone = false;
    Api.lyrics(s.title, s.artist).then((l) {
      if (mounted && _lyricsFor == s.id) {
        setState(() {
          _lyrics = l;
          _lyricsDone = true;
        });
      }
    });
  }

  Widget _lyricsCard() => Container(
        margin: const EdgeInsets.only(top: 24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Color.lerp(bg, Colors.black, .25),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.lyrics_outlined),
            const SizedBox(width: 12),
            const Text('Lyrics', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const Spacer(),
            if (_lyrics != null)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'COLLAPSE' : 'EXPAND'),
              ),
          ]),
          const SizedBox(height: 8),
          if (!_lyricsDone)
            const SizedBox.shrink()
          else if (_lyrics == null)
            const Text('Lyrics not found', style: TextStyle(color: Colors.white70))
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: _expanded ? double.infinity : 90),
              child: ClipRect(
                child: Text(_lyrics!,
                    style: const TextStyle(fontSize: 15, height: 1.5, fontWeight: FontWeight.w500)),
              ),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([PlayerService.i, Library.i]),
        builder: (ctx, _) {
          final p = PlayerService.i;
          final s = p.current;
          if (s == null) {
            return const Scaffold(body: Center(child: Text('Nothing is playing')));
          }
          _color(s);
          _loadLyrics(s);
          final st = p.player.processingState;
          final loading = st == ProcessingState.loading || st == ProcessingState.buffering;
          final liked = Library.i.isLiked(s);

          return Scaffold(
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [bg, const Color(0xFF0E0E0E)],
                  stops: const [0, .6],
                ),
              ),
              child: SafeArea(
                child: ListView(padding: const EdgeInsets.symmetric(horizontal: 24), children: [
                  Row(children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down, size: 34),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                    Expanded(
                      child: Column(children: [
                        Text(p.source.startsWith('Search') ? 'PLAYING FROM SEARCH' : 'PLAYING FROM',
                            style: TextStyle(letterSpacing: 1.5, fontSize: 11, color: Colors.white70)),
                        Text(p.source.isEmpty ? 'Now playing' : p.source,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                      ]),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (v) {
                        if (v == 'autoplay') {
                          Library.i.setAutoplay(!Library.i.autoplay);
                        } else {
                          copyLink(ctx, s);
                        }
                      },
                      itemBuilder: (_) => [
                        CheckedPopupMenuItem<String>(
                          value: 'autoplay',
                          checked: Library.i.autoplay,
                          child: const Text('Autoplay'),
                        ),
                        const PopupMenuItem(value: 'link', child: Text('Copy link')),
                      ],
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: squareArt(s.thumb),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w500)),
                        Text(s.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, color: Colors.white70)),
                      ]),
                    ),
                    IconButton(
                      iconSize: 30,
                      icon: Icon(liked ? Icons.favorite : Icons.favorite_border,
                          color: liked ? kAccent : null),
                      onPressed: () => Library.i.toggle(s),
                    ),
                  ]),
                  StreamBuilder<Duration>(
                    stream: p.player.positionStream,
                    builder: (_, snap) {
                      final pos = snap.data ?? Duration.zero;
                      final total =
                          (p.player.duration ?? Duration(seconds: s.duration)).inMilliseconds;
                      final v = pos.inMilliseconds.clamp(0, total).toDouble();
                      return Column(children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 8,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                            overlayShape: SliderComponentShape.noOverlay,
                            trackShape: const RoundedRectSliderTrackShape(),
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white24,
                          ),
                          child: Slider(
                            value: v,
                            max: total <= 0 ? 1 : total.toDouble(),
                            onChanged: (x) => p.player.seek(Duration(milliseconds: x.toInt())),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [Text(fmt(pos.inSeconds)), Text(fmt(total ~/ 1000))],
                          ),
                        ),
                      ]);
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    IconButton(
                      icon: Icon(Icons.shuffle, color: p.shuffle ? kAccent : null),
                      onPressed: p.toggleShuffle,
                    ),
                    IconButton(iconSize: 34, icon: const Icon(Icons.skip_previous), onPressed: p.prev),
                    GestureDetector(
                      onTap: p.toggle,
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.white,
                        child: loading
                            ? const CircularProgressIndicator(color: Colors.black)
                            : Icon(p.player.playing ? Icons.pause : Icons.play_arrow,
                                color: Colors.black, size: 36),
                      ),
                    ),
                    IconButton(iconSize: 34, icon: const Icon(Icons.skip_next), onPressed: p.next),
                    IconButton(
                      icon: Icon(p.loop == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                          color: p.loop == LoopMode.off ? null : kAccent),
                      onPressed: p.cycleLoop,
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    PopupMenuButton<int>(
                      icon: const Icon(Icons.bedtime_outlined),
                      tooltip: 'Sleep timer',
                      onSelected: (m) => p.setSleep(m == 0 ? null : m),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 15, child: Text('15 min')),
                        PopupMenuItem(value: 30, child: Text('30 min')),
                        PopupMenuItem(value: 60, child: Text('60 min')),
                        PopupMenuItem(value: 0, child: Text('Off')),
                      ],
                    ),
                    IconButton(icon: const Icon(Icons.share), onPressed: () => copyLink(ctx, s)),
                    IconButton(
                      icon: const Icon(Icons.videocam_outlined),
                      tooltip: 'Video',
                      onPressed: () => Navigator.push(
                          ctx, MaterialPageRoute(builder: (_) => VideoScreen(s))),
                    ),
                    IconButton(
                      icon: const Icon(Icons.queue_music),
                      onPressed: () => showModalBottomSheet(
                        context: ctx,
                        backgroundColor: const Color(0xFF1A1A1A),
                        builder: (_) => SongList(PlayerService.i.queue, source: p.source),
                      ),
                    ),
                  ]),
                  _lyricsCard(),
                  const SizedBox(height: 32),
                ]),
              ),
            ),
          );
        },
      );
}


// ---------- Video ----------
class VideoScreen extends StatefulWidget {
  final Song song;
  const VideoScreen(this.song, {super.key});
  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late final VideoPlayerController _c;
  bool _error = false, _full = false;

  @override
  void initState() {
    super.initState();
    PlayerService.i.player.pause(); // audio band, video chalu
    _c = VideoPlayerController.networkUrl(Uri.parse(Api.videoUrl(widget.song)));
    _c.addListener(() {
      if (mounted) setState(() {});
    });
    _c.initialize().then((_) {
      if (mounted) {
        setState(() {});
        _c.play();
      }
    }).catchError((_) {
      if (mounted) setState(() => _error = true);
    });
  }

  void _toggleFull() {
    _full = !_full;
    SystemChrome.setPreferredOrientations(_full
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(
        _full ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    setState(() {});
  }

  @override
  void dispose() {
    _c.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _full
          ? null
          : AppBar(
              backgroundColor: Colors.black,
              title: Text(widget.song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
      body: Center(
        child: _error
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text("Couldn't load the video", textAlign: TextAlign.center),
              )
            : !v.isInitialized
                ? const CircularProgressIndicator()
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Flexible(
                      child: AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(_c)),
                    ),
                    VideoProgressIndicator(_c,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(playedColor: kAccent)),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton(
                        iconSize: 32,
                        icon: const Icon(Icons.replay_10),
                        onPressed: () => _c.seekTo(v.position - const Duration(seconds: 10)),
                      ),
                      IconButton(
                        iconSize: 52,
                        icon: Icon(v.isPlaying ? Icons.pause_circle : Icons.play_circle),
                        onPressed: () => v.isPlaying ? _c.pause() : _c.play(),
                      ),
                      IconButton(
                        iconSize: 32,
                        icon: const Icon(Icons.forward_10),
                        onPressed: () => _c.seekTo(v.position + const Duration(seconds: 10)),
                      ),
                      IconButton(
                        icon: Icon(_full ? Icons.fullscreen_exit : Icons.fullscreen),
                        onPressed: _toggleFull,
                      ),
                    ]),
                  ]),
      ),
    );
  }
}
