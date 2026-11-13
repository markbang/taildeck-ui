# 国内镜像：source tool/env.sh 后再执行 flutter / dart 命令
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_HOSTED_URL=https://pub.flutter-io.cn
# 本机 Flutter（3.47.9，与 FlClash 一致）；换成你自己的 SDK 路径即可
export PATH="${FLUTTER_HOME:-$HOME/flutter347}/bin:$PATH"
