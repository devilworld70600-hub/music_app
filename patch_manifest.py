import glob
import os
import re
import shutil
import sys

p = sys.argv[1]
s = open(p, encoding="utf-8").read()

# tools namespace
if "xmlns:tools" not in s:
    s = s.replace("<manifest ", '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)

perms = """
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
"""
s = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + perms, s, count=1)

# app ka naam
s = re.sub(r'android:label="[^"]*"', 'android:label="Universal Music"', s, count=1)

# audio service activity
s = s.replace('android:name=".MainActivity"',
              'android:name="com.ryanheise.audioservice.AudioServiceActivity"')

extra = """
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService"/>
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON"/>
            </intent-filter>
        </receiver>
"""
s = s.replace("</application>", extra + "    </application>", 1)
open(p, "w", encoding="utf-8").write(s)

# Android lint release build me crash kar raha tha (LintDriver error), isliye lint band
app_dir = os.path.dirname(os.path.dirname(os.path.dirname(p)))
for name in ("build.gradle.kts", "build.gradle"):
    g = os.path.join(app_dir, name)
    if os.path.exists(g):
        t = open(g, encoding="utf-8").read()
        if "checkReleaseBuilds" not in t:
            t = re.sub(
                r"^android\s*\{",
                "android {\n    lint {\n        checkReleaseBuilds = false\n        abortOnError = false\n    }\n",
                t, count=1, flags=re.M)
            open(g, "w", encoding="utf-8").write(t)
        print("patched gradle:", g)
        break
else:
    print("WARNING: build.gradle not found in", app_dir)

# Inter font (repo root me Inter-*.otf ho to) app me jod do
proj = os.path.dirname(os.path.dirname(app_dir))  # .../app
fonts = sorted(glob.glob("Inter-*.otf"))
if fonts:
    os.makedirs(os.path.join(proj, "assets"), exist_ok=True)
    entries = ""
    for f in fonts:
        shutil.copy(f, os.path.join(proj, "assets", f))
        w = 600 if "SemiBold" in f else 500 if "Medium" in f else 400
        entries += "        - asset: assets/%s\n          weight: %d\n" % (f, w)
    pp = os.path.join(proj, "pubspec.yaml")
    t = open(pp, encoding="utf-8").read()
    t = t.replace("  uses-material-design: true\n",
                  "  uses-material-design: true\n  fonts:\n    - family: Inter\n      fonts:\n" + entries, 1)
    open(pp, "w", encoding="utf-8").write(t)
    print("fonts added:", fonts)
else:
    print("no Inter fonts found, default font use hoga")

# Notification ka chhota icon: adaptive launcher icon ki jagah simple white music note
res = os.path.join(app_dir, "src", "main", "res")
os.makedirs(os.path.join(res, "drawable"), exist_ok=True)
open(os.path.join(res, "drawable", "ic_stat_music.xml"), "w", encoding="utf-8").write(
    '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
    '    android:width="24dp" android:height="24dp"\n'
    '    android:viewportWidth="24" android:viewportHeight="24">\n'
    '    <path android:fillColor="#FFFFFFFF"\n'
    '        android:pathData="M12,3v10.55c-0.59,-0.34 -1.27,-0.55 -2,-0.55 -2.21,0 -4,1.79 -4,4s1.79,4 4,4 4,-1.79 4,-4V7h4V3h-6z"/>\n'
    '</vector>\n')
# resource shrinker is icon ko hata na de (wo sirf naam se load hota hai)
os.makedirs(os.path.join(res, "raw"), exist_ok=True)
open(os.path.join(res, "raw", "keep.xml"), "w", encoding="utf-8").write(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<resources xmlns:tools="http://schemas.android.com/tools"\n'
    '    tools:keep="@drawable/ic_stat_music,@mipmap/ic_launcher" />\n')

# debugging: final manifest build log me dikhao
print("=== FINAL MANIFEST ===")
print(open(p, encoding="utf-8").read())
