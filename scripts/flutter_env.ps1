$flutterRoot = Join-Path $env:USERPROFILE ".codex\tools\flutter_3.44.2\flutter"
$androidSdk = Join-Path $env:USERPROFILE ".codex\tools\android-sdk"

$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:PUB_CACHE = "E:\VScode\codex\.pub-cache"
$env:ANDROID_HOME = $androidSdk
$env:ANDROID_SDK_ROOT = $androidSdk
$env:JAVA_HOME = "C:\Program Files\Android\openjdk\jdk-21.0.8"
$env:Path = "$flutterRoot\bin;$env:JAVA_HOME\bin;$androidSdk\platform-tools;$androidSdk\cmdline-tools\latest\bin;$env:Path"

Write-Host "Flutter: $flutterRoot"
Write-Host "Android SDK: $androidSdk"
Write-Host "PUB_CACHE: $env:PUB_CACHE"
