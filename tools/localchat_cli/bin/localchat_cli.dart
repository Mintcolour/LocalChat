import 'dart:io';
import 'dart:convert';

import 'package:localchat_cli/localchat_cli.dart';

Future<void> main(List<String> arguments) async {
  stdout.encoding = utf8;
  stderr.encoding = utf8;
  exitCode = await LocalChatCli().run(arguments);
}
